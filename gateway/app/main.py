"""FastAPI 网关入口：登录 / 监控 / 控制 / 反向代理 / SSE 事件推送。"""
import asyncio
import gzip
import json
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, WebSocket, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse, HTMLResponse, FileResponse, StreamingResponse, Response
from fastapi.staticfiles import StaticFiles

from . import auth, config, dsh_manager, events, monitor, proxy, sessions


@asynccontextmanager
async def lifespan(app: FastAPI):
    tasks = [
        asyncio.create_task(proxy.question_watcher()),
        asyncio.create_task(events.status_watcher()),
        asyncio.create_task(events.session_watcher()),
    ]
    yield
    for t in tasks:
        t.cancel()


app = FastAPI(title="DSH Remote Gateway", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

_PUBLIC_PREFIXES = ("/static", "/dashboard", "/favicon.ico")


@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    path = request.url.path
    is_public = path.startswith(_PUBLIC_PREFIXES) or path == "/gw/login"
    if not is_public and not auth.is_authed(request):
        if path.startswith("/gw/") or path.startswith("/api/") or path.startswith("/plugins/"):
            return JSONResponse({"ok": False, "detail": "未登录或会话已过期"}, status_code=401)
        return RedirectResponse("/dashboard", status_code=302)
    return await call_next(request)


class GzipJsonMiddleware:
    """纯 ASGI 中间件：对 application/json 的完整响应做 gzip（中文文本体积 -80%）。
    SSE（text/event-stream）与其他流式响应立即放行，绝不缓冲。"""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        accept = ""
        for k, v in scope.get("headers", []):
            if k == b"accept-encoding":
                accept = v.decode("latin-1", "replace").lower()
        if "gzip" not in accept:
            await self.app(scope, receive, send)
            return

        state = {"mode": "probe", "status": 200, "headers": [], "chunks": []}

        async def send_wrapper(message):
            mtype = message["type"]
            if mtype == "http.response.start":
                state["status"] = message["status"]
                state["headers"] = list(message.get("headers") or [])
                ct = ""
                ce = ""
                for k, v in state["headers"]:
                    kl = k.decode("latin-1", "replace").lower()
                    if kl == "content-type":
                        ct = v.decode("latin-1", "replace").lower()
                    elif kl == "content-encoding":
                        ce = v.decode("latin-1", "replace").lower()
                if "application/json" in ct and not ce and state["status"] == 200:
                    state["mode"] = "buffer"
                else:
                    state["mode"] = "passthrough"
                    await send(message)
            elif mtype == "http.response.body":
                if state["mode"] == "buffer":
                    state["chunks"].append(message.get("body", b""))
                    if not message.get("more_body", False):
                        await self._flush(send, state)
                else:
                    await send(message)

        await self.app(scope, receive, send_wrapper)

    async def _flush(self, send, state):
        raw = b"".join(state["chunks"])
        out_headers = []
        for k, v in state["headers"]:
            if k.decode("latin-1", "replace").lower() == "content-length":
                continue
            out_headers.append((k, v))
        if len(raw) > 500:
            body = gzip.compress(raw, 5)
            out_headers.append((b"content-encoding", b"gzip"))
            out_headers.append((b"vary", b"Accept-Encoding"))
        else:
            body = raw
        await send({"type": "http.response.start", "status": state["status"], "headers": out_headers})
        await send({"type": "http.response.body", "body": body})


@app.exception_handler(HTTPException)
async def http_exc_handler(request: Request, exc: HTTPException):
    if exc.status_code == 401:
        if request.url.path.startswith("/gw/"):
            return JSONResponse({"ok": False, "detail": exc.detail}, status_code=401)
        return RedirectResponse("/dashboard", status_code=302)
    return JSONResponse({"ok": False, "detail": exc.detail}, status_code=exc.status_code)


# ---------- 登录 ----------
@app.post("/gw/login")
async def login(request: Request):
    data = await request.json()
    ip = auth.client_ip(request)
    if auth._is_locked(ip):
        config.audit("login.blocked", f"ip={ip}")
        raise HTTPException(status_code=429, detail="尝试次数过多，请稍后再试")
    candidate = str(data.get("password", ""))
    if not auth.check_password(candidate):
        auth.record_failure(ip)
        config.audit("login.fail", f"ip={ip}")
        raise HTTPException(status_code=401, detail="密码错误")
    auth.clear_failures(ip)
    config.audit("login.ok", f"ip={ip}")
    resp = JSONResponse({"ok": True})
    auth.set_session_cookie(resp, auth.create_token())
    return resp


@app.post("/gw/logout")
async def logout():
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(auth.COOKIE_NAME, path="/")
    return resp


@app.get("/gw/session")
async def session_info(request: Request):
    return {"ok": True, "authed": auth.is_authed(request)}


# ---------- 监控 ----------
@app.get("/gw/status")
async def get_status():
    st = monitor.status()
    st.update(dsh_manager.info())
    return st


@app.get("/gw/sessions")
async def get_sessions(limit: int = 50):
    return {"ok": True, "sessions": sessions.list_sessions(limit)}


@app.get("/gw/session/{sid}/tail")
async def get_session_tail(sid: str, n: int = 40, unchanged: int = 0):
    return sessions.session_tail(sid, min(n, 100), unchanged_size=unchanged or None)


@app.post("/gw/session/{sid}/send")
async def send_to_session(sid: str, request: Request):
    data = await request.json()
    text = str(data.get("text", "")).strip()
    if not text:
        raise HTTPException(status_code=400, detail="内容为空")
    if not monitor.dsh_running():
        raise HTTPException(status_code=503, detail="DSH 未运行")
    r = await sessions.send_prompt(sid, text, str(data.get("tz", "Asia/Shanghai")))
    if not r.get("ok"):
        raise HTTPException(status_code=502, detail=f"发送失败（HTTP {r.get('status')}）")
    return {"ok": True, "accepted": r.get("accepted", False)}


@app.get("/gw/questions")
async def get_pending_questions(sid: str):
    return {"ok": True, "questions": proxy.pending_questions(sid)}


@app.post("/gw/session/{sid}/answer")
async def answer_question(sid: str, request: Request):
    import httpx

    data = await request.json()
    rpc_id = str(data.get("rpcId", ""))
    answers = data.get("answers")
    if not rpc_id or not isinstance(answers, list) or not answers:
        raise HTTPException(status_code=400, detail="参数错误")
    if not monitor.dsh_running():
        raise HTTPException(status_code=503, detail="DSH 未运行")
    body = {
        "type": "client-response",
        "rpcId": rpc_id,
        "result": {
            "ok": True,
            "value": {"sessionId": sid, "answer": {"answers": answers}},
        },
    }
    headers = {
        "Host": f"{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
        "Origin": f"http://{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(f"{config.DSH_WEB_BASE}/api/respond",
                                 json=body, headers=headers)
    try:
        ok = bool(resp.json().get("accepted"))
    except (ValueError, AttributeError):
        ok = False
    if not ok:
        raise HTTPException(status_code=502, detail=f"应答失败（HTTP {resp.status_code}）")
    config.audit("question.answer", f"sid={sid} rpc={rpc_id[:12]}")
    return {"ok": True}


@app.get("/gw/log")
async def get_log(n: int = 300):
    return {"ok": True, "log": monitor.read_dsh_log(min(n, 2000))}


# ---------- SSE 事件推送（移动 App 订阅） ----------
def _sse(ev: dict) -> str:
    return "data: " + json.dumps(ev, ensure_ascii=False) + "\n\n"


@app.get("/gw/events")
async def gw_events(request: Request):
    if not auth.is_authed(request):
        raise HTTPException(status_code=401, detail="未登录或会话已过期")

    async def gen():
        # 补发历史：只发状态类事件与 60 秒内的新鲜事件。
        # 旧的选择题事件不重放，避免 App 每次连接重复弹旧通知。
        yield _sse({"type": "hello", "data": {"ts": time.time()}})
        now = time.time()
        for ev in events.history():
            if ev.get("type") == "status" or now - ev.get("ts", 0) < 60:
                yield _sse(ev)
        q = events.subscribe()
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    ev = await asyncio.wait_for(q.get(), timeout=15.0)
                except asyncio.TimeoutError:
                    ev = {"type": "heartbeat", "data": {"ts": time.time()}}
                yield _sse(ev)
        finally:
            events.unsubscribe(q)

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"},
    )


# ---------- 控制 ----------
@app.post("/gw/control/{action}")
async def control(action: str):
    if action == "start":
        r = dsh_manager.start()
    elif action == "stop":
        r = dsh_manager.stop()
    elif action == "restart":
        r = dsh_manager.restart()
    else:
        raise HTTPException(status_code=400, detail="未知操作")
    if not r.get("ok"):
        raise HTTPException(status_code=500, detail=r.get("detail", "操作失败"))
    return r


# ---------- 仪表盘 ----------
@app.get("/dashboard")
async def dashboard():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/favicon.ico")
async def favicon():
    return HTMLResponse("", status_code=200)


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


# ---------- 反向代理（DSH 原版 UI，挂根路径） ----------
@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy_root(request: Request, path: str):
    if path.startswith("gw/") or path.startswith("static/"):
        return JSONResponse({"ok": False, "detail": "not found"}, status_code=404)
    return await proxy.proxy_http(request, path)


@app.websocket("/{path:path}")
async def proxy_ws(ws: WebSocket, path: str):
    if not auth.is_authed(ws):
        await ws.close(code=1008)
        return
    await proxy.proxy_websocket(ws, path)


# 注册 gzip 压缩中间件（最后注册 = 最外层，保证拿到最终响应字节）
app.add_middleware(GzipJsonMiddleware)
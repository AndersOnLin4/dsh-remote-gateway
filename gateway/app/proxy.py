"""反向代理到 DSH (127.0.0.1:3080)，重写 Host/Origin 通过 browser-trust fence。"""
import gzip
import json
import time

import httpx
from fastapi import Request
from fastapi.responses import HTMLResponse, Response, StreamingResponse

from . import config, monitor

_client = httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=3.0), follow_redirects=False)

_DROP_REQ_HEADERS = {
    "host", "origin", "connection", "content-length", "transfer-encoding",
    "upgrade", "keep-alive", "proxy-connection", "proxy-authenticate",
    "proxy-authorization", "te",
}
_DROP_RESP_HEADERS = {
    "connection", "content-length", "transfer-encoding", "keep-alive",
    "upgrade", "proxy-authenticate", "proxy-authorization", "te",
}

_MAX_COMPRESS = 4 * 1024 * 1024
_COMPRESSIBLE = ("text/", "application/json", "application/javascript",
                 "application/xml", "application/xhtml+xml", "application/wasm")

_UNAVAILABLE_HTML = """<!doctype html><html lang="zh"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DSH 未运行</title>
<body style="font-family:system-ui;max-width:480px;margin:40px auto;padding:0 16px">
<h2>DSH 未运行</h2>
<p>Harness 后台当前没有在运行。</p>
<p><a href="/dashboard">前往仪表盘查看状态或启动它</a></p>
</body></html>"""

# 注入到 DSH 首页：修复 HTTP 下 crypto.randomUUID 缺失 + 移动端适配样式 + 返回仪表盘按钮
_INJECT_MARK = "<!--dsh-gw-inject-->"
_INJECT_HTML = _INJECT_MARK + """<style>
@media (max-width: 700px) {
  html, body { -webkit-text-size-adjust: 100%; }
  textarea, input, [contenteditable="true"] { font-size: 16px !important; }
  [class*="_composerSeat"] {
    position: fixed !important;
    left: 52px !important;
    right: 0 !important;
    top: auto !important;
    bottom: 0 !important;
    z-index: 40 !important;
    padding-bottom: env(safe-area-inset-bottom) !important;
  }
  [class*="_scrollBody"] { padding-bottom: 120px !important; }
  [class*="_detailsCol"] { display: none !important; }
  [class*="_sidebarCol"] { transition: none !important; }
  [class*="_frame"] { transition: none !important; }
  [class*="_frame"]:not([data-sidebar-collapsed]) {
    grid-template-columns: 100vw minmax(0px, 1fr) 0px !important;
  }
  [class*="_frame"]:not([data-sidebar-collapsed]) [class*="_footArea"] {
    display: none !important;
  }
  [class*="_frame"]:not([data-sidebar-collapsed]) [class*="_regionArea"] {
    flex: 1 1 auto !important; height: auto !important; min-height: 0 !important;
  }
  [class*="_composerSeat"] { left: 0 !important; }
  [class$="_callRow"] { display: none !important; }
  [class*="_overlayLayer"] [class*="notice"] { max-height: 60vh; overflow-y: auto; }
}
</style>
<script>
(function(){
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID !== 'function') {
      crypto.randomUUID = function() {
        var b = crypto.getRandomValues(new Uint8Array(16));
        b[6] = (b[6] & 0x0f) | 0x40;
        b[8] = (b[8] & 0x3f) | 0x80;
        var h = '';
        for (var i = 0; i < 16; i++) h += (b[i] < 16 ? '0' : '') + b[i].toString(16);
        return h.substr(0,8)+'-'+h.substr(8,4)+'-'+h.substr(12,4)+'-'+h.substr(16,4)+'-'+h.substr(20);
      };
    }
  } catch (e) {}
  var d = document;
  var box = d.createElement('div');
  box.style.cssText = 'position:fixed;right:12px;bottom:84px;z-index:99999;font:13px/1 system-ui;';
  var a = d.createElement('a');
  a.href = '/dashboard';
  a.textContent = '\u4eea\u8868\u76d8';
  a.style.cssText = 'display:inline-block;padding:8px 12px;border-radius:8px;background:rgba(20,22,28,.92);color:#fff;text-decoration:none;box-shadow:0 2px 8px rgba(0,0,0,.35);';
  box.appendChild(a);
  if (d.body) { d.body.appendChild(box); }
  else { d.addEventListener('DOMContentLoaded', function(){ d.body.appendChild(box); }); }

  // 手机端：侧边栏展开时整屏显示会话列表（跟随 React 状态，不写内联样式），并提供返回按钮
  var _back = null;
  var _extrasDone = false;
  function _applySidebar() {
    var frame = d.querySelector('[class*="_frame"]');
    var expanded = frame && !frame.hasAttribute('data-sidebar-collapsed') && window.innerWidth <= 700;
    if (expanded) {
      if (!_back) {
        _back = d.createElement('div');
        _back.textContent = '\u2039 \u8fd4\u56de';
        _back.style.cssText = 'position:fixed;top:calc(10px + env(safe-area-inset-top));left:12px;z-index:100;padding:8px 14px;border-radius:20px;background:rgba(20,22,28,.92);color:#fff;font:14px/1 system-ui;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.35);';
        _back.onclick = function(){
          var col = d.querySelector('[class*="_sidebarCol"]');
          var t = col && col.querySelector('[class*="_toggle"]');
          if (t) t.click();
        };
        d.body.appendChild(_back);
      }
      _moveSettingsTop(frame);
    } else if (_back) {
      _back.remove();
      _back = null;
    }
  }
  // 设置按钮从底部挪到顶部（复制图标，点击转发给原按钮）
  function _moveSettingsTop(frame) {
    if (_extrasDone) return;
    var logoRow = frame.querySelector('[class*="_logoRow"]');
    var settingsArea = frame.querySelector('[class*="_settingsArea"]');
    if (!logoRow || !settingsArea) return;
    var orig = settingsArea.querySelector('button');
    if (!orig) return;
    _extrasDone = true;
    var btn = d.createElement('button');
    btn.title = orig.getAttribute('title') || '\u8bbe\u7f6e';
    btn.setAttribute('aria-label', btn.title);
    btn.style.cssText = 'background:none;border:none;color:inherit;cursor:pointer;padding:4px;display:inline-flex;align-items:center;';
    btn.innerHTML = orig.innerHTML;
    btn.onclick = function(){ orig.click(); };
    logoRow.appendChild(btn);
  }
  // 点击会话后自动收起侧边栏，并抑制切换时的输入法弹出（DSH 会自动聚焦输入框）
  var _suppressFocus = false;
  d.addEventListener('click', function(e){
    var row = e.target && e.target.closest ? e.target.closest('[class*="_sessionRow"]') : null;
    if (row && window.innerWidth <= 700) {
      _suppressFocus = true;
      setTimeout(function(){ _suppressFocus = false; }, 1500);
      setTimeout(function(){
        var f = d.querySelector('[class*="_frame"]');
        if (f && !f.hasAttribute('data-sidebar-collapsed')) {
          var t = d.querySelector('[class*="_sidebarCol"] [class*="_toggle"]');
          if (t) t.click();
        }
      }, 200);
    }
  }, true);
  d.addEventListener('focusin', function(e){
    if (_suppressFocus && e.target &&
        (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT')) {
      e.target.blur();
    }
  }, true);
  setInterval(_applySidebar, 300);
  d.addEventListener('resize', _applySidebar);
  _applySidebar();
})();
</script>"""

# 预加载：在 __DSH_BOOT__ 定义后立刻并行拉取所有插件包
_PRELOAD_HTML = """<script>
(function(){
  try {
    var boot = window.__DSH_BOOT__;
    if (boot && boot.entries) {
      for (var i = 0; i < boot.entries.length; i++) {
        var u = boot.entries[i].url;
        if (u) {
          var l = document.createElement('link');
          l.rel = 'preload'; l.as = 'script'; l.href = u;
          document.head.appendChild(l);
        }
      }
    }
  } catch (e) {}
})();
</script>"""


def _public_base(request: Request) -> str:
    scheme = request.headers.get("x-forwarded-proto") or request.url.scheme
    host = request.headers.get("host") or f"localhost:{config.PORT}"
    return f"{scheme}://{host}"


# 历史数据过滤：去掉思考/工具/流式碎片/上下文注入，只留对话正文
_DROP_HISTORY_EVENTS = {
    "assistant/chunk", "reasoning-chunks", "tool-call-chunks", "text-chunks",
    "tool/call", "tool/result", "agent/inbox/spliced",
}


def _keep_text_parts(content):
    if not isinstance(content, list):
        return content
    return [p for p in content if isinstance(p, dict) and p.get("type") == "text"]


def _filter_history_json(data):
    try:
        value = data["result"]["value"]
        events = value["events"]
    except (KeyError, TypeError):
        return data
    kept = []
    for item in events:
        ev = item.get("event") or {}
        if ev.get("type") in _DROP_HISTORY_EVENTS:
            continue
        if ev.get("type") == "user/message":
            src = (ev.get("data") or {}).get("source") or {}
            if src.get("kind") != "user":
                continue  # 上下文注入（skill-catalog 等）不是真实提问
        d = ev.get("data") or {}
        if isinstance(d.get("content"), list):
            d["content"] = _keep_text_parts(d.get("content"))
        msg = d.get("message")
        if isinstance(msg, dict) and isinstance(msg.get("content"), list):
            msg["content"] = _keep_text_parts(msg.get("content"))
        kept.append(item)
    value["events"] = kept
    return data


# 实时流中的挂起选择题：rpcId -> {sessionId, questions, time}
PENDING_QUESTIONS: dict = {}


def track_ws_frame(text: str) -> None:
    """在转发 WebSocket 下行帧时记录挂起的选择题（用于仪表盘应答）。"""
    try:
        obj = json.loads(text)
    except (ValueError, TypeError):
        return
    payload = obj.get("payload")
    if not isinstance(payload, dict):
        return
    ptype = payload.get("type")
    if ptype == "question/requested":
        PENDING_QUESTIONS[obj.get("rpcId")] = {
            "sessionId": payload.get("sessionId"),
            "questions": payload.get("questions") or [],
            "time": time.time(),
        }
    elif ptype == "question/resolved":
        PENDING_QUESTIONS.pop(payload.get("questionRpcId"), None)


def pending_questions(session_id: str, max_age: float = 1800):
    """返回某会话当前挂起的选择题列表。"""
    now = time.time()
    out = []
    for rpc_id, q in list(PENDING_QUESTIONS.items()):
        if q.get("sessionId") != session_id:
            continue
        if now - q.get("time", 0) > max_age:
            continue
        out.append({"rpcId": rpc_id, "questions": q.get("questions") or []})
    return out


async def question_watcher():
    """常驻监听 DSH 的 mux 事件流，捕获挂起的选择题（回放与实时）。"""
    import asyncio
    import websockets

    while True:
        try:
            async with websockets.connect(
                f"{config.DSH_WS_BASE}/api/events.mux",
                origin=f"http://{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
                max_size=64 * 1024 * 1024,
                open_timeout=10.0,
            ) as ws:
                async for msg in ws:
                    if isinstance(msg, str):
                        track_ws_frame(msg)
        except Exception:
            pass
        await asyncio.sleep(3)


def _inject_html_text(text: str) -> str:
    """注入 polyfill、移动端按钮与插件预加载。"""
    s_close = text.find("</script>")
    if s_close != -1:
        end = s_close + len("</script>")
        text = text[:end] + _PRELOAD_HTML + text[end:]
    if "<head>" in text:
        text = text.replace("<head>", "<head>" + _INJECT_HTML, 1)
    elif "</head>" in text:
        text = text.replace("</head>", _INJECT_HTML + "</head>", 1)
    else:
        text = _INJECT_HTML + text
    return text


def _finish(body: bytes, resp_headers, accept_gzip: bool, media_type: str = None):
    """包装响应：可选 gzip 压缩。返回 Response。"""
    resp_headers.pop("content-length", None)
    resp_headers.pop("content-encoding", None)
    ct = media_type or resp_headers.get("content-type") or "application/octet-stream"
    if accept_gzip and len(body) > 1024 and any(t in ct.lower() for t in _COMPRESSIBLE):
        gz = gzip.compress(body)
        if len(gz) < len(body):
            body = gz
            resp_headers["content-encoding"] = "gzip"
    resp_headers["content-type"] = ct
    return Response(content=body, status_code=200, headers=resp_headers)


def _maybe_compress_stream(upstream, resp_headers, accept_gzip: bool):
    """对非 HTML 的可压缩文本做 gzip；不需要/不适合时返回 None 走流式。"""
    if not accept_gzip or upstream.status_code != 200:
        return None
    ct = resp_headers.get("content-type", "").lower()
    if not any(t in ct for t in _COMPRESSIBLE):
        return None
    clen = upstream.headers.get("content-length")
    if clen is not None:
        try:
            if int(clen) > _MAX_COMPRESS:
                return None
        except ValueError:
            return None
    return True  # 需要缓冲整个 body


async def proxy_http(request: Request, path: str):
    if not monitor.dsh_running():
        return HTMLResponse(_UNAVAILABLE_HTML, status_code=502)

    headers = {k: v for k, v in request.headers.items() if k.lower() not in _DROP_REQ_HEADERS}
    headers["Host"] = f"{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}"
    if request.headers.get("origin"):
        headers["Origin"] = f"http://{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}"

    body = await request.body()
    url = f"{config.DSH_WEB_BASE}/{path}" if path else config.DSH_WEB_BASE
    try:
        upstream = await _client.request(
            request.method, url,
            headers=headers, content=body,
            params=request.query_params,
        )
    except httpx.HTTPError:
        return HTMLResponse(_UNAVAILABLE_HTML, status_code=502)

    resp_headers = {k: v for k, v in upstream.headers.items() if k.lower() not in _DROP_RESP_HEADERS}
    loc = resp_headers.get("location")
    if loc and config.DSH_WEB_BASE in loc:
        resp_headers["location"] = loc.replace(config.DSH_WEB_BASE, _public_base(request))

    # 静态资源缓存策略：带 rev 版本号的资源永久缓存；首页 HTML 不缓存
    ct = resp_headers.get("content-type", "").lower()
    if request.method in ("GET", "HEAD"):
        if path.startswith("plugins/") or path.startswith("assets/") or "rev=" in request.url.query:
            resp_headers["cache-control"] = "public, max-age=31536000, immutable"
        elif "text/html" in ct:
            resp_headers["cache-control"] = "no-cache"

    accept_gzip = "gzip" in request.headers.get("accept-encoding", "").lower()
    is_html = upstream.status_code == 200 and "text/html" in ct

    # 会话历史：数据层过滤（去掉思考/工具/碎片），大幅缩小响应体积
    if request.method == "POST" and path == "api/session.history" and upstream.status_code == 200:
        chunks = [c async for c in upstream.aiter_bytes()]
        raw = b"".join(chunks)
        try:
            data = json.loads(raw)
            data = _filter_history_json(data)
            out = json.dumps(data, ensure_ascii=False).encode("utf-8")
            resp_headers.pop("content-length", None)
            resp_headers.pop("content-encoding", None)
            resp_headers["content-type"] = "application/json; charset=utf-8"
            return Response(content=out, status_code=200, headers=resp_headers)
        except (ValueError, TypeError):
            return StreamingResponse(upstream.aiter_bytes(), status_code=200, headers=resp_headers)

    if is_html or (_maybe_compress_stream(upstream, resp_headers, accept_gzip) is not None):
        chunks = [c async for c in upstream.aiter_bytes()]
        data = b"".join(chunks)
        if is_html:
            text = data.decode("utf-8", errors="replace")
            if _INJECT_MARK not in text:
                text = _inject_html_text(text)
            return _finish(text.encode("utf-8"), resp_headers, accept_gzip, "text/html; charset=utf-8")
        return _finish(data, resp_headers, accept_gzip)
    return StreamingResponse(upstream.aiter_bytes(), status_code=upstream.status_code, headers=resp_headers)


async def proxy_websocket(ws, path: str):
    from fastapi import WebSocketDisconnect
    import websockets

    if not monitor.dsh_running():
        await ws.close(code=1011)
        return

    query = ws.query_params
    url = f"{config.DSH_WS_BASE}/{path}"
    if query:
        url += f"?{query}"

    subprotocols = list(ws.scope.get("subprotocols") or [])
    await ws.accept()

    try:
        async with websockets.connect(
            url,
            origin=f"http://{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
            subprotocols=subprotocols or None,
            max_size=64 * 1024 * 1024,
            open_timeout=10.0,
            close_timeout=5.0,
        ) as upstream:
            async def pump_down():
                async for msg in upstream:
                    if isinstance(msg, bytes):
                        await ws.send_bytes(msg)
                    else:
                        track_ws_frame(msg)
                        await ws.send_text(msg)

            async def pump_up():
                while True:
                    msg = await ws.receive()
                    kind = msg.get("type")
                    if kind == "websocket.receive":
                        if msg.get("bytes") is not None:
                            await upstream.send(msg["bytes"])
                        else:
                            await upstream.send(msg.get("text") or "")
                    elif kind in ("websocket.disconnect", "websocket.close"):
                        break

            import asyncio
            tasks = [asyncio.create_task(pump_down()), asyncio.create_task(pump_up())]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
            for t in done:
                try:
                    t.result()
                except Exception:
                    pass
    except Exception as exc:
        import traceback
        print(f"[ws-proxy] {path} upstream error: {type(exc).__name__}: {exc}", flush=True)
        traceback.print_exc()
    finally:
        try:
            await ws.close(code=1000)
        except (WebSocketDisconnect, RuntimeError):
            pass
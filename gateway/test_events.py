"""SSE 事件推送验证：① in-process 广播链路（track_ws_frame → events.broadcast → 订阅者）
② 对运行中网关的传输链路（登录 → GET /gw/events → hello/status/heartbeat）。
用法：.venv\\Scripts\\python test_events.py（需 TEST_GATEWAY 指向运行中的网关，默认 8090）"""
import asyncio
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

GATEWAY = os.environ.get("TEST_GATEWAY", "http://127.0.0.1:8090")


async def test_inprocess():
    from app import events, proxy

    q = events.subscribe()
    frame = json.dumps({
        "rpcId": "test-rpc-123",
        "payload": {
            "type": "question/requested",
            "sessionId": "test-session",
            "questions": [{"id": "q1", "question": "测试问题", "options": [{"label": "A"}, {"label": "B"}]}],
        },
    })
    proxy.track_ws_frame(frame)
    try:
        ev = await asyncio.wait_for(q.get(), timeout=2.0)
    except asyncio.TimeoutError:
        events.unsubscribe(q)
        return False, "未收到 question 广播"
    finally:
        events.unsubscribe(q)
    ok = ev.get("type") == "question" and ev["data"].get("rpcId") == "test-rpc-123"
    return ok, json.dumps(ev, ensure_ascii=False)


async def test_transport():
    import httpx

    env = {}
    with open(os.path.join(os.path.dirname(__file__), ".env"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                env[k] = v
    async with httpx.AsyncClient(timeout=10.0) as client:
        r = await client.post(f"{GATEWAY}/gw/login", json={"password": env.get("GATEWAY_PASSWORD", "")})
        if r.status_code != 200:
            return False, f"login http {r.status_code}"
        token = None
        for c in r.headers.get("set-cookie", "").split(","):
            c = c.strip()
            if c.startswith("gw_session="):
                token = c.split(";")[0].split("=", 1)[1]
        if not token:
            return False, "login 未返回 gw_session Cookie"
        seen = []
        deadline = time.time() + 20
        async with client.stream(
            "GET", f"{GATEWAY}/gw/events", headers={"Cookie": f"gw_session={token}"}
        ) as resp:
            if resp.status_code != 200:
                return False, f"events http {resp.status_code}"
            async for line in resp.aiter_lines():
                if line.startswith("data: "):
                    ev = json.loads(line[6:])
                    seen.append(ev.get("type"))
                    if "hello" in seen and "status" in seen:
                        break
                if time.time() > deadline:
                    break
        return ("hello" in seen and "status" in seen), seen


async def main():
    ok1, d1 = await test_inprocess()
    print("in-process 广播链路:", "PASS" if ok1 else "FAIL", d1)
    ok2, d2 = await test_transport()
    print("SSE 传输链路:", "PASS" if ok2 else "FAIL", d2)
    print("RESULT:", "ALL PASS" if ok1 and ok2 else "FAILED")


if __name__ == "__main__":
    asyncio.run(main())

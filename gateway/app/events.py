"""SSE 事件总线：状态推送 / 选择题事件广播，供移动 App 订阅（/gw/events）。

设计：进程内发布订阅 + 小环形历史（新连接先补发最近事件）。
生产者为 status_watcher（每 3 秒探活，变化才广播）与 proxy.track_ws_frame（选择题捕获）。
"""
import asyncio
import json
import time

from . import config, dsh_manager, monitor

_subs: set = set()
_history: list = []
MAX_HISTORY = 50


def broadcast(etype: str, data) -> None:
    ev = {"type": etype, "data": data, "ts": time.time()}
    _history.append(ev)
    del _history[:-MAX_HISTORY]
    for q in list(_subs):
        try:
            q.put_nowait(ev)
        except asyncio.QueueFull:
            pass


def subscribe() -> asyncio.Queue:
    q = asyncio.Queue(maxsize=200)
    _subs.add(q)
    return q


def unsubscribe(q) -> None:
    _subs.discard(q)


def history() -> list:
    return list(_history)


async def status_watcher():
    """每 3 秒探测一次 DSH 状态，变化时广播 status 事件。"""
    last = None
    while True:
        try:
            st = monitor.status()
            st.update(dsh_manager.info())
            snap = {
                "running": bool(st.get("running")),
                "session_count": st.get("session_count"),
                "latest_activity": st.get("latest_activity"),
                "latest_workspace": st.get("latest_workspace"),
                "started_by_gateway": bool(st.get("started_by_gateway")),
            }
            key = json.dumps(snap, sort_keys=True, default=str)
            if key != last:
                last = key
                broadcast("status", snap)
        except Exception:
            pass
        await asyncio.sleep(3)


async def session_watcher():
    """每 3 秒扫描会话文件的 mtime，发现新写入即广播 session-updated。
    App 收到后立刻刷新对应会话详情——新消息秒级同步，无需依赖轮询节奏。"""
    last_mtime: dict = {}
    initialized = False
    while True:
        try:
            cur: dict = {}
            root = config.SESSIONS_DIR
            if root.exists():
                for ws in root.iterdir():
                    if not ws.is_dir():
                        continue
                    for sid in ws.iterdir():
                        if not sid.is_dir():
                            continue
                        f = sid / "session.jsonl.zstd"
                        if f.exists():
                            try:
                                cur[sid.name] = f.stat().st_mtime
                            except OSError:
                                pass
            if initialized:
                for sid, mt in cur.items():
                    if sid in last_mtime and mt > last_mtime[sid] + 0.001:
                        broadcast("session-updated", {"sid": sid, "lastActivity": mt})
            last_mtime = cur
            initialized = True
        except Exception:
            pass
        await asyncio.sleep(3)

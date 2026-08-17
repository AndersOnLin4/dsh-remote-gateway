"""轻量会话读取：列表（索引缓存）+ 尾段重要节点提取（只解压尾部帧）。
性能优化：session_tail 结果按 (sid, 文件大小, mtime, n) 缓存；
调用方传 unchanged_size（上次拿到的文件大小），文件未变化时返回轻量 unchanged 响应。"""
import glob
import json
import os
import threading
import time
import uuid

import httpx
import zstandard

from . import config

_ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
_TAIL_BYTES = 1024 * 1024          # 尾段读取上限
_WORKING_WINDOW = 120              # 文件 2 分钟内有过写入视为"活跃"
_TEXT_LIMIT = 4000                 # 单条文本上限
_TOOL_LIMIT = 200                  # 工具结果截断

_dctx = zstandard.ZstdDecompressor()

# tail 结果缓存：会话文件只追加，按 (sid, size, mtime, n) 精确失效
_TAIL_CACHE: dict = {}
_TAIL_CACHE_LOCK = threading.Lock()
_TAIL_CACHE_MAX = 64


def _read_json(path):
    try:
        with open(path, "rb") as f:
            return json.loads(f.read().decode("utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        return None


def _find_session_file(session_id: str):
    for f in glob.glob(str(config.SESSIONS_DIR / "*" / session_id / "session.jsonl.zstd")):
        return f
    return None


def _workspace_titles() -> dict:
    """cwd(路径) -> 工作区显示名。"""
    data = _read_json(config.DSH_HOME / "storages" / "workspace.json")
    out = {}
    if data:
        for ws in (data.get("tables", {}).get("workspaces", {}) or {}).values():
            if ws.get("path"):
                out[ws["path"]] = ws.get("title") or os.path.basename(ws["path"])
    return out


def list_sessions(limit: int = 50):
    """会话摘要：标题/工作区/最后活动/轮数/token/是否活跃。全部来自索引缓存，不读会话大文件。"""
    cache = _read_json(config.DSH_HOME / "storages" / "session_projcache.json")
    ws_titles = _workspace_titles()
    now = time.time()
    sessions = []
    if cache:
        for sid, entry in (cache.get("tables", {}).get("sessions", {}) or {}).items():
            rows = entry.get("rows", {}) or {}
            stats = (rows.get("sessionStats", {}) or {}).get("val", {}) or {}
            f = _find_session_file(sid)
            mtime = os.path.getmtime(f) if f else None
            cwd = (entry.get("identity", {}) or {}).get("cwd")
            working = bool(stats.get("openStep") is not None
                           or stats.get("pendingCalls")
                           or (mtime and now - mtime < _WORKING_WINDOW))
            sessions.append({
                "id": sid,
                "title": (rows.get("title", {}) or {}).get("val") or "",
                "workspace": ws_titles.get(cwd) or (os.path.basename(cwd) if cwd else ""),
                "cwd": cwd or "",
                "lastActivity": mtime,
                "working": working,
                "turns": stats.get("turns") or 0,
                "steps": stats.get("steps") or 0,
                "decodeTokens": stats.get("decodeTokens") or 0,
                "pendingCalls": bool(stats.get("pendingCalls")),
            })
    sessions.sort(key=lambda s: s["lastActivity"] or 0, reverse=True)
    return sessions[:limit]


def _extract_text_parts(content):
    """从 content 数组里取 type==text 的文本（跳过 reasoning 等）。"""
    if not isinstance(content, list):
        return ""
    return "\n".join(p.get("text", "") for p in content
                      if isinstance(p, dict) and p.get("type") == "text" and p.get("text"))


def session_tail(session_id: str, n: int = 40, unchanged_size=None):
    """读取会话末尾一段，只返回：用户提问 + 每轮最终中文回复 + 选择题。
    思考/工具细节在服务端过滤，不传到手机。"""
    f = _find_session_file(session_id)
    if not f:
        return {"ok": False, "detail": "会话不存在"}
    try:
        st = os.stat(f)
        file_size = st.st_size
        file_mtime = st.st_mtime
    except OSError:
        return {"ok": False, "detail": "读取失败"}

    # 增量协议：文件大小未变 → 轻量响应（App 保留已有 entries）
    if unchanged_size is not None and unchanged_size == file_size:
        return {"ok": True, "unchanged": True, "file_size": file_size, "entries": [], "filtered": {}}

    key = (session_id, file_size, file_mtime, n)
    with _TAIL_CACHE_LOCK:
        cached = _TAIL_CACHE.get(key)
    if cached is not None:
        return dict(cached)

    try:
        with open(f, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - _TAIL_BYTES))
            data = fh.read()
    except OSError:
        return {"ok": False, "detail": "读取失败"}
    if not data:
        result = {"ok": True, "unchanged": False, "file_size": file_size,
                  "entries": [], "filtered": {"thinking": 0, "tools": 0, "other": 0}}
        with _TAIL_CACHE_LOCK:
            _TAIL_CACHE[key] = result
        return dict(result)
    start = data.find(_ZSTD_MAGIC)
    if start < 0:
        return {"ok": False, "detail": "数据格式异常"}
    try:
        raw = _dctx.decompressobj(read_across_frames=True).decompress(data[start:])
    except zstandard.ZstdError:
        return {"ok": False, "detail": "解压失败"}

    entries = []
    filtered = {"thinking": 0, "tools": 0, "other": 0}
    for line in raw.split(b"\n"):
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = ev.get("type")
        data_ev = ev.get("data") or {}
        if t == "user/message":
            src = data_ev.get("source") or {}
            if src.get("kind") != "user":
                filtered["other"] += 1
                continue
            text = _extract_text_parts(data_ev.get("content"))
            if text:
                entries.append({"role": "user", "time": ev.get("time"), "text": text[:_TEXT_LIMIT]})
        elif t == "assistant/message":
            text = _extract_text_parts((data_ev.get("message") or {}).get("content"))
            if text:
                entries.append({"role": "assistant", "turn": data_ev.get("turn"),
                                "time": ev.get("time"), "text": text[:_TEXT_LIMIT]})
            else:
                filtered["thinking"] += 1  # 只有思考没有正文的回复
        elif t == "tool/call" and data_ev.get("name") == "ask_user_question":
            qs = []
            try:
                qs = (json.loads(data_ev.get("arguments") or "{}") or {}).get("questions") or []
            except json.JSONDecodeError:
                pass
            if qs:
                lines = []
                for i, q in enumerate(qs, 1):
                    lines.append(f"{i}. {q.get('question') or q.get('header') or q.get('id')}")
                    for o in (q.get("options") or []):
                        lines.append(f"   - {o.get('label')}")
                entries.append({"role": "question", "time": ev.get("time"),
                                "text": "\n".join(lines), "questions": qs})
            else:
                filtered["tools"] += 1
        elif t in ("reasoning-chunks", "tool-call-chunks", "assistant/chunk", "text-chunks"):
            filtered["thinking"] += 1
        elif t in ("tool/call", "tool/result", "command/run", "command/done"):
            filtered["tools"] += 1
        elif t not in ("session", "permission/preset", "sandbox/mode", "approval/policy",
                       "agent-preset/selected", "goal/change", "request/header", "request/context",
                       "step/start", "step/end", "turn/start", "turn/end", "agent/inbox/spliced",
                       "session/end-seed"):
            filtered["other"] += 1

    # 每轮只保留最后一条助手回复（缩减为最终回答）
    result = []
    seen_turns = set()
    for e in reversed(entries):
        if e["role"] == "assistant":
            t = e.get("turn")
            if t is not None and t in seen_turns:
                continue
            if t is not None:
                seen_turns.add(t)
        result.append(e)
    result.reverse()
    out = {"ok": True, "unchanged": False, "file_size": file_size,
           "entries": result[-n:], "filtered": filtered}
    with _TAIL_CACHE_LOCK:
        if len(_TAIL_CACHE) >= _TAIL_CACHE_MAX:
            _TAIL_CACHE.clear()
        _TAIL_CACHE[key] = out
    return dict(out)


async def send_prompt(session_id: str, text: str, tz: str = "Asia/Shanghai"):
    """向 DSH 的既有会话发一条消息（复刻 Web UI 的 session.prompt RPC）。"""
    body = {
        "type": "client-request",
        "rpcId": str(uuid.uuid4()),
        "method": "session.prompt",
        "payload": {
            "sessionId": session_id,
            "mode": "queue",
            "content": [{"type": "text", "text": text}],
            "clientTimeZone": tz or "Asia/Shanghai",
        },
    }
    headers = {
        "Host": f"{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
        "Origin": f"http://{config.DSH_WEB_HOST}:{config.DSH_WEB_PORT}",
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(f"{config.DSH_WEB_BASE}/api/session.prompt",
                                 json=body, headers=headers)
    try:
        data = resp.json()
        ok = bool(data.get("result", {}).get("ok"))
        return {"ok": ok, "accepted": bool(data.get("result", {}).get("value", {}).get("accepted")),
                "status": resp.status_code}
    except (ValueError, AttributeError):
        return {"ok": False, "status": resp.status_code}
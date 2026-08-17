"""只读监控：端口探测 / 会话列表 / 日志读取。"""
import re
import socket
import time

from . import config

_WS_NAME_RE = re.compile(r"~([0-9A-Fa-f]{4})")


def decode_workspace_name(name: str) -> str:
    """把 DSH 的工作区目录名（如 --G-~9879~76EE--）解码为可读名称。"""
    try:
        decoded = _WS_NAME_RE.sub(lambda m: chr(int(m.group(1), 16)), name)
        return decoded.strip("-").replace("--", "/") or name
    except (ValueError, OverflowError):
        return name


def is_port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


# ---- DSH 探活（防抖 + 拒绝/超时区分） ----
# DSH 事件循环繁忙时 listen backlog 塞满 → 连接"超时"（活着但忙）；
# 端口无监听 → 连接被"拒绝"（真死了）。
# 非强制：只有"拒绝"计入判死（连续 4 次，约 10 秒）；超时一律视为存活，避免繁忙期误报"未运行"。
# 强制（控制路径启停用）：单次探测立即定生死，不吃防抖——否则"启动"按钮会在 DSH
# 真的停机时误判"已在运行"而没有反应。
_PROBE = {"running": True, "fails": 0, "at": 0.0}
_PROBE_INTERVAL = 2.0
_PROBE_FAILS_TO_DOWN = 4


def _probe_refused() -> bool:
    try:
        s = socket.create_connection((config.DSH_WEB_HOST, config.DSH_WEB_PORT), timeout=1.5)
        s.close()
        return False
    except ConnectionRefusedError:
        return True
    except OSError:
        return False  # 超时等瞬态 → 视为存活（繁忙）


def probe_dsh(force: bool = False) -> bool:
    now = time.time()
    if not force and now - _PROBE["at"] < _PROBE_INTERVAL:
        return _PROBE["running"]
    refused = _probe_refused()
    if force:
        # 控制路径：单次探测立即定生死
        _PROBE["running"] = not refused
        _PROBE["fails"] = 0 if not refused else _PROBE["fails"]
        _PROBE["at"] = now
        return _PROBE["running"]
    if not refused:
        _PROBE["fails"] = 0
        _PROBE["running"] = True
    else:
        _PROBE["fails"] += 1
        if _PROBE["fails"] >= _PROBE_FAILS_TO_DOWN:
            _PROBE["running"] = False
    _PROBE["at"] = now
    return _PROBE["running"]


def dsh_running(force: bool = False) -> bool:
    return probe_dsh(force)


def list_sessions(limit: int = 50):
    """列出各工作区下最近的会话文件（大小 / 最后活动时间）。"""
    sessions: list[dict] = []
    root = config.SESSIONS_DIR
    if root.exists():
        try:
            for ws in root.iterdir():
                if not ws.is_dir():
                    continue
                for sid in ws.iterdir():
                    if not sid.is_dir():
                        continue
                    f = sid / "session.jsonl.zstd"
                    if f.exists():
                        st = f.stat()
                        sessions.append({
                            "workspace": decode_workspace_name(ws.name),
                            "id": sid.name,
                            "size": st.st_size,
                            "mtime": st.st_mtime,
                        })
        except OSError:
            pass
    sessions.sort(key=lambda s: s["mtime"], reverse=True)
    return sessions[:limit]


def tail_file(path, n: int = 200) -> str:
    """读取文本文件末尾 n 行。"""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            block = 4096
            data = b""
            pos = size
            while pos > 0 and len(data.splitlines()) <= n + 8:
                pos = max(0, pos - block)
                f.seek(pos)
                chunk = f.read(block)
                data = chunk + data
                if len(data) > 2 * 1024 * 1024:
                    break
        text = data.decode("utf-8", errors="replace")
        lines = text.splitlines()
        return "\n".join(lines[-n:])
    except OSError:
        return ""


def read_dsh_log(n: int = 300) -> str:
    return tail_file(config.DSH_LOG_FILE, n)


def status():
    running = dsh_running()
    sessions = list_sessions()
    return {
        "running": running,
        "dsh_url": config.DSH_WEB_BASE,
        "session_count": len(sessions),
        "latest_activity": sessions[0]["mtime"] if sessions else None,
        "latest_workspace": sessions[0]["workspace"] if sessions else None,
        "now": time.time(),
    }
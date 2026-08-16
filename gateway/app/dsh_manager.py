"""DSH 进程托管：检测 / 启动 / 停止 / 重启，stdout 落盘日志。"""
import os
import subprocess
import time

from . import config, monitor

PROC = None          # 本网关拉起的 dsh 子进程
STARTED_AT = None    # 本网关拉起的时间戳

_NODE_PATH = str(config.NODE_EXE)
_DSH_BIN_PATH = str(config.DSH_BIN)


def _base_env() -> dict:
    env = os.environ.copy()
    env.update({
        "NPM_CONFIG_PREFIX": str(config.HARNESS_ROOT / "npm"),
        "NPM_CONFIG_CACHE": str(config.HARNESS_ROOT / "npm-cache"),
        "DSH_HOME": str(config.DSH_HOME),
        "PATH": f"{config.HARNESS_ROOT / 'nodejs'};{config.HARNESS_ROOT / 'npm'};" + env.get("PATH", ""),
    })
    return env


def _started_by_us() -> bool:
    return PROC is not None and PROC.poll() is None


def start() -> dict:
    global PROC, STARTED_AT
    if monitor.dsh_running():
        return {"ok": True, "already": True, "detail": "DSH 已在运行"}
    config.LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = open(config.DSH_LOG_FILE, "ab")
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    cmd = [_NODE_PATH, _DSH_BIN_PATH, "--profile", "web",
           "--host", "127.0.0.1", "--port", str(config.DSH_WEB_PORT)]
    try:
        PROC = subprocess.Popen(
            cmd, cwd=str(config.HARNESS_ROOT), env=_base_env(),
            stdout=log_file, stderr=subprocess.STDOUT, creationflags=flags,
        )
    except OSError as exc:
        return {"ok": False, "detail": f"启动失败: {exc}"}
    STARTED_AT = time.time()
    config.audit("dsh.start", f"pid={PROC.pid}")
    return {"ok": True, "already": False, "pid": PROC.pid}


def stop() -> dict:
    """按端口找到监听进程并结束（无论谁启动的）。"""
    global PROC, STARTED_AT
    if not monitor.dsh_running():
        return {"ok": True, "detail": "DSH 未在运行"}
    ps = (
        "Get-NetTCPConnection -LocalPort {port} -State Listen -ErrorAction SilentlyContinue "
        "| Select-Object -First 1 | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force }}"
    ).format(port=config.DSH_WEB_PORT)
    try:
        subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
            capture_output=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        pass
    if PROC is not None and PROC.poll() is None:
        try:
            PROC.terminate()
        except OSError:
            pass
    PROC = None
    STARTED_AT = None
    # 等待端口释放
    for _ in range(50):
        if not monitor.dsh_running():
            break
        time.sleep(0.1)
    config.audit("dsh.stop", "")
    return {"ok": True, "detail": "已停止"}


def restart() -> dict:
    stop()
    time.sleep(0.5)
    return start()


def info() -> dict:
    return {
        "running": monitor.dsh_running(),
        "started_by_gateway": _started_by_us(),
        "port": config.DSH_WEB_PORT,
    }
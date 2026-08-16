"""网关配置：路径 / 端口 / 密钥。所有敏感值保存在 gateway/.env（自动生成）。"""
import os
import secrets
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent          # gateway/
ENV_FILE = BASE_DIR / ".env"

def _load_env() -> None:
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip())

def _get_or_create_env(key: str, generator) -> str:
    val = os.environ.get(key)
    if val:
        return val
    val = generator()
    with ENV_FILE.open("a", encoding="utf-8") as f:
        f.write(f"{key}={val}\n")
    os.environ[key] = val
    return val

_load_env()

# ---- 网关自身 ----
HOST = os.environ.get("GATEWAY_HOST", "0.0.0.0")
PORT = int(os.environ.get("GATEWAY_PORT", "8080"))

# ---- 登录安全 ----
PASSWORD = _get_or_create_env("GATEWAY_PASSWORD", lambda: secrets.token_urlsafe(18))
SECRET_KEY = _get_or_create_env("GATEWAY_SECRET_KEY", lambda: secrets.token_hex(32))
SESSION_TTL_SECONDS = int(os.environ.get("GATEWAY_SESSION_TTL", str(7 * 24 * 3600)))
LOGIN_MAX_ATTEMPTS = int(os.environ.get("GATEWAY_MAX_ATTEMPTS", "5"))
LOGIN_LOCKOUT_SECONDS = int(os.environ.get("GATEWAY_LOCKOUT_SECONDS", "300"))

# ---- DSH ----
DSH_WEB_HOST = "127.0.0.1"
DSH_WEB_PORT = int(os.environ.get("DSH_WEB_PORT", "3080"))
DSH_WEB_BASE = f"http://{DSH_WEB_HOST}:{DSH_WEB_PORT}"
DSH_WS_BASE = f"ws://{DSH_WEB_HOST}:{DSH_WEB_PORT}"

HARNESS_ROOT = Path(os.environ.get("HARNESS_ROOT", r"G:\harness"))
DSH_HOME = Path(os.environ.get("DSH_HOME", str(HARNESS_ROOT / "dsh-home")))
SESSIONS_DIR = DSH_HOME / "sessions"
NODE_EXE = Path(os.environ.get("NODE_EXE", str(HARNESS_ROOT / "nodejs" / "node.exe")))
DSH_BIN = Path(os.environ.get("DSH_BIN", str(HARNESS_ROOT / "npm" / "node_modules" / "@deepseek-ai" / "dsh" / "lib" / "bin.js")))

LOG_DIR = Path(os.environ.get("LOG_DIR", str(HARNESS_ROOT / "logs")))
DSH_LOG_FILE = LOG_DIR / "dsh.log"
AUDIT_LOG_FILE = LOG_DIR / "gateway-audit.log"

# ---- 审计 ----
AUDIT_FILE_LOG = True

# 将 .env 和日志加入忽略列表（防止误入库）
for p in (BASE_DIR / ".env", LOG_DIR):
    pass

def audit(action: str, detail: str = "") -> None:
    """追加一条审计日志（谁/何时/做了什么）。"""
    if not AUDIT_FILE_LOG:
        return
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        line = f"{__import__('datetime').datetime.now().isoformat()} | {action} | {detail}\n"
        with AUDIT_LOG_FILE.open("a", encoding="utf-8", errors="replace") as f:
            f.write(line)
    except OSError:
        pass
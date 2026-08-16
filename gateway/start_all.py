"""一键启动：先拉起 DSH（若未运行），再启动网关。"""
import sys
import time

from pathlib import Path

from app import config

LOG = config.LOG_DIR / "gateway.out.log"
LOG.parent.mkdir(parents=True, exist_ok=True)
try:
    f = open(LOG, "a", encoding="utf-8")
    sys.stdout = f
    sys.stderr = f
except OSError:
    pass

from app import dsh_manager, monitor

if __name__ == "__main__":
    if not monitor.dsh_running():
        print("[start_all] DSH 未运行，正在启动…", flush=True)
        r = dsh_manager.start()
        print("[start_all]", r, flush=True)
        for _ in range(60):
            if monitor.dsh_running():
                break
            time.sleep(1)
    else:
        print("[start_all] DSH 已在运行", flush=True)

    import uvicorn

    uvicorn.run("app.main:app", host=config.HOST, port=config.PORT, log_level="info")
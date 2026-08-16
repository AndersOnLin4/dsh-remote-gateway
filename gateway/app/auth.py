"""登录鉴权：HMAC 签名会话 Cookie + 失败限速。"""
import base64
import hashlib
import hmac
import json
import time
import threading

from fastapi import Request, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse

from . import config

COOKIE_NAME = "gw_session"
_ATTEMPTS: dict[str, list[float]] = {}          # ip -> [fail_times]
_ATTEMPTS_LOCK = threading.Lock()


def _sign(payload: bytes) -> bytes:
    return hmac.new(config.SECRET_KEY.encode(), payload, hashlib.sha256).digest()


def create_token(ttl: int = None) -> str:
    ttl = ttl or config.SESSION_TTL_SECONDS
    payload = json.dumps({"exp": time.time() + ttl}).encode()
    raw = base64.urlsafe_b64encode(payload).rstrip(b"=")
    sig = base64.urlsafe_b64encode(_sign(raw)).rstrip(b"=")
    return f"{raw.decode()}.{sig.decode()}"


def verify_token(token: str) -> bool:
    try:
        raw_b64, sig_b64 = token.split(".")
        raw = raw_b64.encode()
        sig = base64.urlsafe_b64decode(sig_b64 + "=" * (-len(sig_b64) % 4))
        if not hmac.compare_digest(_sign(raw), sig):
            return False
        raw_padded = (raw_b64 + "=" * (-len(raw_b64) % 4)).encode()
        payload = json.loads(base64.urlsafe_b64decode(raw_padded))
        return payload.get("exp", 0) > time.time()
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        return False


def set_session_cookie(response, token: str) -> None:
    response.set_cookie(
        COOKIE_NAME, token,
        max_age=config.SESSION_TTL_SECONDS,
        httponly=True, samesite="lax", path="/",
    )


def is_authed(request: Request) -> bool:
    token = request.cookies.get(COOKIE_NAME)
    return bool(token) and verify_token(token)


def client_ip(request: Request) -> str:
    if request.client:
        return request.client.host or "?"
    return "?"


def _is_locked(ip: str) -> bool:
    with _ATTEMPTS_LOCK:
        fails = [t for t in _ATTEMPTS.get(ip, [])
                 if time.time() - t < config.LOGIN_LOCKOUT_SECONDS]
        if fails:
            _ATTEMPTS[ip] = fails
        return len(fails) >= config.LOGIN_MAX_ATTEMPTS


def record_failure(ip: str) -> None:
    with _ATTEMPTS_LOCK:
        _ATTEMPTS.setdefault(ip, []).append(time.time())


def clear_failures(ip: str) -> None:
    with _ATTEMPTS_LOCK:
        _ATTEMPTS.pop(ip, None)


def check_password(candidate: str) -> bool:
    return hmac.compare_digest(candidate.encode(), config.PASSWORD.encode())


def require_auth(request: Request):
    if not is_authed(request):
        raise HTTPException(status_code=401, detail="未登录或会话已过期")


def redirect_if_not_authed(request: Request):
    if not is_authed(request):
        return RedirectResponse("/dashboard", status_code=302)
    return None
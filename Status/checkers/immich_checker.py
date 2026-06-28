# checkers/immich_checker.py — Immich service health checker
# Created: 2026-06-28 UTC — checks /api/server/ping (liveness) and
# /api/server/version (detail) using x-api-key from config.IMMICH_CONFIG.
# Ping requires no auth; version requires API key. If no key configured,
# reports ping-only status.

import time
import requests
from config import IMMICH_CONFIG


def check(tailscale_name: str, port: int, timeout_ms: int, **kwargs) -> dict:
    start = time.monotonic()
    timeout_s = timeout_ms / 1000
    base_url = f"http://{tailscale_name}:{port}"
    cfg = IMMICH_CONFIG.get(tailscale_name, {})
    api_key = cfg.get("api_key", "")

    def elapsed():
        return round((time.monotonic() - start) * 1000)

    try:
        r = requests.get(f"{base_url}/api/server/ping", timeout=timeout_s)
        if r.status_code != 200:
            return {"status": "down", "response_time_ms": elapsed(), "detail": f"ping HTTP {r.status_code}"}
        body = r.json()
        if body.get("res") != "pong":
            return {"status": "down", "response_time_ms": elapsed(), "detail": f"unexpected ping response: {body}"}
    except requests.exceptions.ConnectionError:
        return {"status": "down", "response_time_ms": elapsed(), "detail": "connection refused"}
    except requests.exceptions.Timeout:
        return {"status": "down", "response_time_ms": elapsed(), "detail": "timeout"}
    except Exception as e:
        return {"status": "down", "response_time_ms": elapsed(), "detail": str(e)}

    if not api_key:
        return {"status": "up", "response_time_ms": elapsed(), "detail": "ping ok (no api_key configured)"}

    try:
        r = requests.get(
            f"{base_url}/api/server/version",
            headers={"x-api-key": api_key},
            timeout=timeout_s,
        )
        if r.status_code == 200:
            v = r.json()
            detail = f"v{v.get('major', '?')}.{v.get('minor', '?')}.{v.get('patch', '?')}"
        elif r.status_code == 401:
            detail = "ping ok (api_key rejected — check IMMICH_CONFIG)"
        else:
            detail = f"ping ok (version HTTP {r.status_code})"
    except Exception:
        detail = "ping ok (version check failed)"

    return {"status": "up", "response_time_ms": elapsed(), "detail": detail}

"""
checkers/flask_checker.py — Flask service alive check
Layer 2: GET / — any HTTP response = alive.
Detail: "HTTP 200", "HTTP 400 — service alive", etc.
"""

from checkers import http_checker
from datetime import datetime, timezone


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check a Flask service on tailscale_name:port via GET /.
    Any HTTP response including 4xx = service alive (up).
    5xx or connection failure = down.

    Detail strings (passing):
        "HTTP 200"
        "HTTP 400 — service alive"
    Detail strings (failing):
        "Connection timeout"
        "HTTP 503"
        etc.
    """
    url = f"http://{tailscale_name}:{port}/"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    result = http_checker.get(url, timeout_ms)

    if result["status"] == "up":
        code = result["http_code"]
        if code and code >= 400:
            detail = f"HTTP {code} — service alive"
        else:
            detail = f"HTTP {code}" if code else "HTTP OK"
    else:
        detail = result["detail"] or (f"HTTP {result['http_code']}" if result["http_code"] else "Unknown error")

    return {
        "status": result["status"],
        "response_time_ms": result["response_time_ms"],
        "detail": detail,
        "timestamp_utc": timestamp,
    }

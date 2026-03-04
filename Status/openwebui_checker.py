"""
checkers/openwebui_checker.py — OpenWebUI service health check
Layer 2: GET /health — returns {"status": true}. Any 200 = passing.
"""

from checkers import http_checker
from datetime import datetime, timezone


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check OpenWebUI on tailscale_name:port.

    Detail strings (passing):  "healthy"
    Detail strings (failing):  "Connection timeout", "HTTP 502", etc.
    """
    url = f"http://{tailscale_name}:{port}/health"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    result = http_checker.get(url, timeout_ms)

    if result["status"] == "up":
        detail = "healthy"
    else:
        detail = result["detail"] or (f"HTTP {result['http_code']}" if result["http_code"] else "Unknown error")

    return {
        "status": result["status"],
        "response_time_ms": result["response_time_ms"],
        "detail": detail if result["status"] == "down" else "healthy",
        "timestamp_utc": timestamp,
    }

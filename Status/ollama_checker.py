"""
checkers/ollama_checker.py — Ollama service health check
Layer 2: GET /api/tags (model count) + GET /api/ps (active model in VRAM)
Returns standard service result with detail string per spec.
"""

import json
from checkers import http_checker
from datetime import datetime, timezone


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check Ollama on tailscale_name:port.

    Detail strings (passing):
        "12 models available · llama3:8b active in VRAM"
        "12 models available · none active"
        "port open — stats unavailable"   (if JSON parse fails)

    Detail strings (failing):
        "Connection timeout"
        "HTTP 502"
        etc.
    """
    base_url = f"http://{tailscale_name}:{port}"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    # --- /api/tags — model inventory ---
    tags_result = http_checker.get(f"{base_url}/api/tags", timeout_ms)

    if tags_result["status"] == "down":
        return _result(
            status="down",
            response_time_ms=tags_result["response_time_ms"],
            detail=tags_result["detail"] or f"HTTP {tags_result['http_code']}",
            timestamp=timestamp,
        )

    # Parse model count
    model_count = None
    if tags_result["raw_body"]:
        try:
            data = json.loads(tags_result["raw_body"])
            models = data.get("models", [])
            model_count = len(models)
        except (json.JSONDecodeError, AttributeError):
            pass

    # --- /api/ps — active VRAM model ---
    ps_result = http_checker.get(f"{base_url}/api/ps", timeout_ms)
    active_model = None

    if ps_result["status"] == "up" and ps_result["raw_body"]:
        try:
            data = json.loads(ps_result["raw_body"])
            running = data.get("models", [])
            if running:
                active_model = running[0].get("name") or running[0].get("model")
        except (json.JSONDecodeError, AttributeError):
            pass

    # Build detail string
    if model_count is None:
        detail = "port open — stats unavailable"
    else:
        count_str = f"{model_count} model{'s' if model_count != 1 else ''} available"
        if active_model:
            detail = f"{count_str} · {active_model} active in VRAM"
        else:
            detail = f"{count_str} · none active"

    total_ms = tags_result["response_time_ms"] + (ps_result["response_time_ms"] if ps_result else 0)

    return _result(
        status="up",
        response_time_ms=total_ms,
        detail=detail,
        timestamp=timestamp,
    )


def _result(status, response_time_ms, detail, timestamp):
    return {
        "status": status,
        "response_time_ms": response_time_ms,
        "detail": detail if detail else None,
        "timestamp_utc": timestamp,
    }

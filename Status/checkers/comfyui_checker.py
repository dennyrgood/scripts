"""
checkers/comfyui_checker.py — ComfyUI service health check
Layer 2: GET /system_stats (GPU name, VRAM used/total in bytes → GB)
         GET /queue (queue_running + queue_pending counts)
Returns standard service result with detail string per spec.
Note: No API exists to identify which model is loaded in VRAM (ComfyUI limitation).
"""

import json
from checkers import http_checker
from datetime import datetime, timezone


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check ComfyUI on tailscale_name:port.

    Detail strings (passing):
        "VRAM: 18.2GB / 32GB · GPU: RTX 5090 · Queue: 2 running, 5 pending"
        "VRAM: 4.1GB / 32GB · GPU: RTX 5090 · Queue: idle"
        "port open — stats unavailable"   (if JSON parse fails)

    Detail strings (failing):
        "Connection timeout"
        "HTTP 502"
        etc.
    """
    base_url = f"http://{tailscale_name}:{port}"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    # --- /system_stats — GPU and VRAM info ---
    stats_result = http_checker.get(f"{base_url}/system_stats", timeout_ms)

    if stats_result["status"] == "down":
        return _result(
            status="down",
            response_time_ms=stats_result["response_time_ms"],
            detail=stats_result["detail"] or f"HTTP {stats_result['http_code']}",
            timestamp=timestamp,
        )

    # Parse GPU/VRAM stats
    gpu_name = None
    vram_used_gb = None
    vram_total_gb = None

    if stats_result["raw_body"]:
        try:
            data = json.loads(stats_result["raw_body"])
            # ComfyUI system_stats structure: {"system": {...}, "devices": [...]}
            devices = data.get("devices", [])
            if not devices:
                # Some versions nest under system.devices or return flat
                system = data.get("system", {})
                devices = system.get("devices", [])

            if devices:
                gpu = devices[0]
                gpu_name = gpu.get("name")
                # VRAM values in bytes per spec
                vram_total = gpu.get("vram_total") or gpu.get("total_memory")
                vram_free = gpu.get("vram_free") or gpu.get("free_memory")
                if vram_total is not None and vram_free is not None:
                    vram_total_gb = round(vram_total / (1024 ** 3), 1)
                    vram_used_gb = round((vram_total - vram_free) / (1024 ** 3), 1)
        except (json.JSONDecodeError, AttributeError, TypeError):
            pass

    # --- /queue — job queue depth ---
    queue_result = http_checker.get(f"{base_url}/queue", timeout_ms)
    running_count = 0
    pending_count = 0

    if queue_result["status"] == "up" and queue_result["raw_body"]:
        try:
            data = json.loads(queue_result["raw_body"])
            running_count = len(data.get("queue_running", []))
            pending_count = len(data.get("queue_pending", []))
        except (json.JSONDecodeError, AttributeError, TypeError):
            pass

    # Build detail string
    if vram_used_gb is None or vram_total_gb is None:
        detail = "port open — stats unavailable"
    else:
        vram_str = f"VRAM: {vram_used_gb}GB / {vram_total_gb}GB"
        gpu_str = f"GPU: {gpu_name}" if gpu_name else ""
        if running_count > 0 or pending_count > 0:
            queue_str = f"Queue: {running_count} running, {pending_count} pending"
        else:
            queue_str = "Queue: idle"

        parts = [p for p in [vram_str, gpu_str, queue_str] if p]
        detail = " · ".join(parts)

    total_ms = stats_result["response_time_ms"] + (
        queue_result["response_time_ms"] if queue_result else 0
    )

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

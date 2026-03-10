
"""
checkers/syncthing_checker.py — Syncthing sync status check (Layer 2 API)
Returns standard service result with detail string.
"""

import time
import requests
from datetime import datetime, timezone

try:
    from requests.exceptions import ConnectionError as RequestsConnectionError
except ImportError:
    RequestsConnectionError = object


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check Syncthing sync status on tailscale_name.
    
    Detail strings (passing):
        "Synced • 3/3 files • No pending items"
    
    Detail strings (failing):
        "Sync pending: X items • Y MB behind"
    """
    start_time = time.monotonic()

    # Get Syncthing credentials/config from config
    from config import SYNC Thing_CONFIG
    
    machine_config = SYNC Thing_CONFIG.get(tailscale_name)
    
    if not machine_config:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"No Syncthing config for {tailscale_name}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    syncthing_url = machine_config.get("syncthing_url")
    api_key = machine_config.get("api_key")

    try:
        headers = {"X-API-Key": api_key} if api_key else None
        progress_url = f"{syncthing_url}/rest/system/progress"
        
        response = requests.get(progress_url, headers=headers, 
timeout=timeout_ms / 1000)
        response.raise_for_status()
        progress_data = response.json()

        elapsed = round((time.monotonic() - start_time) * 1000)
        
        # Format detail string from sync progress data
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"Synced • {progress_data['globalCount']} items",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except RequestsConnectionError:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Syncthing API connection error to {syncthing_url}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except Exception as e:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Syncthing error: {e}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )


def _result(status: str, response_time_ms: int, detail: str, timestamp: str) -> dict:
    """Create standardized service check result."""
    return {
        "status": status,
        "response_time_ms": response_time_ms,
        "detail": detail if detail else None,
        "timestamp_utc": timestamp,
    }


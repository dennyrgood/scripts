
"""
checkers/plex_checker.py — Plex server health check
"""

import time
from datetime import datetime, timezone

try:
    from plexapi.server import PlexServer
    from requests.exceptions import ConnectionError as PlexConnectionError, ConnectTimeout
except ImportError:
    PlexServerError = ImportError("plexapi library not installed")


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check Plex server status.
    """
    from config import PLEX_CONFIG
    
    start_time = time.monotonic()

    # Get Plex credentials for this machine from config
    machine_plex = PLEX_CONFIG.get(tailscale_name)

    if not machine_plex:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"No Plex configuration for {tailscale_name}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    plex_url = machine_plex.get("plex_url")
    plex_token = machine_plex.get("plex_token")

    if not plex_url or not plex_token:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"Plex disabled for {tailscale_name}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    try:
        plex = PlexServer(plex_url, plex_token)

    except (PlexConnectionError, ConnectTimeout):
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Connection timeout to {plex_url}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except Exception as e:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Error connecting to Plex: {e}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    # Gather metrics (only on success)
    try:
        friendly_name = plex.friendlyName
        version = plex.version
        remote_status = "ACTIVE" if plex.myPlexMappingState == "mapped" else "DISABLED"
        sections = len(plex.library.sections())

        detail = f"{friendly_name} v{version} • Remote: {remote_status} • {sections} libraries"
        elapsed = round((time.monotonic() - start_time) * 1000)

        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=detail,
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except Exception as e:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Failed to parse Plex data: {e}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )


def _result(status: str, response_time_ms: int, detail: str, timestamp: str) -> dict:
    return {
        "status": status,
        "response_time_ms": response_time_ms,
        "detail": detail if detail else None,
        "timestamp_utc": timestamp,
    }


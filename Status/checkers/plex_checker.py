
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

        # Get active streams info
        sessions = plex.sessions()
        stream_count = len(sessions)
        stream_details = []

        for session in sessions:
            user = list(session.usernames)[0] if session.usernames else "Unknown"
            title_type = session.type.capitalize() if session.type else "Unknown"
            grandparent = f"{session.grandparentTitle} - " if getattr(session, 'grandparentTitle', None) else ""
            full_title = grandparent
            if session.type == 'episode':
                full_title += f"{session.parentTitle} — {session.title}"
            elif session.type == 'movie':
                full_title += f"{session.title} ({session.year})"
            else:
                full_title += session.title

            # Get player state if available
            try:
                state = list(session.players)[0].state if session.players else "playing"
            except (IndexError, AttributeError):
                state = "unknown"

            stream_details.append(f"{user}: {full_title} [{state}]")

        # Build detail with streams info
        parts = [f"{friendly_name} v{version}", f"Remote: {remote_status}"]
        parts.append(f"{sections} libraries")

        if stream_count > 0:
            parts.append(f"{stream_count} active streams")
            detail_base = " • ".join(parts)
            details_str = detail_base + "\n"
            for sd in stream_details[:3]:  # Show max 3 streams
                details_str += f"    - {sd}\n"
            detail = details_str.strip()
        else:
            parts.append("No active streams")
            detail = " • ".join(parts)
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


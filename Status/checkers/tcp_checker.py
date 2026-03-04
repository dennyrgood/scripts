"""
checkers/tcp_checker.py - Layer 1 host reachability check
TCP connect to Tailscale MagicDNS short hostname on a specified probe_port.
Returns a standard result. If this fails, the engine skips all Layer 2/3 checks.
"""

import socket
import time
from datetime import datetime, timezone


def check(tailscale_name: str, timeout_ms: int, port: int = 80) -> dict:
    """
    Attempt a TCP connect to tailscale_name on the given port.
    Any successful connect OR connection refused = host reachable (port refused
    means the host responded, just not that service).
    Returns a host-level result dict.
    """
    timeout_s = timeout_ms / 1000
    start = time.monotonic()
    status = "down"
    detail = None

    try:
        with socket.create_connection((tailscale_name, port), timeout=timeout_s):
            pass
        status = "up"
    except ConnectionRefusedError:
        # Port refused but host is alive and responding
        status = "up"
        detail = f"port {port} refused (host reachable)"
    except socket.timeout:
        detail = "Connection timeout"
    except socket.gaierror as e:
        detail = f"DNS resolution failed: {e}"
    except OSError as e:
        detail = f"Connection error: {e}"

    elapsed_ms = round((time.monotonic() - start) * 1000)

    return {
        "status": status,
        "response_time_ms": elapsed_ms,
        "detail": detail,
        "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }

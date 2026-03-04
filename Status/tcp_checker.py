"""
checkers/tcp_checker.py — Layer 1 host reachability check
TCP connect to Tailscale MagicDNS short hostname on port 22 (or any open port).
Returns a standard result. If this fails, the engine skips all Layer 2/3 checks.
"""

import socket
import time
from datetime import datetime, timezone


def check(tailscale_name: str, timeout_ms: int) -> dict:
    """
    Attempt a TCP connect to tailscale_name on port 22.
    Any successful connect = host reachable.
    Returns a host-level result dict (not a full service result).
    """
    timeout_s = timeout_ms / 1000
    start = time.monotonic()
    status = "down"
    detail = None

    try:
        with socket.create_connection((tailscale_name, 22), timeout=timeout_s):
            pass
        status = "up"
    except socket.timeout:
        detail = "Connection timeout"
    except ConnectionRefusedError:
        # Port 22 refused but host is alive — still reachable
        status = "up"
        detail = "port 22 refused (host reachable)"
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

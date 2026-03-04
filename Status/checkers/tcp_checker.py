"""
checkers/tcp_checker.py - Layer 1 host reachability check
TCP connect to Tailscale MagicDNS short hostname on a specified probe_port.
Returns a standard result. If this fails, the engine skips all Layer 2/3 checks.
"""

import socket
import time
from datetime import datetime, timezone


def check(host: str, timeout_ms: int, port: int = 80) -> dict:
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
        # Force IPv4 to avoid IPv6 fallback delay on Windows
        addr_info = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        family, socktype, proto, canonname, sockaddr = addr_info[0]
        sock = socket.socket(family, socktype, proto)
        sock.settimeout(timeout_s)
        with sock:
            sock.connect(sockaddr)
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

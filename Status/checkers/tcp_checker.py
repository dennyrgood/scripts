"""
checkers/tcp_checker.py - Layer 1 host reachability check
ICMP ping to verify the node is alive on the wireguard network.
This checks Tailscale connectivity regardless of specific ports or services.
"""

import subprocess
import re
import time
from datetime import datetime, timezone


def check(host: str, timeout_ms: int, port: int = 0) -> dict:
    """
    Check if a machine is alive using ICMP ping to its Tailscale hostname/IP.
    
    Note: 'port' parameter is ignored - we use raw ICMP for reachability check.
    The host can be a Tailscale MagicDNS name (e.g., 'surface3-gc') or IP.
    
    Returns a host-level result dict:
      status: "up" | "down"
      response_time_ms: time in milliseconds  
      detail: "avg response time: Xms" or error message
    """
    start = time.monotonic()
    
    # Give the ping command all the user's timeout, with 3s buffer for subprocess
    ping_timeout_s = (timeout_ms / 1000.0) + 3.0
    if ping_timeout_s < 5.0:
        ping_timeout_s = 5.0  # Minimum 5 seconds for remote checks
    
    try:
        # Send 3 pings and wait for full result
        # -c 3 means 3 packets, -W is individual packet timeout in seconds
        result = subprocess.run(
            ["ping", "-c", "3", str(host)],
            capture_output=True,
            text=True,
            timeout=10,  # Absolute upper bound on wait time
        )
        
        output = result.stdout.strip() + " " + result.stderr.strip()
        
        # Check for ping success (any response received)
        # Linux/macOS: "64 bytes from" or "rtt", Windows: "Reply from"
        has_ping_success = (
            ("64 bytes from" in output.lower() and "icmp_seq" in output.lower())
            or "round-trip" in output.lower()
            or "reply from" in output.lower()
        )
        
        if has_ping_success:
            elapsed_ms = round((time.monotonic() - start) * 1000)
            
            # Extract avg RTT from ping output (Linux/macOS or Windows format)
            detail = "responded"
            try:
                import re
                # Linux/macOS: "round-trip min/avg/max/stddev = 5.123/45.678/67.890/15.321 ms"
                linux_match = re.search(r'round-trip\s+[^=]+=\s+(?:min\/)?([\d.]+)', output)
                # Windows: "Reply from X.X.X.X: ... time=95ms ..."
                windows_match = re.search(r'time=([\d.]+)ms', output, re.IGNORECASE)
                
                if linux_match:
                    avg_ms = float(linux_match.group(1))
                    detail = f"avg response time: {int(avg_ms)}ms"  # Round to nearest ms for display
                elif windows_match:
                    # For Windows, just use first ping time or calculate average
                    times = re.findall(r'time=([\d.]+)ms', output, re.IGNORECASE)
                    if times:
                        avg_time = sum(float(t) for t in times) / len(times)
                        detail = f"avg response time: {int(avg_time)}ms"
                elif result.returncode == 0:
                    detail = "responded"
            except Exception:
                pass
            
            return {
                "status": "up",
                "response_time_ms": elapsed_ms,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        else:
            # No ping responses at all (0% packet loss, or DNS failure)
            status = "down"
            error_text = result.stderr.strip() if result.stderr else output[:100]
            detail = f"Ping failed: {error_text}" if error_text else "Host unreachable on network"
            
            elapsed_ms = round((time.monotonic() - start) * 1000)
            return {
                "status": status,
                "response_time_ms": elapsed_ms,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
            
    except Exception as e:
        # Tailscale CLI not found or other error
        status = "down"
        detail = f"Ping error: {e}"
        elapsed_ms = round((time.monotonic() - start) * 1000)
        return {
            "status": status,
            "response_time_ms": elapsed_ms,
            "detail": detail,
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }

"""
checkers/tcp_checker.py - Layer 1 host reachability check
ICMP ping to verify the node is alive on the wireguard network.
This checks Tailscale connectivity regardless of specific ports or services.
"""

import subprocess
import re
import sys
import time
from datetime import datetime, timezone


def check(host: str, timeout_ms: int, port: int = 0) -> dict:
    """
    Check if a machine is alive using ICMP ping to its Tailscale hostname/IP.
    
    Note: 'port' parameter is ignored - we use raw ICMP for reachability check.
    The host can be a Tailscale MagicDNS name (e.g., 'surface3-gc') or IP.
    
    Returns a host-level result dict:
      status: "up" | "down"
      response_time_ms: actual ping RTT in milliseconds  
      detail: "avg response time: Xms" or error message
    """
    start = time.monotonic()
    
    # Build cross-platform ping command
    if sys.platform.startswith('win'):
        # Windows ping defaults to 4 pings, force 3 for consistency
        ping_cmd = ["ping", "-n", "3", str(host)]
    else:
        # Linux/macOS ping uses -c for count
        ping_cmd = ["ping", "-c", "3", str(host)]
    
    try:
        # Run ping directly without artificial timeout
        result = subprocess.run(
            ping_cmd,
            capture_output=True,
            text=True,
        )
        
        output = result.stdout.strip() + " " + result.stderr.strip()
        
        # Check for ping success based on OS-specific output format
        has_ping_success = (
            ("64 bytes from" in output.lower() and "icmp_seq" in output.lower())  # Linux/macOS
            or "round-trip" in output.lower()  # Also Linux/macOS
            or "reply from" in output.lower()  # Windows
        )
        
        if has_ping_success:
            # Extract RTT time from ping output for reporting
            response_time_ms = 0
            detail = "responded"
            
            try:
                # Linux/macOS format: round-trip min/avg/max/stddev = 5.123/45.678/67.890/15.321 ms
                linux_match = re.search(r'round-trip\s+[^=]+=\s+(?:min\/)?([\d.]+)', output)
                if linux_match:
                    avg_ms = float(linux_match.group(1))
                    response_time_ms = round(avg_ms)
                    detail = f"avg response time: {response_time_ms}ms"
                else:
                    # Windows format: "Reply from X.X.X.X: ... time=95ms ..."
                    times = re.findall(r'time=([\d.]+)ms', output, re.IGNORECASE)
                    if times:
                        avg_time = sum(float(t) for t in times) / len(times)
                        response_time_ms = round(avg_time)
                        detail = f"avg response time: {response_time_ms}ms"
                    elif "64 bytes from" in output.lower():
                        # Fallback for localhost ping or individual replies without stats line
                        time_match = re.search(r'time=([\d.]+)ms', output, re.IGNORECASE)
                        if time_match:
                            response_time_ms = round(float(time_match.group(1)))
                            detail = f"avg response time: {response_time_ms}ms"
            except Exception:
                pass
            
            return {
                "status": "up",
                "response_time_ms": response_time_ms,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        else:
            # No successful ping responses
            status = "down"
            error_text = result.stderr.strip() if result.stderr else output[:100]
            detail = f"Ping failed: {error_text}" if error_text else "Host unreachable on network"
            
            return {
                "status": status,
                "response_time_ms": 0,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
            
    except Exception as e:
        # Process execution error (ping command not found, permissions, etc.)
        status = "down"
        detail = f"Ping error: {e}"
        
        return {
            "status": status,
            "response_time_ms": 0,
            "detail": detail,
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }

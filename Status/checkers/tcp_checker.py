"""
checkers/tcp_checker.py - Layer 1 host reachability check
Uses Tailscale ping (WireGuard protocol) instead of TCP port checks.
This is more reliable because it checks if the node is alive on the network,
regardless of which ports are listening or firewall rules.
"""

import subprocess
import time
from datetime import datetime, timezone
from typing import Optional


def check(host: str, timeout_ms: int, port: int = 0) -> dict:
    """
    Check if a machine is alive using Tailscale ping.
    
    Note: 'port' parameter is ignored - we use Tailscale wire protocol instead.
    The host can be a Tailscale magic DNS name (e.g., 'surface3-gc') or IP.
    
    Returns a host-level result dict:
      status: "up" | "down"
      response_time_ms: time in milliseconds
      detail: "responded in Xms" or error message
    """
    # Tailscale ping typically takes 50-200ms on LAN, up to 3s on slow networks
    # We use a shorter timeout for subprocess but account for its overhead
    tailscale_timeout_s = min(timeout_ms / 1000 - 1.0, 60)  # Reserve 1s for subprocess overhead
    if tailscale_timeout_s < 0.5:
        tailscale_timeout_s = 0.5  # Minimum timeout of 0.5s
        
    start = time.monotonic()
    
    try:
        # Use tailscale ping command - checks WireGuard connectivity, not ports
        result = subprocess.run(
            ["tailscale", "ping", host],
            capture_output=True,
            text=True,
            timeout=tailscale_timeout_s,
        )
        
        output = result.stdout.strip() + " " + result.stderr.strip()
        
        if result.returncode == 0:
            elapsed_ms = round((time.monotonic() - start) * 1000)
            
            # Parse response time from tailscale ping output
            # Various formats:
            #   "pong from imagebeast (100.107.247.38) via ... in 81ms" (remote host)
            #   "pong from denniss-macbook-air (100.72.187.19) via DERP(mad) in 86ms" (local/DERP relay)
            #   "100.72.187.19 is local Tailscale IP" or other variations
            detail = None
            try:
                # Try to extract the ms value from output
                if "ms" in output:
                    import re
                    # Look for pattern like "in 86ms" (handles both direct and DERP relay)
                    ms_match = re.search(r'in\s+([\d.]+)ms', output)
                    if not ms_match:
                        # Fallback: any number followed by ms
                        ms_match = re.search(r'(\d+(?:\.\d+)?)ms', output)
                    if ms_match:
                        ms_value = ms_match.group(1)
                        detail = f"responded in {ms_value}ms"
                    else:
                        detail = "responded"
                else:
                    detail = "responded"
            except:
                detail = "responded"
            
            return {
                "status": "up",
                "response_time_ms": elapsed_ms,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        else:
            # tailscale ping failed - host unreachable or not on network
            status = "down"
            error_detail = result.stderr.strip() if result.stderr else output
            detail = f"Tailscale ping failed: {error_detail}" if error_detail else "Host unreachable"
            
            elapsed_ms = round((time.monotonic() - start) * 1000)
            return {
                "status": status,
                "response_time_ms": elapsed_ms,
                "detail": detail,
                "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
            
    except FileNotFoundError as e:
        # Tailscale CLI not found
        status = "down"
        detail = f"Tailscale CLI error: {e}"
        elapsed_ms = round((time.monotonic() - start) * 1000)
        return {
            "status": status,
            "response_time_ms": elapsed_ms,
            "detail": detail,
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
    except subprocess.TimeoutExpired as e:
        # Show what Tailscale actually said before timing out
        status = "down"
        detail = None
        if hasattr(e, 'stdout') and e.stdout:
            part_output = e.stdout.decode() if isinstance(e.stdout, bytes) else str(e.stdout)
            detail = f"Tailscale ping timed out ({part_output.strip()[:200]})"
        else:
            detail = "Tailscale ping timed out"
        
        elapsed_ms = round((time.monotonic() - start) * 1000)
        return {
            "status": status,
            "response_time_ms": elapsed_ms,
            "detail": detail,
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
    except Exception as e:
        # Generic error - include the actual exception
        status = "down"
        detail = f"Tailscale ping error: {e}"
        elapsed_ms = round((time.monotonic() - start) * 1000)
        return {
            "status": status,
            "response_time_ms": elapsed_ms,
            "detail": detail,
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }

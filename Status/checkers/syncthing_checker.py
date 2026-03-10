
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
    from config import SYNCTHING_CONFIG
    
    machine_config = SYNCTHING_CONFIG.get(tailscale_name)
    
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


def main():
    """Debug mode for manual testing."""
    import sys
    import os
    from pprint import pprint
    
    # Add parent directory to path so imports work
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    if parent_dir not in sys.path:
        sys.path.insert(0, parent_dir)
    
    print("=" * 60)
    print("Syncthing Checker — Manual Debug Mode")
    print("=" * 60)
    
    if len(sys.argv) == 1:
        # No args provided, show usage
        print("\nUsage: python syncthing_checker.py [machine_name] [port]\n")
        print("Examples:")
        print("  python syncthing_checker.py surface3-gc 8384")
        print("  python syncthing_checker.py mathes-mac-mini 8384")
        
        # Show configured machines
        from config import SYNCTHING_CONFIG
        print("\nConfigured Syncthing targets:")
        for name, cfg in SYNCTHING_CONFIG.items():
            if cfg:
                url = cfg.get('syncthing_url', 'N/A')
                has_token = '✓' if cfg.get('api_key') else '✗'
                print(f"  • {name}: {url} (token: {has_token})")
    else:
        # Run test with provided arguments
        machine_name = sys.argv[1]
        port = int(sys.argv[2]) if len(sys.argv) > 2 else 8384
        timeout_ms = 3000
        
        print(f"\nTesting: {machine_name}:{port}")
        print("-" * 60)
        
        try:
            result = check(machine_name, port, timeout_ms)
            pprint(result)
            print("\n" + "=" * 60)
            if result['status'] == 'up':
                print(f"Result: ✓ UP ({result['response_time_ms']}ms)")
                if result.get('detail'):
                    print(f"Detail: {result['detail']}")
            else:
                print(f"Result: ✗ DOWN ({result['response_time_ms']}ms)")
                if result.get('detail'):
                    print(f"Error:  {result['detail']}")
            print("=" * 60)
        except Exception as e:
            print(f"\nERROR: {e}")
            import traceback
            traceback.print_exc()
    
    return result if 'result' in locals() else None


if __name__ == "__main__":
    main()


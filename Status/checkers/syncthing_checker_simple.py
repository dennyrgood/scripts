"""
checkers/syncthing_checker.py — Syncthing sync status check (Layer 2 API)
Returns standard service result with detail string.
"""

import time
import requests
from datetime import datetime, timezone

try:
    from requests.exceptions import ConnectionError as RequestsConnectionError
    from requests.exceptions import ConnectTimeout
except ImportError:
    RequestsConnectionError = object
    ConnectTimeout = object


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check Syncthing sync status on tailscale_name:port.

    Detail strings (passing):
        "Synced • 3 folders • 0 items pending"

    Detail strings (failing):
        "Connection error to http://surface3-gc:8384"
        "Connection timeout"
        "HTTP 403 — check api_key in SYNCTHING_CONFIG"
        "Folder 'docs' error state"
        "Sync pending: 5 items • 12.3 MB behind"
    """
    start_time = time.monotonic()

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

    syncthing_url = machine_config.get("syncthing_url", "").rstrip("/")
    api_key       = machine_config.get("api_key", "").strip()
    headers       = {"X-API-Key": api_key}
    timeout       = timeout_ms / 1000

    try:
        # 1. Liveness ping
        ping = requests.get(
            f"{syncthing_url}/rest/system/ping",
            headers=headers, timeout=timeout, verify=False,
        )
        ping.raise_for_status()
        if ping.json().get("ping") != "pong":
            raise RuntimeError("unexpected ping response")

        # 2. Folder list from config
        cfg_resp = requests.get(
            f"{syncthing_url}/rest/config",
            headers=headers, timeout=timeout, verify=False,
        )
        cfg_resp.raise_for_status()
        folder_ids = [f["id"] for f in cfg_resp.json().get("folders", [])]

        # 3. Per-folder sync status
        total_need_files = 0
        total_need_bytes = 0
        folder_issues    = []

        for fid in folder_ids:
            db_resp = requests.get(
                f"{syncthing_url}/rest/db/status",
                headers=headers, params={"folder": fid},
                timeout=timeout, verify=False,
            )
            db_resp.raise_for_status()
            db    = db_resp.json()
            state = db.get("state", "unknown")
            nf    = db.get("needFiles",  0) or 0
            nb    = db.get("needBytes",  0) or 0
            pe    = db.get("pullErrors", 0) or 0
            total_need_files += nf
            total_need_bytes += nb
            if state == "error":
                folder_issues.append(f"Folder '{fid}' error state")
            if pe:
                folder_issues.append(f"Folder '{fid}' has {pe} pull error(s)")

        elapsed = round((time.monotonic() - start_time) * 1000)

        if folder_issues:
            return _result("down", elapsed, " • ".join(folder_issues),
                           datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

        if total_need_files > 0:
            mb = total_need_bytes / 1_048_576
            return _result("down", elapsed,
                           f"Sync pending: {total_need_files} items • {mb:.1f} MB behind",
                           datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

        n = len(folder_ids)
        return _result("up", elapsed,
                       f"Synced • {n} folder{'s' if n != 1 else ''} • 0 items pending",
                       datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

    except ConnectTimeout:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result("down", elapsed, "Connection timeout",
                       datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

    except RequestsConnectionError:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result("down", elapsed, f"Connection error to {syncthing_url}",
                       datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

    except requests.exceptions.HTTPError as exc:
        elapsed = round((time.monotonic() - start_time) * 1000)
        code  = exc.response.status_code if exc.response is not None else "?"
        hint  = " — check api_key in SYNCTHING_CONFIG" if code == 403 else ""
        return _result("down", elapsed, f"HTTP {code}{hint}",
                       datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))

    except Exception as exc:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result("down", elapsed, f"Syncthing error: {exc}",
                       datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))


def _result(status: str, response_time_ms: int, detail: str, timestamp: str) -> dict:
    """Create standardized service check result."""
    return {
        "status":           status,
        "response_time_ms": response_time_ms,
        "detail":           detail if detail else None,
        "timestamp_utc":    timestamp,
    }


# ---------------------------------------------------------------------------
# main() — manual debug / standalone test
# ---------------------------------------------------------------------------

def main():
    import sys, os
    from pprint import pprint
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    for p in (script_dir, parent_dir):
        if p not in sys.path:
            sys.path.insert(0, p)

    print("=" * 60)
    print("Syncthing Checker — Manual Debug Mode")
    print("=" * 60)

    if len(sys.argv) == 1:
        print("\nUsage: python syncthing_checker.py [machine_name] [port]\n")
        print("Examples:")
        print("  python syncthing_checker.py surface3-gc 8384")
        print("  python syncthing_checker.py mathes-mac-mini 8384")
        from config import SYNCTHING_CONFIG
        print("\nConfigured Syncthing targets:")
        for name, cfg in SYNCTHING_CONFIG.items():
            if cfg:
                url     = cfg.get("syncthing_url", "N/A")
                key     = cfg.get("api_key", "")
                has_key = "✓" if key and key.strip() else "✗ MISSING"
                preview = f"{key[:4]}…{key[-4:]}" if len(key) >= 8 else "(short?)"
                print(f"  • {name:25s}  {url}  key: {has_key} {preview}")
            else:
                print(f"  • {name:25s}  (no config — returns up/no-config)")
        return None

    machine_name = sys.argv[1]
    port         = int(sys.argv[2]) if len(sys.argv) > 2 else 8384
    timeout_ms   = 3000

    print(f"\nTesting: {machine_name}:{port}")
    print("-" * 60)

    result = None
    try:
        result = check(machine_name, port, timeout_ms)
        pprint(result)
        print("\n" + "=" * 60)
        if result["status"] == "up":
            print(f"Result: ✓ UP ({result['response_time_ms']}ms)")
            if result.get("detail"):
                print(f"Detail: {result['detail']}")
        else:
            print(f"Result: ✗ DOWN ({result['response_time_ms']}ms)")
            if result.get("detail"):
                print(f"Error : {result['detail']}")
        print("=" * 60)
    except Exception as exc:
        print(f"\nERROR: {exc}")
        import traceback
        traceback.print_exc()

    return result


if __name__ == "__main__":
    main()
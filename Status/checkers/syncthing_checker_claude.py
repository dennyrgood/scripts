"""
checkers/syncthing_checker.py — Syncthing sync status check (Layer 2 API)
Returns standard service result with detail string.

Fixes vs original:
  - /rest/system/progress does not exist → replaced with correct endpoints:
      /rest/system/ping        (liveness)
      /rest/system/status      (uptime, CPU, RAM)
      /rest/config             (folder list)
      /rest/db/status?folder=X (per-folder sync state)
  - Added API key debug output so 403s are caught early
  - Handles missing/blank api_key gracefully with a clear error message
"""

import time
import requests
from datetime import datetime, timezone

try:
    from requests.exceptions import ConnectionError as RequestsConnectionError
except ImportError:
    RequestsConnectionError = object


# ---------------------------------------------------------------------------
# Public check() — called by the monitor framework
# ---------------------------------------------------------------------------

def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check Syncthing sync status on tailscale_name.

    Detail strings (passing):
        "Synced • 3 folders • 0 items pending"
    Detail strings (failing):
        "Sync pending: 5 items • 12.3 MB behind"
        "Folder 'docs' error state"
    """
    start_time = time.monotonic()
    now_utc = lambda: datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    from config import SYNCTHING_CONFIG
    machine_config = SYNCTHING_CONFIG.get(tailscale_name)

    if not machine_config:
        elapsed = _ms(start_time)
        return _result("up", elapsed,
                       f"No Syncthing config for {tailscale_name}", now_utc())

    syncthing_url = machine_config.get("syncthing_url", "").rstrip("/")
    api_key       = machine_config.get("api_key", "").strip()

    if not syncthing_url:
        return _result("down", _ms(start_time),
                       f"syncthing_url missing in config for {tailscale_name}", now_utc())

    if not api_key:
        return _result("down", _ms(start_time),
                       "api_key missing or blank in config — cannot authenticate", now_utc())

    headers = {"X-API-Key": api_key}
    timeout = timeout_ms / 1000

    try:
        # 1. Liveness ping ---------------------------------------------------
        ping = _get(syncthing_url, "/rest/system/ping", headers, timeout)
        if ping is None:
            return _result("down", _ms(start_time),
                           f"No response from {syncthing_url}", now_utc())
        if ping.get("ping") != "pong":
            return _result("down", _ms(start_time),
                           f"Unexpected ping response: {ping}", now_utc())

        # 2. Folder list from config -----------------------------------------
        config_data = _get(syncthing_url, "/rest/config", headers, timeout) or {}
        folders = [f["id"] for f in config_data.get("folders", [])]

        # 3. Per-folder sync status ------------------------------------------
        total_need_files = 0
        total_need_bytes = 0
        folder_issues    = []

        for fid in folders:
            db = _get(syncthing_url, f"/rest/db/status?folder={fid}", headers, timeout)
            if db is None:
                folder_issues.append(f"'{fid}' unreachable")
                continue
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

        elapsed = _ms(start_time)

        # 4. Build detail string ---------------------------------------------
        if folder_issues:
            detail = " • ".join(folder_issues)
            return _result("down", elapsed, detail, now_utc())

        if total_need_files > 0:
            mb = total_need_bytes / 1_048_576
            detail = f"Sync pending: {total_need_files} items • {mb:.1f} MB behind"
            return _result("down", elapsed, detail, now_utc())

        n = len(folders)
        detail = f"Synced • {n} folder{'s' if n != 1 else ''} • 0 items pending"
        return _result("up", elapsed, detail, now_utc())

    except RequestsConnectionError:
        return _result("down", _ms(start_time),
                       f"Connection refused / network error to {syncthing_url}", now_utc())
    except Exception as exc:
        return _result("down", _ms(start_time),
                       f"Syncthing error: {exc}", now_utc())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get(base: str, path: str, headers: dict, timeout: float) -> dict | None:
    """GET a Syncthing REST path; return parsed JSON or None on any error."""
    url = f"{base}{path}"
    try:
        r = requests.get(url, headers=headers, timeout=timeout, verify=False)
        r.raise_for_status()
        return r.json()
    except requests.exceptions.HTTPError as exc:
        # Surface HTTP errors (especially 403) so callers can act on them
        raise RuntimeError(
            f"HTTP {exc.response.status_code} from {url} — "
            + ("check your api_key in config" if exc.response.status_code == 403
               else str(exc))
        ) from exc
    except Exception:
        return None


def _ms(start: float) -> int:
    return round((time.monotonic() - start) * 1000)


def _result(status: str, response_time_ms: int, detail: str, timestamp: str) -> dict:
    return {
        "status":          status,
        "response_time_ms": response_time_ms,
        "detail":          detail or None,
        "timestamp_utc":   timestamp,
    }


# ---------------------------------------------------------------------------
# main() — debug / manual test mode
# ---------------------------------------------------------------------------

def main():
    import sys, os
    from pprint import pprint

    # Ensure parent directory is on the path so config import works
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
                # Show first/last 4 chars so you can verify without exposing key
                preview = f"{key[:4]}…{key[-4:]}" if len(key) >= 8 else "(short?)"
                print(f"  • {name:25s}  {url}  key: {has_key} {preview}")
        return None

    machine_name = sys.argv[1]
    port         = int(sys.argv[2]) if len(sys.argv) > 2 else 8384
    timeout_ms   = 5000

    # --- Quick API key sanity check before full check() ---
    try:
        from config import SYNCTHING_CONFIG
        cfg = SYNCTHING_CONFIG.get(machine_name, {})
        key = (cfg or {}).get("api_key", "")
        url = (cfg or {}).get("syncthing_url", f"http://{machine_name}:{port}")
        print(f"\nConfig loaded:")
        print(f"  URL     : {url}")
        if key:
            preview = f"{key[:4]}…{key[-4:]}" if len(key) >= 8 else key
            print(f"  API key : {preview}  (len={len(key)})")
        else:
            print("  API key : *** MISSING — this will cause a 403 ***")
    except Exception as exc:
        print(f"\n  (could not load config for preview: {exc})")

    print(f"\nTesting: {machine_name}:{port}")
    print("-" * 60)

    result = None
    try:
        result = check(machine_name, port, timeout_ms)
        pprint(result)
        print("\n" + "=" * 60)
        sym = "✓ UP" if result["status"] == "up" else "✗ DOWN"
        print(f"Result: {sym} ({result['response_time_ms']}ms)")
        if result.get("detail"):
            label = "Detail" if result["status"] == "up" else "Error "
            print(f"{label}: {result['detail']}")
        print("=" * 60)
    except Exception as exc:
        print(f"\nUNHANDLED ERROR: {exc}")
        import traceback
        traceback.print_exc()

    return result


if __name__ == "__main__":
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    main()
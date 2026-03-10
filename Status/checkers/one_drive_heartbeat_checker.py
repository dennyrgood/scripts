"""
checkers/onedrive_heartbeat_checker.py — OneDrive sync health check via 
heartbeat file
Layer 2: Read timestamp from ONE Drive _sync_monitor folder, compute age.
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime, timezone, timedelta
import json


# ── ADD ROOT TO PATH FOR IMPORTS ───

sys.path.insert(0, str(Path(__file__).parent.parent))


def _get_onedrive_path():
    """Resolve OneDrive path the same way as Status/config.py."""
    return Path(
        os.environ.get("OneDriveConsumer")
        or os.environ.get("OneDrive")
        or (Path.home() / "OneDrive")
    )


def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check heartbeat file for specific writer machine on OneDrive.

    Returns standard service result with age in seconds.
    """
    start_time = datetime.now(timezone.utc)

    # Configuration
    ONE_DRIVE_PATH = _get_onedrive_path()
    HEARTBEAT_DIR = ONE_DRIVE_PATH / "_sync_monitor"
    HEARTBEAT_FILE = HEARTBEAT_DIR / f"heartbeat_{tailscale_name}.txt"
    STALE_THRESHOLD_MINUTES = 5

    filepath_str = str(HEARTBEAT_FILE)
    
    # Check if file exists
    if not HEARTBEAT_FILE.exists():
        elapsed_ms = round((datetime.now(timezone.utc).timestamp() - start_time.timestamp()) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed_ms,
            detail=f"File not found at {filepath_str}",
        )

    # Read file content
    try:
        raw = HEARTBEAT_FILE.read_text().strip()
    except Exception as e:
        elapsed_ms = round((datetime.now(timezone.utc).timestamp() - start_time.timestamp()) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed_ms,
            detail=f"File read error: {e}",
        )

    # Check if file is empty
    if not raw:
        elapsed_ms = round((datetime.now(timezone.utc).timestamp() - start_time.timestamp()) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed_ms,
            detail="File is empty — writer may have crashed"
        )

    # Parse timestamp
    try:
        server_time = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if server_time.tzinfo is None:
            server_time = server_time.replace(tzinfo=timezone.utc)
    except Exception as e:
        elapsed_ms = round((datetime.now(timezone.utc).timestamp() - start_time.timestamp()) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed_ms,
            detail=f"Parse error: Invalid timestamp '{raw[:20]}...' — {e}"
        )

    # Compute age
    now = datetime.now(timezone.utc)
    age = now - server_time
    age_seconds = int(age.total_seconds())
    age_minutes = age_seconds / 60

    elapsed_ms = round((datetime.now(timezone.utc).timestamp() - start_time.timestamp()) * 1000)

    # Determine if stale
    if age > timedelta(minutes=STALE_THRESHOLD_MINUTES):
        return _result(
            status="down",
            response_time_ms=elapsed_ms,
            detail=f"Stale: {age_minutes:.1f} min old on {tailscale_name}, threshold: {STALE_THRESHOLD_MINUTES} min",
        )

    # Heartbeat is OK
    return _result(
        status="up",
        response_time_ms=elapsed_ms,
        detail=f"{age_seconds} sec old on {tailscale_name}",
    )


def _result(status, response_time_ms, detail):
    """Create standardized service check result."""
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "status": status,
        "response_time_ms": response_time_ms,
        "detail": detail if detail else None,
        "timestamp_utc": timestamp,
    }


# ── STANDALONE DEBUG MODE ───────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="OneDrive heartbeat checker (standalone test mode)"
    )
    parser.add_argument(
        "--target", 
        required=True, 
        help="Target host to check: amsterdamdesktop or chatworkhorse"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Show verbose debug output including resolved paths and all heartbeat files in OneDrive"
    )
    
    args = parser.parse_args()
    
    if args.debug:
        print("=== OneDrive Heartbeat Checker (Debug Mode) ===\n")
        
        ONE_DRIVE_PATH = _get_onedrive_path()
        HEARTBEAT_DIR = ONE_DRIVE_PATH / "_sync_monitor"
        target_host = args.target.lower()
        
        print(f"Target host: {target_host}")
        print(f"Resolved OneDrive path: {ONE_DRIVE_PATH}")
        print(f"Heartbeat directory: {HEARTBEAT_DIR}")
        print(f"Expected file path: {HEARTBEAT_DIR / f'heartbeat_{target_host}.txt'}\n")
        
        # List ALL heartbeat files for visual verification
        if HEARTBEAT_DIR.exists():
            print("All heartbeat files found in OneDrive _sync_monitor:")
            for f in HEARTBEAT_DIR.iterdir():
                if f.name.startswith("heartbeat_"):
                    try:
                        content = f.read_text().strip()
                        age_raw = datetime.fromisoformat(content.replace("Z", "+00:00")) 
                        age_total_secs = int((datetime.now(timezone.utc) - age_raw).total_seconds())
                        status_str = "OK" if age_total_secs < (5 * 60) else "STALE"
                        print(f"  ✦ {f.name}: {content[:30]}... ({status_str}, {age_total_secs} sec)")
                    except Exception as e:
                        print(f"  ✦ {f.name}: Could not parse — {e}")
        else:
            print("Heaartbeat directory NOT FOUND - OneDrive may not be synced.")
        
        print("\n--- Running check for", target_host, "---")

    result = check(args.target, 0, 10000)
    
    # Output as JSON (matching Status engine output format)
    if args.debug:
        print(f"\nResult:")
        print(json.dumps(result, indent=2))
    else:
        print(json.dumps(result, indent=2))



import os
import time
import sys
from pathlib import Path
from datetime import datetime, timezone

# Which machine is running this checker instance
CHECKER_HOST = os.environ.get("FLEET_CHECKER_HOST") or os.environ.get("COMPUTERNAME", "unknown").lower()


#print(f"DEBUG: CHECKER_HOST detected: {CHECKER_HOST}", file=sys.stderr)

ONEDRIVE_PATH = Path(
    os.environ.get("OneDriveConsumer")
    or os.environ.get("OneDrive")
    or Path.home() / "OneDrive"
)

#print(f"DEBUG: ONEDRIVE_PATH resolved to: {ONEDRIVE_PATH}", file=sys.stderr)
#print(f"DEBUG: OneDriveConsumer env: {os.environ.get('OneDriveConsumer', 'NOT SET')}", file=sys.stderr)
#print(f"DEBUG: OneDrive env: {os.environ.get('OneDrive', 'NOT SET')}", 
#file=sys.stderr)

HEARTBEAT_DIR = ONEDRIVE_PATH / "_sync_monitor"
HEARTBEAT_FILE = HEARTBEAT_DIR / f"heartbeat_{CHECKER_HOST}.txt"

#print(f"DEBUG: Heartbeat file path: {HEARTBEAT_FILE}", file=sys.stderr)

WRITE_INTERVAL = 150  # 2.5 minutes

iteration = 0
while True:
    iteration += 1
    #print(f"DEBUG: Writing heartbeat #{iteration} to {HEARTBEAT_FILE}", file=sys.stderr, flush=True)
    try:
        HEARTBEAT_DIR.mkdir(parents=True, exist_ok=True)
        HEARTBEAT_FILE.write_text(datetime.now(timezone.utc).isoformat())
        timestamp = HEARTBEAT_FILE.read_text().strip()
        #print(f"DEBUG: Successfully wrote timestamp: {timestamp}", file=sys.stderr, flush=True)
    except Exception as e:
        #print(f"DEBUG: ERROR writing to {HEARTBEAT_FILE}: {e}", file=sys.stderr, flush=True)
        time.sleep(WRITE_INTERVAL)


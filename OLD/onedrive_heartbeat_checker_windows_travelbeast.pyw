import os
import ctypes  # Built-in Windows API for system dialogs
from pathlib import Path
from datetime import datetime, timedelta, timezone

# ── CONFIG ────────────────────────────────────────────────────────────────────

# Priority 1: Check D drive. Priority 2: Standard OneDrive paths.
BASE_PATH = Path("D:/OneDrive")
if not BASE_PATH.exists():
    BASE_PATH = Path(os.environ.get("OneDriveConsumer") or os.environ.get("OneDrive") or Path.home() / "OneDrive")

HEARTBEAT_FILE = BASE_PATH / "_sync_monitor" / "heartbeat_server.txt"
STALE_THRESHOLD_MINUTES = 5

# ── THE "IN-YOUR-FACE" ALERT ──────────────────────────────────────────────────

def alert_user(title, message):
    """
    Triggers a standard Windows System Modal Message Box.
    0x30 = Warning Icon
    0x1000 = System Modal (Stays on top of EVERYTHING)
    """
    # Using ctypes avoids needing to install tkinter or plyer
    ctypes.windll.user32.MessageBoxW(0, message, title, 0x30 | 0x1000)

# ── CHECK ─────────────────────────────────────────────────────────────────────

def run_check():
    machine = os.environ.get("COMPUTERNAME", "this machine")

    # 1. Check if file exists
    if not HEARTBEAT_FILE.exists():
        alert_user("ONEDRIVE CRITICAL", 
                  f"Sync Error: Heartbeat file missing!\n\nPath: {HEARTBEAT_FILE}")
        return

    try:
        # 2. Read and parse
        raw = HEARTBEAT_FILE.read_text().strip()
        if not raw:
            alert_user("ONEDRIVE WARNING", "Heartbeat file is empty. Server might be down.")
            return

        server_time = datetime.fromisoformat(raw)
        if server_time.tzinfo is None:
            server_time = server_time.replace(tzinfo=timezone.utc)
            
        # 3. Check age
        age = datetime.now(timezone.utc) - server_time
        age_mins = int(age.total_seconds() / 60)

        if age > timedelta(minutes=STALE_THRESHOLD_MINUTES):
            alert_user("⚠️ ONEDRIVE SYNC STUCK", 
                      f"Last sync was {age_mins} minutes ago.\n"
                      f"Expected sync every {STALE_THRESHOLD_MINUTES} mins.\n\n"
                      f"Check the server machine!")
            
    except Exception as e:
        alert_user("MONITOR SCRIPT ERROR", f"Failed to run check: {str(e)}")

if __name__ == "__main__":
    run_check()
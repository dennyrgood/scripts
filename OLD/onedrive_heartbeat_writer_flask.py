"""
heartbeat_writer.py — runs on your Win11 server
Writes a timestamp to a file in your OneDrive folder every 5 minutes.
OneDrive then syncs it to all other machines.

Setup:
  pip install flask apscheduler

Run:
  python heartbeat_writer.py

Or run as a background service — see instructions at the bottom.
"""

from flask import Flask, jsonify
from apscheduler import schedulers
from apscheduler.schedulers.background import BackgroundScheduler
from pathlib import Path
from datetime import datetime, timezone
import os

app = Flask(__name__)

# ── CONFIG ────────────────────────────────────────────────────────────────────

# Path to your OneDrive folder on this server
ONEDRIVE_PATH = Path(os.environ.get("OneDriveConsumer") or os.environ.get("OneDrive") or
                     Path.home() / "OneDrive")

# Heartbeat file location within OneDrive
HEARTBEAT_FILE = ONEDRIVE_PATH / "_sync_monitor" / "heartbeat_server.txt"

# How often to write the heartbeat (minutes)
WRITE_INTERVAL_MINUTES = 5

# ── WRITER ────────────────────────────────────────────────────────────────────

def write_heartbeat():
    try:
        HEARTBEAT_FILE.parent.mkdir(parents=True, exist_ok=True)
        now = datetime.now(timezone.utc).isoformat()
        HEARTBEAT_FILE.write_text(now)
        print(f"[{now} UTC] Heartbeat written.")
    except Exception as e:
        print(f"[ERROR] Could not write heartbeat: {e}")

# ── ROUTES ────────────────────────────────────────────────────────────────────

@app.route("/status")
def status():
    """Quick health check — visit http://server:5000/status in a browser."""
    try:
        last = HEARTBEAT_FILE.read_text().strip()
        return jsonify({
            "status": "ok",
            "last_heartbeat": last,
            "heartbeat_file": str(HEARTBEAT_FILE)
        })
    except Exception as e:
        return jsonify({"status": "error", "detail": str(e)}), 500

# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Write immediately on startup so clients don't wait 5 min for first file
    write_heartbeat()

    scheduler = BackgroundScheduler()
    scheduler.add_job(write_heartbeat, "interval", minutes=WRITE_INTERVAL_MINUTES)
    scheduler.start()

    print(f"Heartbeat writer running. Writing to: {HEARTBEAT_FILE}")
    print(f"Health check: http://localhost:5000/status")

    app.run(host="0.0.0.0", port=5000)


# ══════════════════════════════════════════════════════════════════════════════
# RUNNING AS A BACKGROUND SERVICE (so it survives reboots)
# ══════════════════════════════════════════════════════════════════════════════
#
# Option A — NSSM (recommended, free):
#   1. Download nssm from https://nssm.cc
#   2. nssm install HeartbeatWriter
#      - Path: C:\Path\To\python.exe
#      - Arguments: C:\Path\To\heartbeat_writer.py
#   3. nssm start HeartbeatWriter
#
# Option B — Task Scheduler (no install needed):
#   Trigger: At startup
#   Action:  python.exe "C:\path\to\heartbeat_writer.py"
#   Settings: Run whether user is logged on or not

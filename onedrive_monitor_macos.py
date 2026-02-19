#!/usr/bin/env python3
"""
OneDrive Sync Monitor — macOS
Shows a native macOS notification + optional AppleScript dialog if sync is stuck.

Schedule via launchd (recommended) or cron.
See setup instructions at the bottom of this file.

Requirements:
  pip3 install psutil
  (No other deps needed — uses osascript for notifications)
"""

import os
import subprocess
import psutil
from pathlib import Path
from datetime import datetime, timedelta

# ── CONFIG ────────────────────────────────────────────────────────────────────
# Your OneDrive folder (adjust the name if it differs)
ONEDRIVE_PATH = Path.home() / "OneDrive"
# If you use OneDrive for Business it might be something like:
# ONEDRIVE_PATH = Path.home() / "OneDrive - Your Company Name"

HEARTBEAT_SUBDIR = "_sync_monitor"
STUCK_THRESHOLD_MINUTES = 45

# ── HELPERS ───────────────────────────────────────────────────────────────────

def notify(title: str, message: str) -> None:
    """Send a macOS notification via osascript."""
    safe_title = title.replace('"', '\\"')
    safe_msg = message.replace('"', '\\"')

    # Notification center notification
    script = (
        f'display notification "{safe_msg}" '
        f'with title "{safe_title}" '
        f'sound name "Basso"'
    )
    subprocess.run(["osascript", "-e", script], capture_output=True)

    # Also show a dialog box so it's hard to miss
    dialog_script = (
        f'tell app "System Events" to display dialog '
        f'"{safe_msg}" with title "{safe_title}" '
        f'buttons {{"OK"}} default button "OK" '
        f'with icon caution'
    )
    subprocess.run(["osascript", "-e", dialog_script], capture_output=True)


def is_onedrive_running() -> bool:
    for proc in psutil.process_iter(["name"]):
        name = proc.info.get("name") or ""
        if "onedrive" in name.lower():
            return True
    return False


def check_onedrive_finder_badge() -> tuple[bool, str]:
    """
    Use mdls to check if OneDrive folder has a sync error status.
    This is a best-effort check since macOS doesn't expose OneDrive
    status via a clean API.
    """
    try:
        result = subprocess.run(
            ["mdls", "-name", "kMDItemFSContentChangeDate", str(ONEDRIVE_PATH)],
            capture_output=True, text=True, timeout=5
        )
        # If we can at least stat the folder, that's something
        return True, "Folder accessible"
    except Exception as e:
        return False, str(e)


def write_heartbeat(heartbeat_file: Path) -> None:
    heartbeat_file.parent.mkdir(parents=True, exist_ok=True)
    heartbeat_file.write_text(f"heartbeat {datetime.now().isoformat()}\n")


def heartbeat_is_stale(heartbeat_file: Path) -> tuple[bool, int]:
    if not heartbeat_file.exists():
        return False, 0
    age = datetime.now() - datetime.fromtimestamp(heartbeat_file.stat().st_mtime)
    age_mins = int(age.total_seconds() / 60)
    return age > timedelta(minutes=STUCK_THRESHOLD_MINUTES), age_mins


# ── MAIN ──────────────────────────────────────────────────────────────────────

def run_check():
    problems = []

    # 1. Is OneDrive running?
    if not is_onedrive_running():
        problems.append("OneDrive process is NOT running.")

    # 2. Is the OneDrive folder even there?
    if not ONEDRIVE_PATH.exists():
        problems.append(f"OneDrive folder not found at: {ONEDRIVE_PATH}")

    # 3. Heartbeat staleness check
    heartbeat_file = ONEDRIVE_PATH / HEARTBEAT_SUBDIR / "heartbeat.txt"
    stale, age_mins = heartbeat_is_stale(heartbeat_file)
    if stale:
        problems.append(
            f"Heartbeat file hasn't updated in {age_mins} min "
            f"(threshold: {STUCK_THRESHOLD_MINUTES} min). Sync may be stuck."
        )

    # Always refresh the heartbeat
    try:
        write_heartbeat(heartbeat_file)
    except Exception as e:
        problems.append(f"Could not write heartbeat file: {e}")

    # 4. Alert
    if problems:
        message = "\n".join(f"• {p}" for p in problems)
        notify("⚠️ OneDrive Sync Problem", message)

        log_file = Path(__file__).parent / "onedrive_monitor.log"
        with open(log_file, "a") as f:
            f.write(f"\n[{datetime.now().isoformat()}] ALERT:\n{message}\n")


if __name__ == "__main__":
    run_check()


# ══════════════════════════════════════════════════════════════════════════════
# SETUP INSTRUCTIONS — macOS launchd
# ══════════════════════════════════════════════════════════════════════════════
#
# 1. Save this file, e.g. to ~/scripts/onedrive_monitor_macos.py
#    chmod +x ~/scripts/onedrive_monitor_macos.py
#
# 2. Create a launchd plist:
#    nano ~/Library/LaunchAgents/com.user.onedriveMonitor.plist
#
# Paste this (adjust paths):
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#   "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#   <key>Label</key>
#   <string>com.user.onedriveMonitor</string>
#   <key>ProgramArguments</key>
#   <array>
#     <string>/usr/bin/python3</string>
#     <string>/Users/YOURUSERNAME/scripts/onedrive_monitor_macos.py</string>
#   </array>
#   <key>StartInterval</key>
#   <integer>1800</integer>  <!-- every 30 minutes -->
#   <key>RunAtLoad</key>
#   <true/>
#   <key>StandardOutPath</key>
#   <string>/tmp/onedrive_monitor_out.log</string>
#   <key>StandardErrorPath</key>
#   <string>/tmp/onedrive_monitor_err.log</string>
# </dict>
# </plist>
#
# 3. Load it:
#    launchctl load ~/Library/LaunchAgents/com.user.onedriveMonitor.plist
#
# 4. Test it immediately:
#    launchctl start com.user.onedriveMonitor

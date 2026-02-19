"""
OneDrive Sync Monitor — Windows
Runs silently (.pyw), shows a toast/messagebox popup if sync looks stuck.

Schedule via Task Scheduler:
  Action: Start a program
  Program: pythonw.exe  (or full path)
  Args:    "C:\path\to\onedrive_monitor_windows.pyw"
  Trigger: Every 15–30 minutes (or at logon + repeat)

Requirements:
  pip install plyer psutil
"""

import os
import sys
import time
import subprocess
import psutil
from pathlib import Path
from datetime import datetime, timedelta

# ── CONFIG ────────────────────────────────────────────────────────────────────
# Your OneDrive folder path (adjust if needed)
ONEDRIVE_PATH = Path(os.environ.get("OneDriveConsumer") or os.environ.get("OneDrive") or
                     Path.home() / "OneDrive")

# A subfolder inside OneDrive to write the heartbeat file (will be created)
HEARTBEAT_SUBDIR = "_sync_monitor"

# Alert if the heartbeat file hasn't been touched in this many minutes
# (Set to slightly more than your Task Scheduler interval)
STUCK_THRESHOLD_MINUTES = 45

# How long (seconds) to wait after writing heartbeat before checking age
# Only relevant if you run this script continuously instead of scheduled
CONTINUOUS_CHECK_INTERVAL = 60 * 20  # 20 min (ignored when run by Task Scheduler)

# ── HELPERS ───────────────────────────────────────────────────────────────────

def notify(title: str, message: str) -> None:
    """Show a Windows notification. Falls back to a MessageBox if plyer missing."""
    try:
        from plyer import notification
        notification.notify(
            title=title,
            message=message,
            app_name="OneDrive Monitor",
            timeout=30,
        )
    except Exception:
        # Pure-stdlib fallback: PowerShell toast
        ps_cmd = (
            f'[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, '
            f'ContentType = WindowsRuntime] > $null;'
            f'$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02;'
            f'$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template);'
            f'$xml.GetElementsByTagName("text")[0].AppendChild($xml.CreateTextNode("{title}")) > $null;'
            f'$xml.GetElementsByTagName("text")[1].AppendChild($xml.CreateTextNode("{message}")) > $null;'
            f'$toast = [Windows.UI.Notifications.ToastNotification]::new($xml);'
            f'[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("OneDriveMonitor").Show($toast);'
        )
        try:
            subprocess.run(["powershell", "-Command", ps_cmd], capture_output=True)
        except Exception:
            # Last resort: tkinter messagebox
            import tkinter as tk
            from tkinter import messagebox
            root = tk.Tk()
            root.withdraw()
            messagebox.showwarning(title, message)
            root.destroy()


def is_onedrive_running() -> bool:
    for proc in psutil.process_iter(["name"]):
        if proc.info["name"] and "onedrive" in proc.info["name"].lower():
            return True
    return False


def write_heartbeat(heartbeat_file: Path) -> None:
    heartbeat_file.parent.mkdir(parents=True, exist_ok=True)
    heartbeat_file.write_text(f"heartbeat {datetime.now().isoformat()}\n")


def heartbeat_is_stale(heartbeat_file: Path) -> bool:
    if not heartbeat_file.exists():
        return False  # First run — just created it, not stale yet
    age = datetime.now() - datetime.fromtimestamp(heartbeat_file.stat().st_mtime)
    return age > timedelta(minutes=STUCK_THRESHOLD_MINUTES)


def check_onedrive_status_registry() -> tuple[bool, str]:
    """
    Check OneDrive sync state from registry.
    Returns (ok: bool, status_string: str)
    Known SyncActivity values:
      0 = Up to date, 1 = Syncing, 2 = Paused, 3 = Error, 4 = Offline
    """
    try:
        import winreg
        key_path = r"SOFTWARE\Microsoft\OneDrive\Accounts\Personal"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            try:
                state, _ = winreg.QueryValueEx(key, "SyncActivity")
                states = {0: "Up to date", 1: "Syncing", 2: "Paused", 3: "Error", 4: "Offline"}
                label = states.get(state, f"Unknown({state})")
                ok = state in (0, 1)
                return ok, label
            except FileNotFoundError:
                return True, "Registry key present but SyncActivity not found"
    except Exception as e:
        return True, f"Registry check skipped: {e}"


# ── MAIN ──────────────────────────────────────────────────────────────────────

def run_check():
    problems = []

    # 1. Is OneDrive process running?
    if not is_onedrive_running():
        problems.append("OneDrive process is NOT running.")

    # 2. Registry status check
    ok, status = check_onedrive_status_registry()
    if not ok:
        problems.append(f"OneDrive status: {status}")

    # 3. Heartbeat file check
    heartbeat_file = ONEDRIVE_PATH / HEARTBEAT_SUBDIR / "heartbeat.txt"

    if heartbeat_is_stale(heartbeat_file):
        age_mins = int((datetime.now() - datetime.fromtimestamp(
            heartbeat_file.stat().st_mtime)).total_seconds() / 60)
        problems.append(
            f"Heartbeat file hasn't been updated in {age_mins} minutes "
            f"(threshold: {STUCK_THRESHOLD_MINUTES} min). Sync may be stuck."
        )

    # Always write/update the heartbeat for the next check cycle
    try:
        write_heartbeat(heartbeat_file)
    except Exception as e:
        problems.append(f"Could not write heartbeat to OneDrive folder: {e}")

    # 4. Notify if anything's wrong
    if problems:
        message = "\n".join(f"• {p}" for p in problems)
        notify("⚠️ OneDrive Sync Problem Detected", message)
        # Also log to a file next to the script
        log_file = Path(__file__).parent / "onedrive_monitor.log"
        with open(log_file, "a") as f:
            f.write(f"\n[{datetime.now().isoformat()}] ALERT:\n{message}\n")


if __name__ == "__main__":
    run_check()

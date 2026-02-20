import os
import time
import json
import socket
import ctypes
import subprocess
from pathlib import Path
from datetime import datetime, timezone

# ================= CONFIG =================

STALE_THRESHOLD_MINUTES = 10
REPEAT_ALERT_EVERY_MINUTES = 10
CHECK_INTERVAL_SECONDS = 60

# ==========================================

BASE_PATH = Path("D:/OneDrive")
if not BASE_PATH.exists():
    BASE_PATH = Path(
        os.environ.get("OneDriveConsumer")
        or os.environ.get("OneDrive")
        or Path.home() / "OneDrive"
    )

HEARTBEAT_FILE = BASE_PATH / "onedrive_heartbeat.json"
MACHINE_NAME = socket.gethostname()

last_alert_time = None
alert_active = False


# ---------- Toast Notification ----------

def send_toast(title, message):
    ps_script = f"""
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $template = @"
    <toast>
        <visual>
            <binding template="ToastGeneric">
                <text>{title}</text>
                <text>{message}</text>
            </binding>
        </visual>
    </toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("OneDriveMonitor")
    $notifier.Show($toast)
    """
    subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps_script],
        capture_output=True
    )


# ---------- Modal Popup ----------

def show_modal(title, message):
    MB_ICONWARNING = 0x30
    MB_SYSTEMMODAL = 0x1000
    MB_TOPMOST = 0x00040000
    ctypes.windll.user32.MessageBoxW(
        0,
        message,
        title,
        MB_ICONWARNING | MB_SYSTEMMODAL | MB_TOPMOST
    )


# ---------- Heartbeat Logic ----------

def read_heartbeat():
    if not HEARTBEAT_FILE.exists():
        raise FileNotFoundError("Heartbeat file missing")

    content = HEARTBEAT_FILE.read_text().strip()
    if not content:
        raise ValueError("Heartbeat file empty")

    data = json.loads(content)
    return datetime.fromisoformat(data["timestamp"])


def heartbeat_age_minutes(timestamp):
    now = datetime.now(timezone.utc)
    delta = now - timestamp
    return delta.total_seconds() / 60


# ---------- Main Loop ----------

while True:
    try:
        ts = read_heartbeat()
        age = heartbeat_age_minutes(ts)

        if age > STALE_THRESHOLD_MINUTES:
            now = time.time()

            if (
                not alert_active
                or last_alert_time is None
                or (now - last_alert_time)
                > REPEAT_ALERT_EVERY_MINUTES * 60
            ):
                message = (
                    f"Machine: {MACHINE_NAME}\n"
                    f"Heartbeat stale: {int(age)} minutes old\n"
                    f"File: {HEARTBEAT_FILE}"
                )

                send_toast("OneDrive Sync Problem", message)
                show_modal("ONEDRIVE CRITICAL", message)

                last_alert_time = now
                alert_active = True

        else:
            # If previously in alert state, notify recovery
            if alert_active:
                send_toast(
                    "OneDrive Sync Restored",
                    f"{MACHINE_NAME} heartbeat healthy again."
                )
                alert_active = False
                last_alert_time = None

    except Exception as e:
        send_toast("MONITOR SCRIPT ERROR", str(e))
        show_modal("MONITOR SCRIPT ERROR", str(e))
        alert_active = True

    time.sleep(CHECK_INTERVAL_SECONDS)

#!/usr/bin/env python3
"""
onedrive_heartbeat_writer_mac.py — macOS heartbeat + machine info writer
Writes heartbeat_{host}.txt and machine_info_{host}.json to OneDrive _sync_monitor/{host}/
Interval: 150 seconds (same as PowerShell writer on Windows machines)
Created: 2026-06-15 23:00 UTC
Updated: 2026-06-16 09:30 UTC — fix RAM calculation to match Activity Monitor (correct page size, active+wired+compressor)
"""

import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────

HOST = "denniss-macbook-air"
INTERVAL_SECONDS = 150
ONEDRIVE_PATH = Path.home() / "OneDrive"
OUTPUT_DIR = ONEDRIVE_PATH / "_sync_monitor" / HOST


# ── Data collection ────────────────────────────────────────────

def get_ram() -> tuple[float, float]:
    """Returns (ram_total_gb, ram_used_gb) matching Activity Monitor methodology."""
    # Total RAM
    out = subprocess.check_output(["sysctl", "-n", "hw.memsize"]).decode().strip()
    total_bytes = int(out)
    total_gb = round(total_bytes / (1024 ** 3), 1)

    # Used RAM via vm_stat — page size varies by hardware (16KB on Apple Silicon)
    vm = subprocess.check_output(["vm_stat"]).decode()

    # Extract actual page size from vm_stat header
    m = re.search(r"page size of (\d+) bytes", vm)
    page_size = int(m.group(1)) if m else 16384

    def pages(label):
        m = re.search(rf"{label}:\s+(\d+)", vm)
        return int(m.group(1)) if m else 0

    # Match Activity Monitor: used = active + wired + compressor
    active     = pages("Pages active")
    wired      = pages("Pages wired down")
    compressor = pages("Pages occupied by compressor")
    used_bytes = (active + wired + compressor) * page_size
    used_gb = round(used_bytes / (1024 ** 3), 1)
    return total_gb, used_gb


def get_cpu_percent() -> float:
    """Returns CPU usage percent (1-second sample via top)."""
    try:
        out = subprocess.check_output(
            ["top", "-l", "2", "-n", "0", "-s", "1"],
            stderr=subprocess.DEVNULL
        ).decode()
        # Take the last CPU line (second sample)
        matches = re.findall(r"CPU usage:\s+([\d.]+)%\s+user,\s+([\d.]+)%\s+sys", out)
        if matches:
            user, sys_ = matches[-1]
            return round(float(user) + float(sys_), 1)
    except Exception:
        pass
    return 0.0


def get_disks() -> list[dict]:
    """Returns list of disk dicts matching Windows schema.
    Includes: / (system), /System/Volumes/Data (user data), /Volumes/* (USB etc).
    """
    out = subprocess.check_output(["df", "-g"]).decode()
    disks = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 9:
            continue
        filesystem = parts[0]
        if not filesystem.startswith("/dev/"):
            continue
        mount = parts[8]
        # Only include meaningful mounts
        if mount not in ("/", "/System/Volumes/Data") and not mount.startswith("/Volumes/"):
            continue
        total_gb = float(parts[1])
        used_gb = float(parts[2])
        free_gb = float(parts[3])
        disks.append({
            "drive": mount,
            "total_gb": round(total_gb, 1),
            "used_gb": round(used_gb, 1),
            "free_gb": round(free_gb, 1),
        })
    return disks


def get_last_reboot() -> str:
    """Returns last reboot as 'Mon DD HH:MM' string."""
    try:
        out = subprocess.check_output(["sysctl", "-n", "kern.boottime"]).decode()
        # Output: { sec = 1749999999, usec = 123456 } Mon Jun  9 20:35:00 2026
        m = re.search(r"\}\s+(.+)$", out.strip())
        if m:
            dt = datetime.strptime(m.group(1).strip(), "%a %b %d %H:%M:%S %Y")
            return dt.strftime("%b %-d %H:%M")
    except Exception:
        pass
    return "unknown"


def get_os_info() -> tuple[str, str, str, bool]:
    """
    Returns (last_wu_date, last_wu_kb, last_wu_reboot, pending_reboot).
    last_wu_kb will be the update name (no KB numbers on macOS).
    """
    last_wu_date = "unknown"
    last_wu_kb = "unknown"
    last_wu_reboot = "unknown"
    pending_reboot = False

    try:
        out = subprocess.check_output(
            ["softwareupdate", "--history"],
            stderr=subprocess.DEVNULL
        ).decode()
        # Only consider lines that are macOS OS updates (start with "macOS ")
        os_lines = [
            l for l in out.splitlines()
            if l.strip().startswith("macOS ")
        ]
        if os_lines:
            last = os_lines[-1]
            # Format: "macOS Tahoe 26.2                                   26.2       01/28/2026, 13:40:11"
            m = re.match(r"(macOS\s+\S+\s+[\d.]+)\s+[\d.]+\s+(\d{2}/\d{2}/\d{4}),\s+([\d:]+)", last)
            if m:
                last_wu_kb = m.group(1).strip()
                dt = datetime.strptime(f"{m.group(2)} {m.group(3)}", "%m/%d/%Y %H:%M:%S")
                last_wu_date = dt.strftime("%b %-d %H:%M")
                last_wu_reboot = last_wu_date
    except Exception:
        pass

    # Pending reboot: check if softwareupdate has downloaded updates waiting
    try:
        out = subprocess.check_output(
            ["softwareupdate", "-l"],
            stderr=subprocess.STDOUT
        ).decode()
        if "restart" in out.lower() or "recommended" in out.lower():
            pending_reboot = True
    except Exception:
        pass

    return last_wu_date, last_wu_kb, last_wu_reboot, pending_reboot


def get_os_build() -> str:
    try:
        product = subprocess.check_output(["sw_vers", "-productVersion"]).decode().strip()
        build = subprocess.check_output(["sw_vers", "-buildVersion"]).decode().strip()
        return f"{product} ({build})"
    except Exception:
        return "unknown"


# ── Write functions ────────────────────────────────────────────

def write_heartbeat(output_dir: Path, host: str):
    ts = datetime.now(timezone.utc).isoformat()
    hb_file = output_dir / f"heartbeat_{host}.txt"
    hb_file.write_text(ts, encoding="utf-8")


def write_machine_info(output_dir: Path, host: str):
    ram_total, ram_used = get_ram()
    cpu = get_cpu_percent()
    disks = get_disks()
    last_reboot = get_last_reboot()
    last_wu_date, last_wu_kb, last_wu_reboot, pending_reboot = get_os_info()
    os_build = get_os_build()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    info = {
        "host": host,
        "timestamp_utc": ts,
        "ram_total_gb": ram_total,
        "ram_used_gb": ram_used,
        "cpu_percent": cpu,
        "disks": disks,
        "last_reboot": last_reboot,
        "last_wu_date": last_wu_date,
        "last_wu_kb": last_wu_kb,
        "last_wu_reboot": last_wu_reboot,
        "os_build": os_build,
        "pending_reboot": pending_reboot,
    }

    info_file = output_dir / f"machine_info_{host}.json"
    info_file.write_text(json.dumps(info, indent=4), encoding="utf-8")


# ── Main loop ──────────────────────────────────────────────────

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[{datetime.now(timezone.utc).isoformat()}] Starting heartbeat writer for {HOST}")
    print(f"  Output dir: {OUTPUT_DIR}")

    while True:
        try:
            write_heartbeat(OUTPUT_DIR, HOST)
            write_machine_info(OUTPUT_DIR, HOST)
            print(f"[{datetime.now(timezone.utc).isoformat()}] Written OK")
        except Exception as e:
            print(f"[{datetime.now(timezone.utc).isoformat()}] ERROR: {e}")
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()

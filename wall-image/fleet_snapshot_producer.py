#!/usr/bin/env python3
"""fleet_snapshot_producer.py -- draws the fleet-wall grid + per-host detail
screens with Pillow (no headless browser, no fonts-over-network) and writes
them into wall_server.py's inbox/fleet/. Same machine_info/services schema
as esp-firmware/fleet_wall*.

Does NOT touch the network itself -- reads inbox/fleet/status.json, which
fetch_fleet_status.sh writes on its own timer. That split exists because of
a macOS Local Network permission quirk (confirmed 2026-09-22): under
launchd, curl succeeds when its immediate parent is bash, but fails when
its immediate parent is an unsigned Homebrew python3, even with a trusted
bash further up the ancestry chain. See fetch_fleet_status.sh's docstring.

Run continuously (its own loop, polling that file, not the network) under
launchd. Needs: venv/bin/python3 (pillow) -- NOT the bare system python3.
2026-09-22
"""
import io
import json
import os
import time

from PIL import Image, ImageDraw, ImageFont

W, H = 800, 480
GRID_COLS, GRID_ROWS = 6, 3
HEADER_H, FOOTER_H = 40, 28
CELL_W = W // GRID_COLS
CELL_H = (H - HEADER_H - FOOTER_H) // GRID_ROWS

BASE = os.path.dirname(os.path.abspath(__file__))
INBOX = os.path.join(BASE, "inbox", "fleet")

COL_BG = (10, 16, 17)
COL_PANEL = (15, 23, 25)
COL_PANEL2 = (12, 20, 22)
COL_LINE = (30, 47, 48)
COL_TEAL = (53, 214, 193)
COL_OK = (72, 209, 122)
COL_WARN = (240, 168, 60)
COL_CRIT = (255, 98, 89)
COL_TEXT = (223, 238, 236)
COL_TEXT_DIM = (132, 160, 156)
COL_TEXT_FAINT = (77, 102, 99)

_font_cache = {}

# This script's own mtime, formatted once at import time -- shown in the
# header so it's possible to tell at a glance whether a producer restart
# actually picked up a recent edit (same idea as __DATE__/__TIME__ in the
# old ESP32 firmware, but pointed at this file: there's no board-side
# rendering left to verify in this architecture, the producer script is the
# thing that changes). Recomputed from disk, not hand-bumped, so it can't
# go stale the way a manually-typed version string would.
_BUILD_STAMP = time.strftime("V-%Y.%m.%d.%H.%M", time.localtime(os.path.getmtime(os.path.abspath(__file__))))


def font(size, bold=False):
    key = (size, bold)
    if key not in _font_cache:
        # DejaVu Sans ships with Pillow itself (PIL/fonts/) -- no system font
        # dependency, no network fetch, so a headless/minimal box still works.
        try:
            name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
            _font_cache[key] = ImageFont.truetype(name, size)
        except OSError:
            _font_cache[key] = ImageFont.load_default()
    return _font_cache[key]


def status_color(status):
    return {"up": COL_OK, "down": COL_CRIT, "warn": COL_WARN}.get(status, COL_TEXT_FAINT)


def pct_color(pct):
    if pct is None:
        return COL_TEXT_FAINT
    if pct >= 90:
        return COL_CRIT
    if pct >= 70:
        return COL_WARN
    return COL_TEAL


def to_rgb565_bytes(img: Image.Image) -> bytes:
    assert img.size == (W, H)
    img = img.convert("RGB")
    out = bytearray(W * H * 2)
    px = img.load()
    i = 0
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            out[i] = v & 0xFF
            out[i + 1] = v >> 8
            i += 2
    return bytes(out)


STATUS_PATH = os.path.join(INBOX, "status.json")


def read_status():
    """Reads the JSON fetch_fleet_status.sh last wrote -- this process does
    no networking itself. Returns None if the file doesn't exist yet (the
    fetcher hasn't completed its first poll) or is mid-write (fetcher writes
    to .tmp then renames, so a torn read here should be rare, but a bad
    parse just means "nothing new this tick," not a crash)."""
    if not os.path.exists(STATUS_PATH):
        return None
    try:
        with open(STATUS_PATH) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def draw_grid(data):
    img = Image.new("RGB", (W, H), COL_BG)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, W, HEADER_H], fill=COL_PANEL2)
    d.text((14, 12), "FLEET_WALL - CONSOLIDATED", font=font(14, True), fill=COL_TEAL)
    d.text((W - 150, 12), _BUILD_STAMP, font=font(12), fill=COL_TEXT_FAINT)

    machines = data.get("machines", [])[: GRID_COLS * GRID_ROWS]
    summary = data.get("summary", {})
    tapmap = []

    for i, m in enumerate(machines):
        col, row = i % GRID_COLS, i // GRID_COLS
        x0, y0 = col * CELL_W, HEADER_H + row * CELL_H
        x1, y1 = x0 + CELL_W, y0 + CELL_H

        host_info = m.get("host", {})
        minfo = m.get("machine_info") or {}
        status = host_info.get("status", "unknown")
        sc = status_color(status)
        name = m["machine"]["display_name"]
        tailscale_name = m["machine"].get("tailscale_name", name.lower())

        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=COL_PANEL, outline=COL_LINE)
        d.rectangle([x0, y0, x0 + 3, y1 - 1], fill=sc)  # left status stripe

        pad = 10
        d.text((x0 + pad, y0 + 6), name[:16], font=font(15, True), fill=COL_TEXT)

        ping = host_info.get("response_time_ms")
        if ping is not None:
            d.text((x0 + pad, y0 + 26), f"{ping}ms", font=font(12), fill=COL_TEXT_FAINT)

        cpu = minfo.get("cpu_percent")
        cpu = round(cpu) if cpu is not None else None
        ram_pct = None
        if minfo.get("ram_total_gb"):
            ram_pct = round(100 * minfo.get("ram_used_gb", 0) / minfo["ram_total_gb"])
        stat_label, stat_pct = ("CPU", cpu) if cpu is not None else ("MEM", ram_pct)
        bar_y = y0 + 48
        if stat_pct is not None:
            bar_x0, bar_x1 = x0 + pad, x1 - pad
            d.rectangle([bar_x0, bar_y, bar_x1, bar_y + 6], fill=COL_LINE)
            filled = bar_x0 + int((bar_x1 - bar_x0) * min(stat_pct, 100) / 100)
            d.rectangle([bar_x0, bar_y, filled, bar_y + 6], fill=pct_color(stat_pct))
            label = f"{stat_label} {min(stat_pct, 999)}%"
            # A wide cell label ("CPU 100%") can run past a narrow 133px cell
            # at this font -- clip to the cell rather than overflow into the
            # next tile's space.
            max_w = (x1 - pad) - (x0 + pad)
            while d.textlength(label, font=font(12)) > max_w and len(label) > 4:
                label = label[:-1]
            d.text((x0 + pad, bar_y + 10), label, font=font(12), fill=COL_TEXT_DIM)

        d.text((x0 + pad, y1 - 20), status.upper(), font=font(12, True), fill=sc)

        tapmap.append({"x0": x0, "y0": y0, "x1": x1, "y1": y1, "host": tailscale_name})

    fy0 = H - FOOTER_H
    d.rectangle([0, fy0, W, H], fill=COL_PANEL2)
    up, total = summary.get("machines_up", 0), summary.get("machines_total", 0)
    sup, stotal = summary.get("services_up", 0), summary.get("services_total", 0)
    d.text((10, fy0 + 6), f"HOSTS {up}/{total}  SERVICES {sup}/{stotal}", font=font(13), fill=COL_TEXT_FAINT)

    stamp = time.strftime("%Y %m %d %H %M %S")
    stamp_w = d.textlength(stamp, font=font(13, True))
    d.text((W - stamp_w - 10, fy0 + 6), stamp, font=font(13, True), fill=COL_TEXT)

    return img, tapmap


def draw_detail(m):
    img = Image.new("RGB", (W, H), COL_BG)
    d = ImageDraw.Draw(img)
    host_info, minfo = m.get("host", {}), (m.get("machine_info") or {})
    status = host_info.get("status", "unknown")
    sc = status_color(status)

    d.text((24, 20), m["machine"]["display_name"], font=font(28, True), fill=COL_TEXT)
    d.text((24, 58), m["machine"].get("primary_role", ""), font=font(16), fill=COL_TEXT_DIM)
    d.text((24, 84), status.upper(), font=font(16, True), fill=sc)

    y = 130
    cpu = minfo.get("cpu_percent")
    if cpu is not None:
        d.text((24, y), f"CPU {cpu}%", font=font(16), fill=COL_TEXT)
        d.rectangle([24, y + 24, W - 24, y + 34], fill=COL_LINE)
        d.rectangle([24, y + 24, 24 + int((W - 48) * cpu / 100), y + 34], fill=pct_color(cpu))
        y += 50
    if minfo.get("ram_total_gb"):
        ram_pct = round(100 * minfo.get("ram_used_gb", 0) / minfo["ram_total_gb"])
        d.text((24, y), f"MEM {minfo['ram_used_gb']:.1f}/{minfo['ram_total_gb']:.1f}G ({ram_pct}%)",
               font=font(16), fill=COL_TEXT)
        d.rectangle([24, y + 24, W - 24, y + 34], fill=COL_LINE)
        d.rectangle([24, y + 24, 24 + int((W - 48) * ram_pct / 100), y + 34], fill=pct_color(ram_pct))
        y += 50

    y += 10
    for svc in m.get("services", [])[:6]:
        tsc = (svc.get("tailscale_check") or {}).get("status", "unknown")
        d.text((24, y), svc.get("name", "?"), font=font(15), fill=COL_TEXT)
        d.text((W - 140, y), tsc.upper(), font=font(15), fill=status_color(tsc))
        y += 26

    d.text((24, H - 30), "tap to return", font=font(13), fill=COL_TEXT_FAINT)
    return img


def write_atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def run_once(data):
    grid_img, tapmap = draw_grid(data)
    write_atomic(os.path.join(INBOX, "grid.rgb565"), to_rgb565_bytes(grid_img))
    write_atomic(os.path.join(INBOX, "grid.json"), json.dumps({"tapmap": tapmap}).encode())

    detail_dir = os.path.join(INBOX, "detail")
    os.makedirs(detail_dir, exist_ok=True)
    for m in data.get("machines", []):
        tailscale_name = m["machine"].get("tailscale_name") or m["machine"]["display_name"].lower()
        safe = "".join(c for c in tailscale_name if c.isalnum() or c in "-_")
        detail_img = draw_detail(m)
        write_atomic(os.path.join(detail_dir, f"{safe}.rgb565"), to_rgb565_bytes(detail_img))


if __name__ == "__main__":
    os.makedirs(INBOX, exist_ok=True)
    print(f"[fleet_snapshot_producer] watching {STATUS_PATH}", flush=True)
    last_mtime = 0.0
    while True:
        try:
            mtime = os.path.getmtime(STATUS_PATH) if os.path.exists(STATUS_PATH) else 0.0
            if mtime != last_mtime:
                data = read_status()
                if data is not None:
                    t0 = time.time()
                    run_once(data)
                    last_mtime = mtime
                    print(f"[fleet_snapshot_producer] wrote grid + details in {time.time() - t0:.2f}s", flush=True)
        except (OSError, KeyError, ValueError) as e:
            print(f"[fleet_snapshot_producer] error: {e}", flush=True)
        time.sleep(1)  # cheap check; the real cadence is however often fetch_fleet_status.sh actually writes

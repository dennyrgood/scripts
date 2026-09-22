#!/usr/bin/env python3
"""Spike server for fleet_wall_image_spike: serves a synthetic 800x480 RGB565
test frame that changes every FRAME_SECONDS, so the ESP32 has to re-download
and blit a full, all-pixels-different frame each time (worst case for the
PSRAM-bandwidth drift problem).

Test pattern (chosen so any shift/tear/color-order bug is obvious):
  - white 3px border and 80px grid lines: a vertical shift or wrap shows
    immediately as a displaced/duplicated border
  - top bar: red, green, blue, white, black: wrong colors = wrong byte order
  - gradient background that changes every frame (every pixel differs)
  - big 7-segment frame counter + server clock in the middle

Endpoints: /frame.hash ("<id>:<crc32 hex>"), /frame.rgb565 (768000 bytes, LE).
Stdlib only (no PIL/numpy on this box). Run: python3 image_server.py
"""
import os
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

W, H = 800, 480
FRAME_SECONDS = int(os.environ.get("FRAME_SECONDS", "15"))
PORT = int(os.environ.get("PORT", "8099"))

SEGS = {  # a b c d e f g
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
    "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}

_lock = threading.Lock()
_cache = {"id": None, "data": None, "crc": 0}


def c565(r, g, b):
    v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    return bytes((v & 0xFF, v >> 8))  # little-endian, as esp_lcd expects


def fill(rows, x0, y0, x1, y1, color):
    x0, x1 = max(0, x0), min(W, x1)
    px = color * (x1 - x0)
    for y in range(max(0, y0), min(H, y1)):
        rows[y][x0 * 2:x1 * 2] = px


def digit(rows, ch, x, y, s, color):
    t = s // 6 or 1
    w, h = s * 3 // 5, s
    segs = SEGS.get(ch, "")
    pos = {
        "a": (x, y, x + w, y + t), "g": (x, y + h // 2 - t // 2, x + w, y + h // 2 + t // 2 + 1),
        "d": (x, y + h - t, x + w, y + h), "f": (x, y, x + t, y + h // 2),
        "b": (x + w - t, y, x + w, y + h // 2), "e": (x, y + h // 2, x + t, y + h),
        "c": (x + w - t, y + h // 2, x + w, y + h),
    }
    for sg in segs:
        fill(rows, *pos[sg], color)


def text(rows, s, x, y, size, color):
    for ch in s:
        if ch != ":":
            digit(rows, ch, x, y, size, color)
        else:
            fill(rows, x + 4, y + size // 3, x + 10, y + size // 3 + 8, color)
            fill(rows, x + 4, y + 2 * size // 3, x + 10, y + 2 * size // 3 + 8, color)
        x += size * 3 // 5 + size // 5


def render(fid):
    rows = []
    for y in range(H):
        row = bytearray(W * 2)
        for x in range(W):
            r = (x * 255 // (W - 1) + fid * 23) & 255
            g = (y * 255 // (H - 1) + fid * 41) & 255
            b = (fid * 67 + (x + y)) & 255
            v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            row[x * 2] = v & 0xFF
            row[x * 2 + 1] = v >> 8
        rows.append(row)
    white, black = c565(255, 255, 255), c565(0, 0, 0)
    for gx in range(80, W, 80):
        fill(rows, gx, 0, gx + 1, H, white)
    for gy in range(80, H, 80):
        fill(rows, 0, gy, W, gy + 1, white)
    bars = [c565(255, 0, 0), c565(0, 255, 0), c565(0, 0, 255), white, black]
    for i, col in enumerate(bars):
        fill(rows, i * 160, 3, (i + 1) * 160, 43, col)
    fill(rows, 150, 140, 650, 340, black)
    text(rows, f"{fid % 100000:05d}", 190, 160, 110, white)
    text(rows, time.strftime("%H:%M:%S"), 260, 290, 40, c565(255, 255, 0))
    fill(rows, 0, 0, W, 3, white)
    fill(rows, 0, H - 3, W, H, white)
    fill(rows, 0, 0, 3, H, white)
    fill(rows, W - 3, 0, W, H, white)
    return b"".join(bytes(r) for r in rows)


def current():
    fid = int(time.time() // FRAME_SECONDS)
    with _lock:
        if _cache["id"] != fid:
            t0 = time.time()
            _cache["data"] = render(fid)
            _cache["crc"] = zlib.crc32(_cache["data"])
            _cache["id"] = fid
            print(f"rendered frame {fid} in {time.time() - t0:.2f}s", flush=True)
        return _cache["id"], _cache["data"], _cache["crc"]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/frame.hash":
            fid, _, crc = current()
            body = f"{fid}:{crc:08x}".encode()
            ctype = "text/plain"
        elif self.path == "/frame.rgb565":
            _, body, _ = current()
            ctype = "application/octet-stream"
        else:
            body = b"fleet_wall_image_spike: /frame.hash /frame.rgb565\n"
            ctype = "text/plain"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"serving on 0.0.0.0:{PORT}, new frame every {FRAME_SECONDS}s", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

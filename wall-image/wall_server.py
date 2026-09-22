#!/usr/bin/env python3
"""wall_server.py -- resident daemon serving pixels to fleet_wall_image
ESP32 boards. Generalizes fleet_wall_image_spike/image_server.py's proven
poll/fetch/CRC-verify pattern into two independent channels: each physical
device is pointed at ONE channel (via its own secrets.h URL prefix) and
stays there for its whole life -- no shared queue, no priority/preemption,
because a device is either "the fleet wall" or "the photo frame", never both.

Channels:
  /fleet/frame.hash /fleet/frame.rgb565    -- current fleet snapshot, tap-interactive
  /fleet/tap        (POST {"x":.., "y":..}) -- maps to the current image's tapmap;
                                                a hit switches this channel to that
                                                host's pre-rendered detail image;
                                                any tap while already in detail
                                                returns to the fleet grid.
  /photos/frame.hash /photos/frame.rgb565  -- current photo, no tap handling

Producers own image production and just write files:
  inbox/fleet/grid.rgb565      + grid.json      (tapmap: [{x0,y0,x1,y1,host}, ...])
  inbox/fleet/detail/<host>.rgb565              (no sidecar needed)
  inbox/photos/current.rgb565                   (photo_producer picks/rotates)
This daemon only reads inbox/ and serves whatever's there -- it renders nothing.

Frame format: 800x480 RGB565, little-endian, 768000 bytes -- same as the spike.
Stdlib only (no Flask) so this can run standalone under launchd with no venv.
2026-09-22
"""
import hashlib
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

W, H = 800, 480
FRAME_BYTES = W * H * 2
BASE = os.path.dirname(os.path.abspath(__file__))
INBOX = os.path.join(BASE, "inbox")
PORT = int(os.environ.get("WALL_SERVER_PORT", "8099"))

# Tap on the detail view auto-returns to the fleet grid after this long with
# no further tap, so a device that never taps again doesn't get stuck showing
# one host forever.
DETAIL_TIMEOUT_S = 120


def _hash_bytes(b: bytes) -> str:
    return hashlib.sha1(b).hexdigest()[:16]


class Channel:
    """One independent frame slot. Thread-safe; polled by GET, mutated by
    either a producer's file drop (fleet/photos) or a tap (fleet only)."""

    def __init__(self, name):
        self.name = name
        self.lock = threading.Lock()
        self.data = b"\x00\x00" * (W * H // 2) + b"\xff\xff" * (W * H // 2)  # placeholder until first producer write
        self.hash = _hash_bytes(self.data)
        self.mtime = 0.0

    def set_bytes(self, data: bytes):
        if len(data) != FRAME_BYTES:
            return False
        h = _hash_bytes(data)
        with self.lock:
            if h != self.hash:
                self.data = data
                self.hash = h
        self.mtime = time.time()
        return True

    def get(self):
        with self.lock:
            return self.hash, self.data


fleet_chan = Channel("fleet")
photos_chan = Channel("photos")

# Fleet-only tap state: which image is "live" (grid vs a detail host), and
# the grid's tapmap so a tap coordinate can be resolved to a host.
_fleet_state_lock = threading.Lock()
_fleet_state = {"mode": "grid", "detail_host": None, "detail_since": 0.0, "tapmap": []}


def _fleet_grid_path():
    return os.path.join(INBOX, "fleet", "grid.rgb565")


def _fleet_detail_path(host):
    safe = "".join(c for c in host if c.isalnum() or c in "-_")
    return os.path.join(INBOX, "fleet", "detail", f"{safe}.rgb565")


def _load_fleet_grid():
    p = _fleet_grid_path()
    if not os.path.exists(p):
        return
    with open(p, "rb") as f:
        data = f.read()
    tapmap = []
    jpath = p[:-len(".rgb565")] + ".json"
    if os.path.exists(jpath):
        try:
            with open(jpath) as f:
                tapmap = json.load(f).get("tapmap", [])
        except (json.JSONDecodeError, OSError):
            tapmap = []
    with _fleet_state_lock:
        _fleet_state["tapmap"] = tapmap
    if _fleet_state["mode"] == "grid":
        fleet_chan.set_bytes(data)


def _load_fleet_detail(host):
    p = _fleet_detail_path(host)
    if not os.path.exists(p):
        return False
    with open(p, "rb") as f:
        return fleet_chan.set_bytes(f.read())


def _load_photo():
    p = os.path.join(INBOX, "photos", "current.rgb565")
    if os.path.exists(p):
        with open(p, "rb") as f:
            photos_chan.set_bytes(f.read())


def _hit_test(x, y, tapmap):
    for cell in tapmap:
        if cell["x0"] <= x < cell["x1"] and cell["y0"] <= y < cell["y1"]:
            return cell.get("host")
    return None


def handle_tap(x, y):
    """Fleet channel only. Grid + hit -> that host's detail. Anything else
    while in detail (a hit, a miss, or a timeout) -> back to the grid."""
    with _fleet_state_lock:
        mode = _fleet_state["mode"]
        tapmap = _fleet_state["tapmap"]

    if mode == "detail":
        with _fleet_state_lock:
            _fleet_state["mode"] = "grid"
            _fleet_state["detail_host"] = None
        _load_fleet_grid()
        return {"mode": "grid"}

    host = _hit_test(x, y, tapmap)
    if host and _load_fleet_detail(host):
        with _fleet_state_lock:
            _fleet_state["mode"] = "detail"
            _fleet_state["detail_host"] = host
            _fleet_state["detail_since"] = time.time()
        return {"mode": "detail", "host": host}
    return {"mode": "grid"}


def _watch_loop():
    """Polls inbox/ for producer writes. A real filesystem watch (watchdog
    lib) would be nicer, but this stays stdlib-only and 1s latency is fine --
    devices themselves only poll every 15s."""
    last_grid_mtime = last_photo_mtime = 0.0
    while True:
        try:
            gp = _fleet_grid_path()
            if os.path.exists(gp):
                m = os.path.getmtime(gp)
                if m != last_grid_mtime:
                    last_grid_mtime = m
                    _load_fleet_grid()
            pp = os.path.join(INBOX, "photos", "current.rgb565")
            if os.path.exists(pp):
                m = os.path.getmtime(pp)
                if m != last_photo_mtime:
                    last_photo_mtime = m
                    _load_photo()
            with _fleet_state_lock:
                stuck = (
                    _fleet_state["mode"] == "detail"
                    and time.time() - _fleet_state["detail_since"] > DETAIL_TIMEOUT_S
                )
            if stuck:
                with _fleet_state_lock:
                    _fleet_state["mode"] = "grid"
                    _fleet_state["detail_host"] = None
                _load_fleet_grid()
        except OSError as e:
            print(f"[wall_server] watch loop error: {e}", flush=True)
        time.sleep(1)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/fleet/frame.hash":
            h, _ = fleet_chan.get()
            self._send(200, h.encode())
        elif self.path == "/fleet/frame.rgb565":
            _, d = fleet_chan.get()
            self._send(200, d, "application/octet-stream")
        elif self.path == "/photos/frame.hash":
            h, _ = photos_chan.get()
            self._send(200, h.encode())
        elif self.path == "/photos/frame.rgb565":
            _, d = photos_chan.get()
            self._send(200, d, "application/octet-stream")
        else:
            self._send(200, b"wall_server: /fleet/* /photos/*\n")

    def do_POST(self):
        if self.path != "/fleet/tap":
            self._send(404, b"not found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw)
            x, y = int(body["x"]), int(body["y"])
        except (json.JSONDecodeError, KeyError, ValueError):
            self._send(400, b'{"error":"expected {\\"x\\":int,\\"y\\":int}"}', "application/json")
            return
        result = handle_tap(x, y)
        self._send(200, json.dumps(result).encode(), "application/json")

    def log_message(self, fmt, *args):
        print(f"{time.strftime('%H:%M:%S')} {self.client_address[0]} {fmt % args}", flush=True)


if __name__ == "__main__":
    for sub in ("fleet", "fleet/detail", "photos"):
        os.makedirs(os.path.join(INBOX, sub), exist_ok=True)
    _load_fleet_grid()
    _load_photo()
    threading.Thread(target=_watch_loop, daemon=True).start()
    print(f"[wall_server] serving on 0.0.0.0:{PORT}, inbox={INBOX}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

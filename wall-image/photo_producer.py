#!/usr/bin/env python3
"""photo_producer.py -- picks the next image from a source folder, crops/scales
it to 800x480, converts to RGB565, and writes it into wall_server.py's
inbox/photos/current.rgb565. No source folder is hardcoded: point this at
whatever directory you want to rotate through (a plain folder of JPG/PNG/etc,
not an opaque .photoslibrary package -- export from Photos first if needed).

Usage:
  ./venv/bin/python3 photo_producer.py --source ~/some/folder [--seconds 300]

Rotation order is shuffled once at startup and persisted to .rotation_state
in the source folder (survives a restart; a source folder change starts a
fresh shuffle). New files dropped into the source folder later are picked up
and appended to the back of the current rotation on the next cycle.

Checks inbox/photos/control.json once a second for a command from
wall_server.py's prev/next/pause/resume gestures (see that file's docstring)
-- ticks fast so a tap feels responsive, but only actually re-renders when
there's a command or the auto-advance interval has elapsed, not every tick.
2026-09-22
"""
import argparse
import json
import os
import random
import time

from PIL import Image, ImageOps

W, H = 800, 480
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff"}
BASE = os.path.dirname(os.path.abspath(__file__))
INBOX = os.path.join(BASE, "inbox", "photos")


def to_rgb565_bytes(img: Image.Image) -> bytes:
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


def prep_image(path):
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)  # respect phone-camera rotation tags
    # Letterbox/pillarbox, not crop-to-cover: a portrait photo used to get
    # its top and bottom cut off to fill the 800x480 frame. Instead, scale
    # so the whole image fits inside 800x480 (whichever dimension is the
    # tighter constraint), then center it on a black canvas.
    img = ImageOps.contain(img, (W, H), method=Image.LANCZOS)
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    return canvas


def list_images(source):
    files = []
    for name in sorted(os.listdir(source)):
        if os.path.splitext(name)[1].lower() in EXTS:
            files.append(name)
    return files


def load_rotation(source):
    state_path = os.path.join(source, ".rotation_state")
    if os.path.exists(state_path):
        try:
            with open(state_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"order": [], "index": 0}


def save_rotation(source, state):
    state_path = os.path.join(source, ".rotation_state")
    with open(state_path + ".tmp", "w") as f:
        json.dump(state, f)
    os.replace(state_path + ".tmp", state_path)


def refresh_order(source, state):
    """Adds newly-seen files to the back of the rotation (shuffled among
    themselves) and drops files that disappeared, without disturbing state
    for files that are still there -- called every tick, must be cheap."""
    current_files = set(list_images(source))
    known = set(state["order"])
    new_files = sorted(current_files - known)
    if new_files:
        random.shuffle(new_files)
        state["order"].extend(new_files)
    removed = [f for f in state["order"] if f not in current_files]
    if removed:
        current_name = state["order"][state["index"]] if state["order"] else None
        state["order"] = [f for f in state["order"] if f in current_files]
        if state["order"]:
            state["index"] = state["order"].index(current_name) if current_name in state["order"] else 0
        else:
            state["index"] = 0


def write_atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def show(source, state):
    name = state["order"][state["index"]]
    t0 = time.time()
    img = prep_image(os.path.join(source, name))
    write_atomic(os.path.join(INBOX, "current.rgb565"), to_rgb565_bytes(img))
    print(f"[photo_producer] showing {name} ({time.time() - t0:.2f}s)", flush=True)


def read_control(control_path, last_seq):
    """Returns (action, new_last_seq). action is None if there's nothing new
    to apply -- either no control file yet, or its seq is one we already
    handled (wall_server.py bumps seq on every write, so an unchanged seq
    means an unconsumed old command, not a fresh one)."""
    if not os.path.exists(control_path):
        return None, last_seq
    try:
        with open(control_path) as f:
            ctrl = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None, last_seq
    seq = ctrl.get("seq", 0)
    if seq <= last_seq:
        return None, last_seq
    return ctrl.get("action"), seq


def run(source, seconds):
    os.makedirs(INBOX, exist_ok=True)
    control_path = os.path.join(INBOX, "control.json")
    state = load_rotation(source)
    last_seq = 0
    paused = False
    last_advance = 0.0  # 0 forces an immediate first show below

    while True:
        refresh_order(source, state)
        if not state["order"]:
            print(f"[photo_producer] no images in {source}, waiting", flush=True)
            time.sleep(seconds)
            continue

        action, last_seq = read_control(control_path, last_seq)
        advance = False
        if action == "next":
            state["index"] = (state["index"] + 1) % len(state["order"])
            advance = True
        elif action == "prev":
            state["index"] = (state["index"] - 1) % len(state["order"])
            advance = True
        elif action == "pause":
            paused = True
        elif action == "resume":
            paused = False
            advance = True  # show something immediately rather than waiting out the rest of the old interval
        elif not paused and time.time() - last_advance >= seconds:
            state["index"] = (state["index"] + 1) % len(state["order"])
            advance = True

        if advance:
            try:
                show(source, state)
                save_rotation(source, state)
            except OSError as e:
                print(f"[photo_producer] skipping current image: {e}", flush=True)
            last_advance = time.time()

        time.sleep(1)  # fast tick so a prev/next/pause tap feels responsive; actual re-render is gated above


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, help="folder of images to rotate through")
    ap.add_argument("--seconds", type=int, default=300, help="seconds per photo (default 300 = 5min)")
    args = ap.parse_args()
    source = os.path.expanduser(args.source)
    if not os.path.isdir(source):
        raise SystemExit(f"--source {source!r} is not a directory")
    print(f"[photo_producer] rotating {source} every {args.seconds}s -> {INBOX}", flush=True)
    run(source, args.seconds)

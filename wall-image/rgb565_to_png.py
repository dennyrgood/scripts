#!/usr/bin/env python3
"""Convert one or more raw RGB565 frames (as written into inbox/) to PNG for
viewing. RGB565 has no header -- just 800x480 pixels x 2 bytes -- so this
just unpacks it with Pillow. See wall-image/README.md ("Local development /
testing") for the pipeline this reads from.

Usage:
    ./venv/bin/python3 rgb565_to_png.py [FILE.rgb565 ...]

With no arguments, converts every *.rgb565 currently in inbox/fleet/ and
inbox/photos/ and writes each as /tmp/<name>.png.
"""
import sys
import glob
import os
from PIL import Image


def load(path, W=800, H=480):
    data = open(path, "rb").read()
    img = Image.new("RGB", (W, H))
    px = img.load()
    i = 0
    for y in range(H):
        for x in range(W):
            lo, hi = data[i], data[i + 1]
            v = lo | (hi << 8)
            i += 2
            r, g, b = (v >> 11) & 0x1F, (v >> 5) & 0x3F, v & 0x1F
            px[x, y] = (r * 255 // 31, g * 255 // 63, b * 255 // 31)
    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    files = sys.argv[1:] or (
        glob.glob(os.path.join(here, "inbox/fleet/*.rgb565"))
        + glob.glob(os.path.join(here, "inbox/fleet/detail/*.rgb565"))
        + glob.glob(os.path.join(here, "inbox/photos/*.rgb565"))
    )
    if not files:
        print("No .rgb565 files found (and none given on the command line).")
        return
    for f in files:
        out = "/tmp/" + os.path.basename(f).replace(".rgb565", ".png")
        load(f).save(out)
        print(out)


if __name__ == "__main__":
    main()

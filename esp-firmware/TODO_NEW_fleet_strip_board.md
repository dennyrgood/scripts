# NEW PROJECT — under-monitor fleet status strip

Status: prospective purchase, not yet ordered. This file is a planning
brief to start a new session on once the board is in hand (or to start
designing the host-side render function ahead of time).

## The hardware

**Waveshare ESP32-S3 3.49" Touch LCD Dev Board** — $41.27 on Amazon
(waveshare store).
- Display: 172x640 QSPI IPS — a long thin horizontal strip, not a
  normal aspect ratio panel.
- Processor: ESP32-S3R8 dual-core — **native USB** (same chip family as
  `esp-functionkeys`'s board, confirmed capable of USB-HID if ever
  needed, though this project doesn't need HID).
- Interface: **QSPI, not RGB-parallel** — same safety property as every
  other e-ink/SPI board discussed this cycle: does not share the
  RGB-panel-bus/WiFi-contention failure class that caused
  `fleet_wall`/`fleet_wall_compact`'s flicker/reboot problem (see
  `esp-firmware/fleet_wall_image/README.md` for that history).
- Has onboard AI-interaction/offline-voice-control hardware — irrelevant
  to this use case, ignore it.
- No battery — fine, this runs on continuous USB/mains power under a
  monitor anyway.

## The intended use

An always-on, under-monitor mini fleet status display — a glanceable
strip, not a replacement for the full 6x3 grid.

## Architecture to reuse (don't redesign from scratch)

This project is a **new render target on the existing host-render
pipeline**, not a new architecture:

- **Host side (`wall-image/`)**: `fleet_snapshot_producer.py` already
  reads `inbox/fleet/status.json` (written by `fetch_fleet_status.sh`,
  which is the only process allowed to touch the network — see that
  README's section on the macOS Local Network/launchd quirk, do not
  "simplify" that split away) and draws with Pillow. This project needs
  a **new draw function** (e.g. `draw_strip()`) producing a 640x172 (or
  172x640, check orientation) image — NOT a reuse of `draw_grid()`'s 6x3
  tile layout, which doesn't fit this aspect ratio at all. Likely
  candidates for what a strip shows: a single rotating host's name +
  status + key metric, or a compact one-line-per-group summary, or just
  an alert ticker that's blank/calm when everything's up. Design this
  with the user before writing code — the right layout isn't obvious yet.
- **`wall_server.py`** already has a pattern for serving multiple
  "channels" (`/fleet/*`, `/photos/*`, `/display/*` unified endpoint) —
  adding a `/strip/*` channel (or folding this into `/display/*` if the
  board will ever show more than the strip) follows the same dispatch
  style already there. Touch support on this board means tap-to-cycle
  is plausible, same as the existing `/display/tap` zone-based dispatch.
- **Device firmware is new** — this board's QSPI display needs its own
  panel driver/library (different from the RGB-parallel driver in
  `fleet_wall_image/`), but the *behavior* should match: dumb client,
  polls a hash, fetches a raw frame on change, forwards touch (if used),
  CRC32-checks every transfer (see `fleet_wall_image/README.md`'s
  checksumming section — this was added after real corruption-diagnosis
  pain, don't skip it on a new board).

## What to figure out before writing firmware

1. Exact pixel format this panel's driver library expects (RGB565 like
   the others, or something else for QSPI IPS panels this size).
2. Whether to fold this into the existing `wall_server.py`/`/display`
   unified channel model or give it a fully separate endpoint — depends
   on whether this board and the e-ink devices (see "Context" below) are
   meant to show related or independent content.
3. The actual strip layout/content design — not decided yet, discuss
   with the user first.

## Context this session already has, don't re-derive

- Full fleet host list and what's monitored: see root `CLAUDE.md`'s
  "Fleet machine aliases" table and `Status/readme.md`.
- The densify-grid work (`wall-image/TODO_DENSIFY_GRID.md`) is a
  **separate, independent task** on the *existing* 6x3/800x480 grid —
  not part of this project, don't conflate them.
- Two TRMNL 7.5" e-ink kits and one 13.3" Spectra 6 DIY kit (+ one spare
  EE02 driver, bought by accident but kept) are already purchased and in
  hand, destined for fleet-status (TRMNL, replacing the old RGB 7" board
  in that role) and a photo album (13.3"). That's a separate, unrelated
  project — don't fold it into this one.
- The freed-up original RGB 7" board (`fleet_wall_image`, ESP#1) is
  being repurposed as a second `esp-functionkeys`-style macro pad for a
  second Mac, once the TRMNL units take over fleet-status duty — also
  unrelated to this strip project.
- Decision already made: own firmware + the existing host-render
  pipeline, not any vendor's bundled software (TRMNL cloud/BYOS, Seeed
  SenseCraft) — same reasoning applies here even though this board isn't
  from either of those vendors: you already have a working Pillow
  rendering pipeline, there's no reason to adopt new tooling.

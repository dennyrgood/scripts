# TODO — densify the fleet grid rendering

## Context

`fleet_snapshot_producer.py`'s `draw_grid()` (800x480, 6x3 tiles, ~133x131px
each) currently renders a sparse tile: name, ping, ONE bar (CPU if present,
else RAM — never both), and a redundant status word (the left color stripe
already encodes up/down/warn, so the text duplicates it).

Compare against the LCARS web dashboard (`Status/` — the richer HTML/JS
status view, not this ESP32 grid) which shows per-host: RAM bar, CPU bar +
live sparkline, GPU bar, multiple disk volumes, a row of colored service
dots, reboot/OS/Windows-Update timestamps. That view is the aspirational
ceiling — don't try to match it 1:1 (live sparklines don't belong on this
architecture either, see "Out of scope" below), but the current grid tile
has real unused room and is worth tightening independently of any new
hardware purchase (separate conversation, not this file's concern).

## Goal

Tighten `draw_grid()`'s per-tile layout to use the existing 133x131px cell
better, without changing the grid dimensions, canvas size, or the
host/detail-screen split. Purely a rendering density improvement on the
existing 800x480 RGB565 pipeline (`fleet_wall_image` board + `wall_server.py`
+ `fleet_snapshot_producer.py` in this repo).

## Concrete changes (in priority order)

1. **Stack CPU + RAM as two bars**, not one-or-the-other. ~16px of
   additional vertical space needed; cell has room.
2. **Add a compact service-status dot row** — small colored dots (reuse
   `status_color()`), one per entry in `m.get("services", [])`, instead of
   showing nothing. Mirrors the "●Flask/API ●Fleet API" pattern from the
   LCARS dashboard in ~10px of height. Cap at however many dots fit the
   cell width before truncating/overflow-hiding.
3. **Add a GPU bar** (third thin bar) when `minfo` has a GPU percent —
   relevant for ComfyUI hosts (Amsterdam, ChatWorkhorse, ImageBeast,
   TravelBeast all report GPU in the fleet status JSON already).
4. **Drop the redundant bottom status word**, replace with something that
   adds information instead of repeating the stripe color — e.g. a disk
   usage percent/number, or move ping there instead of duplicating it near
   the top.
5. Re-check `draw_detail()` too once the grid tile is denser — right now
   the detail screen (full 800x480 per host) is comparatively sparse next
   to a tightened grid tile; may be worth a pass there too for consistency,
   but that's secondary to #1-4.

## Out of scope for this task

- Live/scrolling sparkline graphs — not a good fit for the 15s poll-driven,
  hash-diffed push model this architecture already uses (see this repo's
  own `wall-image/README.md` on why update cadence is deliberately coarse).
  If sparklines are wanted later, they'd be a static N-sample bar/line
  redrawn each snapshot, not a live-scrolling one.
- Any new hardware (e-ink panels, XIAO boards, etc.) — that's a separate,
  ongoing conversation/purchase thread, not related to this rendering
  cleanup. This file is scoped to the *existing* RGB ESP32-S3 board and
  `wall-image/` pipeline only.
- Grid dimensions / canvas size changes — stay at 6x3 / 800x480.

## Where to work

- `wall-image/fleet_snapshot_producer.py` — `draw_grid()` is the only
  function that needs changes (lines ~114-172 as of 2026-09-30). `draw_detail()`
  is untouched except possibly step 5.
- Test by running the producer against a saved `inbox/fleet/status.json`
  (or a copy of one) and inspecting `inbox/fleet/grid.rgb565` via
  `rgb565_to_png.py` (already in this dir) rather than deploying to the
  physical board first.
- This runs as a LaunchAgent on FleetDev normally — don't restart/touch the
  live LaunchAgent as part of dev iteration; run the script manually against
  a copied status.json and converted PNG until the layout looks right, then
  hand off restarting the LaunchAgent as a separate explicit step.

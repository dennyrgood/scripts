# wall-image — host-rendered display system for fleet_wall_image

The host side of a "dumb pixel client" architecture: the ESP32-S3-Touch-LCD-7
board (`esp-firmware/fleet_wall_image/` — read that project's README for the
device/firmware side) does no rendering of its own. Everything shown on the
physical panel — the fleet status grid, per-host detail screens, and a
rotating photo frame — is drawn here with Pillow and served as raw RGB565
pixels. This exists because on-device LVGL rendering plus WiFi polling
caused a long-running, never-fully-resolved flicker/reboot problem in the
earlier `fleet_wall`/`fleet_wall_compact` projects; moving rendering off the
board was the fix.

Deployed on FleetDev (this Mac, `192.168.178.241`) as four LaunchAgents
(see "Deployment" below) — not run manually. `esp-firmware/fleet_wall_image`
points at `IMAGE_API_HOST=192.168.178.241`, `IMAGE_API_PORT=8099`.

## The four processes

```
fetch_fleet_status.sh  --curl-->  fleet_api.py (Status/)
        |
        v (writes inbox/fleet/status.json)
fleet_snapshot_producer.py  --Pillow-->  inbox/fleet/grid.rgb565, grid.json, detail/*.rgb565

photo_producer.py  --Pillow-->  inbox/photos/current.rgb565
        ^
        | (reads a folder of real photos, picked with --source)

wall_server.py  --HTTP-->  the physical ESP32 board(s)
        (reads whatever's currently in inbox/, serves it, holds gesture state)
```

- **`fetch_fleet_status.sh`** — the ONLY process that touches the network.
  Polls `fleet_api.py`'s `/api/status` (LAN IP, not Tailscale — the ESP32
  has no Tailscale client, and this Mac's own `curl` call needs the same
  reachable address) every `POLL_SECONDS` (default 15s), writes the raw
  JSON to `inbox/fleet/status.json`. **Why a separate bash script and not
  just Python:** see "The macOS Local Network / launchd quirk" below —
  this split exists entirely because of that, not for any architectural
  elegance reason.
- **`fleet_snapshot_producer.py`** — no networking at all. Watches
  `status.json`'s mtime; whenever it changes, draws the grid (6x3 tiles,
  matching `fleet_wall_compact`'s layout) and one detail screen per host
  with Pillow, writes them into `inbox/fleet/`. Also computes and writes
  `grid.json`'s tapmap (tile pixel-rect -> tailscale hostname) — that's
  how `wall_server.py` later knows what a tap on the grid means.
- **`photo_producer.py`** — `--source <folder> --seconds <N>`. Shuffles
  and rotates through every image in that folder (a plain folder of
  JPG/PNG/etc — not a `.photoslibrary` package), letterboxing each one to
  800x480 (scales to fit, pads with black — does NOT crop, so portrait
  photos don't lose their top/bottom). Checks `inbox/photos/control.json`
  once a second for a prev/next/pause/resume command from a device tap
  (written by `wall_server.py`), otherwise auto-advances on its own timer.
  State (shuffle order, current index) persists to a hidden
  `.rotation_state` file inside the **source** folder, not here.
- **`wall_server.py`** — stdlib only, no Pillow, no venv needed. A small
  HTTP daemon (default port 8099) that:
  - Serves `/fleet/frame.hash` `/fleet/frame.rgb565`, `/photos/frame.hash`
    `/photos/frame.rgb565` — the two channels directly, for a board
    dedicated to just one.
  - Serves `/display/frame.hash` `/display/frame.rgb565` `/display/tap` —
    the unified endpoint a normal device actually polls. Holds which
    channel is "active" and dispatches `POST /display/tap {x,y}` by zone:
    - Bottom-right corner (110x70px, either channel) → switch fleet/photos
    - Fleet, elsewhere → tapmap hit-test (tile → that host's detail;
      any tap while already showing a detail screen → back to grid; also
      auto-returns to the grid after 120s with no tap)
    - Photos, left third → prev; right third → next; middle → toggle
      pause/resume (writes `inbox/photos/control.json` for
      `photo_producer.py` to pick up)
  - Renders NOTHING itself — only reads whatever the two producers have
    already written to `inbox/`, via a 1s poll loop watching file mtimes.

The device (firmware) only ever calls `/display/*`. It has no idea what
channel is active, what a tapmap is, or what "photos" even means — it just
polls one hash, fetches on change, and forwards raw touch coordinates.

## Every transfer is checksummed

The firmware computes a CRC32 over every downloaded frame and logs whether
it matched what the server thinks it sent. This was added specifically to
rule data corruption in or out as the cause of a display glitch — see
`fleet_wall_image_spike`'s README for the investigation that motivated it.
If the panel ever looks wrong, check the firmware's serial log for
`CRC BAD` before suspecting this host side.

## The macOS Local Network / launchd quirk (important — don't "simplify" this)

Confirmed 2026-09-22, cost significant debugging time: a `launchd`-spawned
process's outbound connection to a LAN address (this Mac's own local
network, e.g. `192.168.178.158`) can fail with `EHOSTUNREACH`
("No route to host") **even though the kernel routing table has exactly
one valid route and the identical code works fine run interactively from
Terminal.** Ruled out: routing table (only one default route, via the
correct interface), Tailscale (identical failure with `tailscale down`).

The actual mechanism: macOS's Local Network permission for a `launchd` job
is gated on the **immediate parent** of whatever process actually opens
the socket — not the top-level `launchd`-spawned process, and not the
`ProgramArguments[0]` binary's own trustworthiness in isolation:
- `curl` (Apple-signed) succeeds when its **direct** parent is `bash`
  (also Apple-signed, and the direct `launchd` child).
- `curl` FAILS when its direct parent is an unsigned Homebrew `python3` —
  even when that `python3` was itself spawned by a trusted `bash` further
  up the chain. The trust doesn't inherit past one hop.
- Using `exec` inside the bash wrapper doesn't help — `exec` replaces the
  process image, so the "process" becomes `python3` again and loses
  whatever protection the bash identity provided.

**The fix, and why the architecture looks the way it does above:** only
`fetch_fleet_status.sh` (a bash script, `curl`'s direct parent) touches the
network. `fleet_snapshot_producer.py` only ever reads a local file. Do not
"simplify" this back into one Python script that fetches directly — it
will silently fail under `launchd` while appearing to work fine when you
test it by running it yourself in Terminal, which is exactly the trap that
cost hours here.

## Deployment (LaunchAgents on FleetDev)

Four `~/Library/LaunchAgents/com.dennis.wall-*.plist`, all `RunAtLoad` +
`KeepAlive` (reboot-safe, restart-on-crash), managed like any other
`com.dennis.*` agent via the repo's `launchmgr` tool
(`launchmgr status`, `launchmgr logs wall-server`, `launchmgr kick
wall-fleet-fetcher`, etc.):

| Label | Runs | Needs |
|---|---|---|
| `com.dennis.wall-server` | `wall_server.py` | system `/usr/bin/python3` (stdlib only) |
| `com.dennis.wall-fleet-fetcher` | `fetch_fleet_status.sh` | `/bin/bash` directly — see the quirk above |
| `com.dennis.wall-fleet-producer` | `fleet_snapshot_producer.py` | `venv/bin/python3` (Pillow) |
| `com.dennis.wall-photo-producer` | `photo_producer.py --source <folder> --seconds <N>` | `venv/bin/python3` (Pillow) |

**The photo source folder and interval are settings, but there is no
config file for them** — they're hardcoded as `ProgramArguments` in
`com.dennis.wall-photo-producer.plist`. To change either: edit that plist,
then `launchctl unload`/`load` it (or `launchmgr kick wall-photo-producer`
after editing). Deployment state (which LaunchAgents exist, their plist
contents) is captured separately into the `fleet-configs` repo by
`FleetDev/fleetdev-snapshot-fleet-configs.sh` — run that (and
`sync-this`/`git push` in `fleet-configs`) after changing any of these
plists, or the fleet-configs snapshot goes stale.

## Local development / testing

```
python3 -m venv venv && ./venv/bin/pip install pillow   # if venv/ doesn't exist yet
./venv/bin/python3 fleet_snapshot_producer.py            # needs fetch_fleet_status.sh running too, for status.json
./venv/bin/python3 photo_producer.py --source ~/some/folder --seconds 30
python3 wall_server.py                                    # stdlib only, plain python3 is fine
```

To inspect what's actually being shown without a physical board, convert
`inbox/{fleet,photos}/*.rgb565` to viewable PNGs with `rgb565_to_png.py`:
```
./venv/bin/python3 rgb565_to_png.py            # converts everything currently in inbox/ to /tmp/*.png
./venv/bin/python3 rgb565_to_png.py FILE.rgb565  # convert just one file
```
`inbox/` is gitignored (regenerated output, rewritten every poll — not
source) and Finder can't preview `.rgb565` files directly, which is
expected, not a bug.

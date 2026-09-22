# FLEET_WALL_IMAGE — host-rendered display for the ESP32-S3-Touch-LCD-7

A dumb pixel client. Unlike `fleet_wall`/`fleet_wall_compact` (which render
tiles on-device with LVGL) and `fleet_wall_image_spike` (a diagnostic
predecessor to this firmware, kept for its test pattern and stability
history), this firmware has **no LVGL, no JSON parsing, no rendering logic
at all**. It polls a hash, fetches raw RGB565 pixels on change, blits them,
and forwards raw touch coordinates. All intelligence — what to show, what a
tap means — lives on the host, in the sibling `wall-image/` project at the
repo root (**not** under `esp-firmware/`). Read that project's own
`README.md` first; this file only covers the firmware side.

Live and stable as of 2026-09-22 on the physical board (ESP#1, the same
board that ran `fleet_wall_compact`).

## Why this exists (history)

`fleet_wall`/`fleet_wall_compact`'s LVGL rendering plus WiFi polling on the
same board caused a long-running, never-fully-resolved flicker/reboot
problem (see those projects' own READMEs). The idea tested here: move all
rendering to the host, make the device idle almost all the time holding a
static framebuffer. `fleet_wall_image_spike` proved the concept works (see
its README) before this became the real firmware.

## WALL_CHANNEL — which URL prefix this board polls

Set in `fleet_wall_image_secrets.h` (gitignored, copy from the `.example`):
- `"/display"` — **normal choice.** One unified endpoint; the host decides
  what's showing (fleet grid, a host's detail screen, or a photo) and what
  a tap does. See `wall-image/wall_server.py`'s docstring for the gesture
  zones (corner = switch fleet/photos, thirds = prev/pause/next on photos,
  tile = detail on fleet).
- `"/fleet"` / `"/photos"` — a board permanently dedicated to just one,
  no switch gesture. Only useful if you have a second physical board.

## Known issues / architecture notes

- **RGB panel "screen drift"**: the ESP32-S3's RGB LCD peripheral
  continuously DMAs pixels from PSRAM; if something else contends for that
  memory bus (WiFi activity, a big write) badly enough, the panel can lose
  sync and show a vertically-shifted/wrapped frame that does NOT self-heal.
  Mitigations in place, cheapest-to-most-expensive:
  1. `WiFi.setSleep(false)` — modem-sleep power-cycling was a major
     contributor (confirmed by A/B testing on `fleet_wall_compact`).
  2. `esp_lcd_rgb_panel_restart()` called every poll cycle — re-syncs the
     panel; doesn't prevent a glitch but stops it from persisting for
     hours.
  3. **Whole frame staged in PSRAM (`frame_buf`) before ONE `drawBitmap()`
     call**, rather than blitting 8-line strips as they arrive over the
     network. The earlier strip-as-you-download approach left the live,
     actively-scanned display buffer partially rewritten for the entire
     ~2-4s download — `drawBitmap()` on this RGB bus is a synchronous
     `memcpy` straight into the buffer being scanned out, with no vsync-
     synced swap, so that multi-second exposure window made tearing close
     to guaranteed, not occasional. Staging first cuts it to roughly one
     768,000-byte memcpy (well under 100ms).
  4. **Not yet done, the actually-correct fix**: real double buffering
     (write into a hidden buffer, atomic swap at vsync) — what LVGL's
     adapter did for `fleet_wall`/`fleet_wall_compact`. Staging (#3) is the
     cheap version of this, not the complete one. If drift is still
     bothering you often, this is the next thing to try, not another
     tweak to #1-3.
- **Touch is edge-triggered.** A held physical press stays "pressed" for
  many loop iterations; the code fires only on the down-edge (see
  `touch_was_pressed` in the `.ino`). An earlier version without this
  sent the same tap 2-6 times.
- **Touch is checked independently of the network poll**, every ~50ms, not
  once per 15s poll cycle. An earlier version gated both behind the same
  `delay(POLL_MS)`, so a tap had roughly a 1-in-15-seconds chance of
  landing in the instant touch was actually sampled.
- **Self-heal watchdog**: if no successful poll completes for
  `STALL_RESTART_MS` (180s), the board reboots itself. Confirmed necessary
  2026-09-17/21: `HTTPClient::GET()` can wedge on a half-open socket with
  zero error output, and the board can sit frozen (screen unchanged, no
  crash) for over an hour with nothing to indicate why.

## Build setup, flashing

Same as `fleet_wall_compact` — see that project's README for the full
`arduino-cli`/library install steps (Homebrew, board core, Waveshare's
bundled libraries into `~/Documents/Arduino/libraries`). This project
reuses the identical `esp_panel_board_custom_conf.h` (verified pin/panel
config, don't hand-edit) but does NOT use `esp_lv_adapter_arduino.{h,cpp}`
or LVGL at all.

```
cp fleet_wall_image_secrets.h.example fleet_wall_image_secrets.h
# fill in WiFi + IMAGE_API_HOST (the Mac running wall_server.py, LAN IP
# not a Tailscale hostname -- the ESP32 has no Tailscale client) + WALL_CHANNEL
arduino-cli compile --upload -p /dev/cu.usbmodemXXXXXXXXXXXX \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB" .
```

Bootloader mode before every flash: hold **BOOT**, tap **RESET**, release
**RESET**, then release **BOOT** — though auto-reset via the UART1
connector usually works without it.

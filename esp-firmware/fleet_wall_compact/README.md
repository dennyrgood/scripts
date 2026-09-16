# FLEET_WALL_COMPACT — ESP32-S3-Touch-LCD-7 fleet status display (consolidated layout)

Fork of `fleet_wall` with the same WiFi/JSON backend, but a dense, non-paginated
6-column x 3-row grid (18 tiles) instead of the original's paginated 4x2 tiles —
the whole fleet fits on one screen. Each tile shows host name, ping, one stat
bar (CPU or MEM, whichever's available), and a heart/up-down status line.
Tap any tile for the full detail overlay (same as `fleet_wall`).

Live and flashed on the physical board as of 2026-09-17 (macOS, via `arduino-cli`,
`esp32:esp32` core 3.3.11) — no flicker/reboot observed in initial testing.
Note: an earlier attempt at a wider (24-tile) grid with more widgets per tile
crashed on boot (`Guru Meditation StoreProhibited` in `lv_obj_class_create_obj`)
because it exceeded LVGL's 64KB `LV_MEM_SIZE` pool, which doesn't null-check its
own allocations. Fixed by cutting each tile down to 5 LVGL objects (no stripe
child, no wrapper rows — the status color is the card's own left border, and
the stat/health lines are single labels) and dropping to 18 tiles.

## Build setup (from a clean macOS machine)

1. **Homebrew**, if not already installed: https://brew.sh
2. **arduino-cli**:
   ```
   brew install arduino-cli
   ```
3. **7-Zip** (needed to extract the LVGL library archive in step 6):
   ```
   brew install sevenzip
   ```
4. Board core:
   ```
   arduino-cli config init
   arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   arduino-cli core update-index
   arduino-cli core install esp32:esp32
   ```
5. Library: `arduino-cli lib install ArduinoJson`
6. Clone Waveshare's official demo repo and copy its bundled libraries into your
   sketchbook's `libraries/` dir. On macOS this is `~/Documents/Arduino/libraries`
   — **not** `~/Arduino/libraries`; arduino-cli won't find libraries in the wrong
   one and will fail with a confusing "file not found" on `esp_display_panel.hpp`.
   ```
   git clone --depth 1 https://github.com/waveshareteam/ESP32-S3-Touch-LCD-7
   cp -r ESP32-S3-Touch-LCD-7/examples/Arduino/libraries/{esp-lib-utils,ESP32_Display_Panel,ESP32_IO_Expander} \
       ~/Documents/Arduino/libraries/
   cp ESP32-S3-Touch-LCD-7/examples/Arduino/libraries/LVGL_v9.5.0.7z ~/Documents/Arduino/libraries/
   cd ~/Documents/Arduino/libraries
   7zz x LVGL_v9.5.0.7z    # produces lvgl/ and lv_conf.h as siblings in this dir
   rm LVGL_v9.5.0.7z LVGL_v8.4.0.7z   # the v8 archive extracts too; not needed
   ```
7. This sketch's `esp_panel_board_custom_conf.h` and `esp_lv_adapter_arduino.{h,cpp}`
   are copied verbatim from Waveshare's `examples/Arduino/examples/10_lvgl_v9_demo`
   — the exact, verified pin/panel config for this board. Don't hand-edit the pin
   macros in `esp_panel_board_custom_conf.h`.

## Before flashing

1. **Credentials** — copy `fleet_wall_secrets.h.example` to `fleet_wall_secrets.h`
   (gitignored, never committed) and fill in your real WiFi SSID/password:
   ```
   cp fleet_wall_secrets.h.example fleet_wall_secrets.h
   ```
2. Edit these constants at the top of `fleet_wall_compact.ino`:
   - `FLEET_API_HOST` — box running `Status/fleet_api.py`, given as a **LAN IP**,
     not a Tailscale hostname (the ESP32 has no Tailscale client, so it can't
     resolve or route to a Tailscale-only address — confirmed 2026-09-15,
     `amsterdamdesktop` failed to connect until swapped for its LAN IP).
   - `POLL_INTERVAL_MS`

## Find the board's serial port

Plug the board into USB (either port on this model works; it enumerates as a
native `usbmodem` device, not through a USB-serial chip driver), then:
```
ls /dev/cu.*
```
Look for something like `/dev/cu.usbmodemXXXXXXXXXXXX` — that's the `-p`
argument for the compile/upload command below. It changes per-cable/per-port,
so re-check if you move the cable.

## Putting the board in bootloader mode

Before every flash: hold **BOOT**, tap **RESET**, release **RESET**, then
release **BOOT**. The board's own onboard ↻ reset button (added in firmware,
see below) does a software reboot, not a bootloader-mode entry — it won't
help you get into flashing mode.

## Compile + flash

```
./flash-compact.sh
```

Auto-detects the board's `/dev/cu.usbmodem*` port, checks that
`fleet_wall_secrets.h` exists, prompts you to enter bootloader mode, then
compiles and uploads. Pass a port explicitly if you have more than one
`usbmodem` device connected: `./flash-compact.sh /dev/cu.usbmodemXXXXXXXXXXXX`.

To just compile without flashing (e.g. to check for errors after an edit):
```
arduino-cli compile --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB" .
```

Flash/PSRAM options match what `esptool` read back from the actual board
(16MB flash, 8MB Octal PSRAM).

## Known issues

- The original `fleet_wall`'s intermittent flicker/reboot (see its own
  README) has not reappeared in this build's initial testing (2026-09-17),
  but it hasn't run long enough yet to call that conclusive. The manual
  reset button (↻ icon, top-right of the header) is still in place as a
  same-process workaround if it shows up.
- **LVGL memory ceiling**: `LV_MEM_SIZE` is a shared 64KB pool
  (`~/Documents/Arduino/libraries/lv_conf.h`, not in this repo) and
  `lv_obj_create()` doesn't null-check its own allocation, so exceeding it
  crashes on boot rather than failing loudly. Each tile is deliberately kept
  to 5 LVGL objects for this reason — see the note at the top of this file.
  Don't add more tiles (`GRID_COLS`/`GRID_ROWS`) or widgets per tile without
  checking the pool still fits.

# FLEET_WALL — ESP32-S3-Touch-LCD-7 fleet status display

Live and flashed on the physical board as of 2026-09-16 (macOS, via `arduino-cli`,
`esp32:esp32` core 3.3.11) — tap-to-detail works, CPU/MEM/disk data pulls from
`fleet_api.py`'s `machine_info` block. Known open issue: intermittent
display flicker/reboot every ~20+ minutes that self-recovers; a manual
reset button (top-right ↻ icon) works around it in the meantime — see
"Known issues" below.

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
2. Edit these constants at the top of `fleet_wall.ino`:
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
arduino-cli compile --upload -p /dev/cu.usbmodemXXXXXXXXXXXX \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB" \
  fleet_wall
```

Flash/PSRAM options match what `esptool` read back from the actual board
(16MB flash, 8MB Octal PSRAM). Drop `--upload -p ...` to just compile without
flashing.

## Known issues

- **Intermittent flicker/reboot**: after running cleanly for a while (seen
  anywhere from ~2 minutes to 20+ minutes), the display can start ghosting/
  flickering, sometimes followed by a full auto-reboot that then runs clean
  again. Root cause not fully isolated as of 2026-09-16. Ruled out or
  mitigated so far:
  - RGB LCD bounce buffer size (doubled from Waveshare's stock example, per
    their troubleshooting doc) — helped but didn't eliminate it.
  - Networking moved off the render core entirely, onto its own FreeRTOS
    task — helped but didn't eliminate it.
  - Networking task stack size (was too small once `/api/status` grew to
    include `machine_info`, causing a stack-overflow crash-and-reboot loop;
    fixed by raising to 20KB) — this specific crash mode is resolved.
  - Not yet tried: Waveshare's "high_perf" XIP-on-PSRAM SDK swap. Checked
    2026-09-16 — that repo's builds only go up to arduino-esp32 core 3.2.0,
    but this project is on 3.3.11, so using it means either downgrading the
    whole toolchain or building a custom SDK from source via ESP-IDF. Not
    attempted given the size of that undertaking relative to the payoff.
  - **Workaround in place**: a manual reset button (↻ icon, top-right of the
    header) does a clean software reboot (`ESP.restart()`) without needing
    the physical BOOT/RESET button sequence.

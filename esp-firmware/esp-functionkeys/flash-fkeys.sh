#!/usr/bin/env bash
# flash-fkeys.sh — compile and upload esp-functionkeys to the ESP32-S3-Touch-LCD-7.
# Usage: ./flash-fkeys.sh [/dev/cu.usbmodemXXXX]
# If no port is given, auto-detects the first /dev/cu.usbmodem* device.
#
# FQBN includes USBMode=default (USB-OTG/TinyUSB) -- required for the HID
# keyboard to work at all; the board's other sketches (fleet_wall, esp-test)
# use the default Hardware-CDC-and-JTAG mode instead, so don't reuse this
# FQBN for those. CDCOnBoot=cdc keeps Serial console debugging working
# alongside HID as one composite USB device.
set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-}"
if [ -z "$PORT" ]; then
  PORT=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)
  if [ -z "$PORT" ]; then
    echo "No /dev/cu.usbmodem* device found."
    echo "Plug in the board (either USB port works on this model) and try again,"
    echo "or pass the port explicitly: ./flash-fkeys.sh /dev/cu.usbmodemXXXXXXXXXXXX"
    exit 1
  fi
fi

echo "Using port: $PORT"
echo "Put the board in bootloader mode now: hold BOOT, tap RESET, release RESET, then release BOOT."
read -r -p "Press Enter once ready... " _

arduino-cli compile --upload -p "$PORT" \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB,USBMode=default,CDCOnBoot=cdc" \
  .

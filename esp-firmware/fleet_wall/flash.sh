#!/usr/bin/env bash
# flash.sh — compile and upload fleet_wall to the ESP32-S3-Touch-LCD-7.
# Usage: ./flash.sh [/dev/cu.usbmodemXXXX]
# If no port is given, auto-detects the first /dev/cu.usbmodem* device.
set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-}"
if [ -z "$PORT" ]; then
  PORT=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)
  if [ -z "$PORT" ]; then
    echo "No /dev/cu.usbmodem* device found."
    echo "Plug in the board (either USB port works on this model) and try again,"
    echo "or pass the port explicitly: ./flash.sh /dev/cu.usbmodemXXXXXXXXXXXX"
    exit 1
  fi
fi

if [ ! -f fleet_wall_secrets.h ]; then
  echo "fleet_wall_secrets.h is missing -- copy fleet_wall_secrets.h.example to"
  echo "fleet_wall_secrets.h and fill in your real WiFi SSID/password first."
  exit 1
fi

echo "Using port: $PORT"
echo "Put the board in bootloader mode now: hold BOOT, tap RESET, release RESET, then release BOOT."
read -r -p "Press Enter once ready... " _

arduino-cli compile --upload -p "$PORT" \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB" \
  .

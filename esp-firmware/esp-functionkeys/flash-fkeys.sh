#!/usr/bin/env bash
# flash-fkeys.sh -- compile and upload esp-functionkeys to ESP#2
# (Waveshare ESP32-S3-Touch-LCD-7).
# Usage: ./flash-fkeys.sh [/dev/cu.usbmodemXXXX]
#
# Flashes ONLY through the UART1 connector (USB-serial chip, auto-reset
# works, no BOOT/RESET needed). The native USB connector is the keyboard
# port: it disappears/re-enumerates during a reset, so uploads there fail.
# Cycle: cable in UART1 -> flash -> move cable to USB to use it as a keyboard.
#
# FQBN includes USBMode=default (USB-OTG/TinyUSB) -- required for the HID
# keyboard to work at all; the board's other sketches (fleet_wall, esp-test)
# use the default Hardware-CDC-and-JTAG mode instead, so don't reuse this
# FQBN for those. CDCOnBoot=cdc keeps Serial console debugging working
# alongside HID as one composite USB device.
set -euo pipefail
cd "$(dirname "$0")"

UART1_PORT=/dev/cu.usbmodem5B5E0664711   # flash here
USB_PORT=/dev/cu.usbmodem1CDBD443C58C2   # keyboard mode, never flash here
OTHER_BOARD=/dev/cu.usbmodem5B5E0656511  # fleet wall -- never flash

PORT="${1:-$UART1_PORT}"

if [ "$PORT" = "$OTHER_BOARD" ]; then
  echo "Refusing: $PORT is the other board (fleet wall)."
  exit 1
fi
if [ "$PORT" = "$USB_PORT" ]; then
  echo "Refusing: $PORT is the native USB (keyboard) connector."
  echo "Move the cable to UART1 and run again."
  exit 1
fi
if [ ! -e "$PORT" ]; then
  echo "Port not found: $PORT"
  echo "Cable must be in the UART1 connector. Ports present now:"
  ls /dev/cu.usbmodem* 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "Flashing via UART1: $PORT"

if ! arduino-cli compile --upload -p "$PORT" \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB,USBMode=default,CDCOnBoot=cdc" \
  .; then
  echo "Flash failed. If it could not connect: hold BOOT, tap RESET,"
  echo "release BOOT, then run this again."
  exit 1
fi

echo "Done. Move the cable to the USB connector to use it as a keyboard."

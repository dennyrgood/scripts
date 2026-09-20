# esp-functionkeys

Touchscreen macro pad on a Waveshare ESP32-S3-Touch-LCD-7 (800x480).
Tapping a cell sends a real USB HID keystroke to the Mac. It replaces
and augments the user's physical Surface Dial + extended-F-key setup.

## What the grid means
- Column = F-key: F6..F12 (FKEY_CODES[] is in that order).
- Row = modifier layer, top to bottom: Ctrl+Shift, Ctrl, Shift, Plain.
  ROW_CTRL[] / ROW_SHIFT[] give the modifiers per row.
- Every cell is exactly one keystroke: the row's modifiers + the
  column's F-key. Blank cells (line_count 0) are unlabeled (same full
  color, not dimmed) but STILL send their keystroke, so bindings can be added in Hammerspoon
  without touching the firmware.
- The grid mirrors the user's Hammerspoon bindings (posCtrlShift /
  posCtrl / posShift / posPlain tables in ~/.hammerspoon/init.lua).
  The action words are short labels for what Hammerspoon does on that
  key. To know what a label really does, read the secret-free copy
  ~/.hammerspoon/init.lua.safe. NEVER read init.lua or the
  init.lua-* backups (real secrets; also denied in settings.json).
  That includes grep/cat/sed via Bash, not just the Read tool.
- The physical printed key strip above the real keys shows the same
  layout. Column colors here are chosen to match that strip.

## Where things live (esp-functionkeys.ino)
- GRID[row][col]: CellSpec {lines[2], line_count, cyc}.
  - lines: up to 2 lines of label text.
  - cyc: display-only. Shows a small "(cyc)" tag under the label.
    It does not change the keystroke. Set on Term, Firefox, Jump,
    Finder (and means "cycles" in the user's Hammerspoon setup).
- COL_FILL_HEX[] / COL_DARK_TEXT[]: per-column fill color and whether
  text is black (true) or white (false). Change these to recolor.
- MOD_TAG[]: small modifier text in each cell's corner ("^Sh", "^",
  "Sh"). Text, not symbols: LV_SYMBOL_UP and "^" looked identical.
- Cell layout: label top-left (Montserrat 20), F-key + modifier tag
  bottom-right (Montserrat 14). Empty cells use the same column color
  as labeled ones (no dimming). Pressed state = lighter fill + white border + glow.
- send_keystroke(): the HID call, fires on release only.

## Common tasks (how requests usually go)
Every change follows: edit .ino -> compile-check -> flash -> user
looks at the panel (often sends a photo) -> adjust -> repeat.
- Recolor a column: edit that column's entry in COL_FILL_HEX[] and
  set COL_DARK_TEXT[] (true = black text, false = white). Hex codes
  from the user are used as given, e.g. "#22c55e" -> 0x22C55E. If a
  color looks off, adjust and reflash rather than debating it.
- Change a label: edit the string in GRID[row][col]. Keep it short.
  Use 2 lines only where line_count is 2 (see "open"/"Iterm").
- Add or remove the "(cyc)" tag: flip that cell's cyc flag.
- Move or restyle text (alignment, font, corner tags): the cell is
  built in build_ui(). Label position is lv_obj_align on `content`.
- Change what a key ACTUALLY does: NOT done here. This firmware only
  sends F-key + the row's modifiers. The action happens in the user's
  Hammerspoon config. To change behavior, change the label to match
  the Hammerspoon binding, or tell the user Hammerspoon must change.
- Change which keystroke a cell sends: only by moving it to a
  different row/column, since position defines the keystroke.
- Add rows/columns: change N_ROWS / N_COLS and every per-row/per-col
  array (FKEYS, FKEY_CODES, ROW_CTRL, ROW_SHIFT, MOD_TAG, GRID,
  COL_FILL_HEX, COL_DARK_TEXT). The compiler won't catch a short array.
- Flash: see Flashing below. After flashing the user moves the cable
  to the USB port to test keystrokes; moving it power-cycles the
  board, which is normal.
- Testing HID: the user taps a cell and watches the Mac. Claude
  can't observe keystrokes, so ask what happened if it matters.

## Working style
- Small visual tweaks are the norm: colors, labels, mappings.
- Do not commit or push unless the user says "commit" or "push".
- Never ask the user whether they want to stop. Just do the next thing.
- The user picks colors by eye on the real panel, which renders more
  yellow than a monitor. Expect several rounds; reflash each time.
- Hammerspoon's init.lua contains real secrets (a GitHub token and
  passwords). Never print, quote or copy them anywhere. Labels stay
  as the short names already used (pat, ug, live, email).
- Keep labels short. Long words like "Terminal" clip the cell border
  (that's why it is "Term").
- Fonts: only Montserrat 14 and 20 are enabled and used. Other sizes
  need lv_conf.h changes in ~/Documents/Arduino/libraries.
- After a change, compile-check before flashing.

## The two USB connectors (flash vs run) -- read this first
The board has two USB-C connectors and they do different jobs:
- UART1 = flashing. A USB-serial chip sits behind it, so uploads and
  auto-reset work. Port: /dev/cu.usbmodem5B5E0664711.
  The screen runs from here, but the Mac does NOT see a keyboard.
- USB = running as a keyboard. This is the ESP32-S3's native USB, the
  only connector where HID works. Port: /dev/cu.usbmodem1CDBD443C58C2.
  Do not try to flash from here; auto-reset is unreliable on it.
Cycle for every change:
  1. Cable in UART1 -> flash.
  2. Move cable to USB -> the board power-cycles (normal) and boots as
     a keyboard. Test taps.
  3. To change anything again, move the cable back to UART1 first.
The keyboard never works from UART1, even though the screen does.
If the screen works but the Mac gets no keystrokes, check the cable
is in USB, not UART1, before suspecting the firmware. (Native USB is
also shared with a CAN interface; the firmware sets EXIO5 low so USB
wins. Never remove that.)
Which port shows up in `ls /dev/cu.usbmodem*` tells you which
connector is currently in use.

## Flashing
- Board is "ESP#2". Check ports with: ls /dev/cu.usbmodem*
- Flash with the cable in the UART1 connector.
  Port: /dev/cu.usbmodem5B5E0664711
  Usually no button presses are needed (auto-reset works there). If a
  flash fails to connect, ask the user to hold BOOT, tap RESET.
- Then the user moves the cable to the USB connector to use it as a
  keyboard. Port there: /dev/cu.usbmodem1CDBD443C58C2
- Command (from this directory):
  arduino-cli compile --upload -p /dev/cu.usbmodem5B5E0664711 \
    --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB,USBMode=default,CDCOnBoot=cdc" .
  (./flash-fkeys.sh does the same: it defaults to the UART1 port, has
  no BOOT/RESET prompt, and refuses the USB and other-board ports.)
- Never flash /dev/cu.usbmodem5B5E0656511. That is the other board
  (fleet wall, fleet_wall_compact).
- Do not edit esp_panel_board_custom_conf.h. It drives EXIO5 low to
  enable native USB. Without it the keyboard never enumerates.
- HID has only been tested for a short time. The physical keyboard
  stays the reliable primary; this is a convenience layer.

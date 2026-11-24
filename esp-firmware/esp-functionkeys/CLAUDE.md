# esp-functionkeys

Touchscreen macro pad on a Waveshare ESP32-S3-Touch-LCD-7 (800x480).
Tapping a cell sends a real USB HID keystroke to the Mac. It replaces
and augments the user's physical Surface Dial + extended-F-key setup.

## The F-key layout (redone 2026-11-24)
F-keys are split by where they live. Hammerspoon (~/.hammerspoon/init.lua,
`fkeyMap`) and Rectangle Pro do the actions; this firmware only sends keys.
- F1-F7  = THIS PAD, layout 0 (default). FKEY_CODES[0][] is F1..F7.
- F8-F12 = laptop keyboard only (not on the pad). F8 Firefox, F10 Jump
  (cycle / Shift = list), F12 = pat/ug/live/email. F9, F11 unbound.
- F13-F19 = extended keyboard (window management in Rectangle Pro, see
  "Rectangle Pro and F13-F19" below) AND pad layout 1: medium-hold the
  top-left cell to switch the pad to a second layout that sends F13-F19
  (FKEY_CODES[1][]) with its own labels and colors (blue F13-F15, teal
  F16-F19). See "Layouts and hold tiers".

Pad cells (Hammerspoon actions; blank = no label but still sends the key):
| Col | Plain | Shift | Ctrl | Ctrl+Shift |
|---|---|---|---|---|
| F1 | Area | Delay | | |
| F2 | Full | Scroll | | |
| F3 | Term (cyc) | new | | |
| F4 | iTerm (cyc) | new iTerm | | |
| F5 | Finder (cyc) | new | open iTerm @folder | |
| F6 | Max (toggle) | Min | Restore (un-minimize) | |
| F7 | Move | Tear | Jump | Jump (list) |

Pad layout 1 (F13-F19; labels in GRID[1]; Rectangle Pro does the work):
| Row | F13 | F14 | F15 | F16 | F17 | F18 | F19 |
|---|---|---|---|---|---|---|---|
| Ctrl+Shift | Snap Left | Snap Up | Snap Right | Snap TL | Snap TR | Snap BL | Snap BR |
| Ctrl | 6th TL | 6th TC | 6th TR | 8th TL | 8th TCL | 8th TCR | 8th TR |
| Shift | 6th BL | 6th BC | 6th BR | 8th BL | 8th BCL | 8th BCR | 8th BR |
| Plain | 1/3 | 2/3 | 3/3 | 1/4 TL | 1/4 TR | 1/4 BL | 1/4 BR |
(T/B = top/bottom, L/C/R = left/center/right, TCL/TCR = center-left/right.
Plain F13-F19 go through Hammerspoon's rectFwd -> ctrl+opt+D/F/G, U/I/J/K.)

## Option swap (Hammerspoon, 2026-11-24)
Holding the Mac keyboard's Option key swaps the two ranges for any key
source (the ESP cannot see the Mac's Option state, so this lives in
~/.hammerspoon/init.lua, "OPTION SWAP" block): Opt+F1-F7 acts like
F13-F19, Opt+F13-F19 acts like F1-F7. Not swapped: F8-F12. Opt+F1-F7 plain
runs the ctrl+opt forward; with Shift/Ctrl/Ctrl+Shift it posts a synthetic
F13-F19 with that modifier for Rectangle Pro. Checked no conflict: no
enabled macOS symbolic hotkey and no Rectangle Pro shortcut uses Option on
these keys.

## Layouts and hold tiers (added 2026-11-24)
Top-left cell (THEME_TOGGLE_ROW/COL = Ctrl+Shift F1 / F13), by hold time:
- under LAYOUT_TOGGLE_MS (600 ms): normal tap, sends its keystroke on release.
- 600 ms up to THEME_TOGGLE_MS (2000 ms): switches layout 0 <-> 1, sends nothing.
- 2000 ms or more: next theme + reboot, sends nothing (as before).
The cell border turns yellow at the layout tier and red at the theme tier
while the finger is still down (hold_feedback()). The layout switch rebuilds
the screen via lv_async_call (never from inside the touch callback, since
lv_obj_clean() deletes the cell that is handling the event). The layout is
kept in NVS key "layout" ONLY across the theme-change reboot (setup() reads
and erases it); any other boot, including moving the cable, starts in layout 0.
Per-layout arrays: FKEYS, FKEY_CODES, GRID, COL_FILL_HEX, COL_DARK_TEXT are
all indexed [g_layout]. A third layout = bump LAYOUT_COUNT and add an entry
to each of those five.

## What the grid means
- Column = F-key: F1..F7 (layout 0) or F13..F19 (layout 1).
- Row = modifier layer, top to bottom: Ctrl+Shift, Ctrl, Shift, Plain.
  ROW_CTRL[] / ROW_SHIFT[] give the modifiers per row.
- Every cell is exactly one keystroke: the row's modifiers + the
  column's F-key. Blank cells (line_count 0) are unlabeled (same full
  color, not dimmed) but STILL send their keystroke, so bindings can be added in Hammerspoon
  without touching the firmware.
- The grid mirrors the user's Hammerspoon bindings (fkeyMap in
  ~/.hammerspoon/init.lua, built from the posCtrlShift / posCtrl /
  posShift / posPlain action tables).
  The action words are short labels for what Hammerspoon does on that
  key. To know what a label really does, read ~/.hammerspoon/init.lua.
  As of 2026-11-19 it no longer contains secrets: typeSecret() reads
  them from the macOS Keychain at keypress (service "hs-<name>").
  Older init.lua-* / init.lua.bak* backups may still hold real secrets,
  so don't read those.
- Column colors: amber F1-F2 (capture), green F3-F5 (apps), purple F6-F7
  (window). They do NOT necessarily match the old printed key strip.

## Rectangle Pro and F13-F19 (extended keyboard)
Hammerspoon forwards ONLY plain F13-F19 (the `rectFwd` table):
F13/F14/F15 -> ctrl+opt+D/F/G (thirds), F16-F19 -> ctrl+opt+U/I/J/K
(quarters TL/TR/BL/BR). Shift / Ctrl / Ctrl+Shift F13-F19 are recorded
directly in Rectangle Pro and Hammerspoon must NOT bind them (a Hammerspoon
hotkey swallows the key before Rectangle sees it):
- Shift: bottom sixths (F13-F15), bottom eighths (F16-F19)
- Ctrl: top sixths (F13-F15), top eighths (F16-F19)
- Ctrl+Shift: Snap Left/Up/Right on F13/F14/F15; Snap TL/TR/BL/BR on F16-F19
Backup of the working config: ~/Documents/RectangleProConfigFinal.json
(RectangleProConfigOrig.json = before the hand edit).

### Making Rectangle Pro use Ctrl+F14 / Ctrl+F15 (manual JSON edit)
Rectangle Pro's GUI shortcut recorder refuses F14 and F15 (with some
modifier combos, e.g. plain Ctrl), even though the keys reach apps fine
(verified with an hs.eventtap logger: `f14(107) ctrl+fn`). The macOS
brightness shortcuts (symbolichotkeys ids 53/54 on keycodes 107/113) are
already disabled here, so that is not the cause -- it is the recorder.
Workaround, confirmed working 2026-11-24:
1. In Rectangle Pro, assign any combo it accepts (e.g. Ctrl+Shift+F13) to
   the action, then Settings > General > Export Config.
2. Edit the JSON under "shortcuts": set that action's "keyCode" and
   "modifierFlags". Names seen in the export: topCenterSixth, topRightSixth,
   moveLeft/moveUp/moveRight, snapTopLeft/TopRight/BottomLeft/BottomRight.
3. Import Config. Check for duplicate (keyCode, modifierFlags) pairs after.
keyCodes: F13=105 F14=107 F15=113 F16=106 F17=64 F18=79 F19=80.
modifierFlags: Shift=131072, Ctrl=262144, Ctrl+Shift=393216.
Diff two exports with sorted keys: `diff -u <(python3 -m json.tool
--sort-keys A.json) <(python3 -m json.tool --sort-keys B.json)`.

## Where things live (esp-functionkeys.ino)
- GRID[layout][row][col]: CellSpec {lines[2], line_count, cyc}.
  - lines: up to 2 lines of label text.
  - cyc: display-only. Shows a small "(cyc)" tag under the label.
    It does not change the keystroke. Set on Term, Firefox, Jump,
    Finder (and means "cycles" in the user's Hammerspoon setup).
- COL_FILL_HEX[layout][] / COL_DARK_TEXT[layout][]: per-column fill color and whether
  text is black (true) or white (false). Change these to recolor.
- MOD_TAG[]: small modifier text in each cell's corner ("^Sh", "^",
  "Sh"). Text, not symbols: LV_SYMBOL_UP and "^" looked identical.
- Cell layout: label top-left (Montserrat 20), F-key + modifier tag
  bottom-right (Montserrat 14). Empty cells use the same column color
  as labeled ones (no dimming). Pressed state = lighter fill + white border + glow.
- send_keystroke(): the HID call, fires on release only.
- Four themes, cycled in order: THEME_COLOR (default, per-column
  colors) -> THEME_CLASSIC (dark blue, cyan outline) -> THEME_AMBER ->
  THEME_GREEN (1970s/80s monochrome CRT looks) -> back to
  THEME_COLOR. The 3 monochrome themes' colors live in
  MONO_PALETTES[] (indexed by the Theme enum); THEME_COLOR keeps
  using COL_FILL_HEX[]/COL_DARK_TEXT[] instead. The current theme is
  saved in flash (NVS namespace "fkeys", key "theme", a uint8) and
  read in setup(). Hold the top-left cell (Ctrl+Shift F1 / F13,
  THEME_TOGGLE_ROW/COL) for THEME_TOGGLE_MS (2s), then release: it
  advances to the next theme and reboots into it, sending NO
  keystroke. A normal tap on that cell still sends its keystroke.
  Any new per-cell color must be handled for both THEME_COLOR and the
  monochrome branch (build_ui() and cell_event_cb() branch on
  g_theme). To add a 5th theme: add it to the Theme enum before
  THEME_COUNT and add its row to MONO_PALETTES[].

## Common tasks (how requests usually go)
Every change follows: edit .ino -> compile-check -> flash -> user
looks at the panel (often sends a photo) -> adjust -> repeat.
- Recolor a column: edit that column's entry in COL_FILL_HEX[] and
  set COL_DARK_TEXT[] (true = black text, false = white). Hex codes
  from the user are used as given, e.g. "#22c55e" -> 0x22C55E. If a
  color looks off, adjust and reflash rather than debating it.
- Change a label: edit the string in GRID[layout][row][col]. Keep it short.
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
- Hammerspoon's init.lua no longer holds secrets (they are in the
  Keychain), but older backups might. Never print, quote or copy a
  secret anywhere. Labels stay as the short names already used
  (pat, ug, live, email).
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

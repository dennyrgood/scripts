# NEW PROJECT — Surface Dial replacement (knob board)

Status: prospective purchase, not yet ordered. This file is a planning
brief to start a new session on once the board is in hand.

## The hardware

**Waveshare ESP32-S3 1.8" Knob Display Development Board** — Amazon,
waveshare store.
- Physical rotary encoder ("knob") + 1.8" capacitive touch round
  display + a round LCD.
- 2.4GHz WiFi + BT onboard — not needed for this project (local USB-HID
  device only, no networking).
- **Native USB** — ESP32-S3, same chip family as `esp-functionkeys`'s
  board, confirmed capable of real USB-HID output.
- No battery — fine, this sits on a desk plugged into the Mac anyway
  (same power/data cable serves both roles, like the function-key pad).

## The goal

Replace the physical Microsoft Surface Dial on macOS with this board.

## How the Surface Dial currently works (read before designing anything)

Everything lives in `~/.hammerspoon/init.lua`, roughly lines 39-625 as
of 2026-11-24 (search for "Surface Dial" / "MacDial" / "dialRotate" to
relocate if the file has moved since):

- The physical Dial talks to macOS via **a third-party driver app called
  "MacDial"**, which translates Bluetooth Dial input into **synthetic
  scrollWheel events** (rotation; `isContinuous == 0` distinguishes it
  from real trackpad scroll) and **leftMouseDown events** (click;
  `mouseEventSubtype == 0` distinguishes it from a real click).
- Hammerspoon can't see the Dial directly — it watches those
  scroll/click event types and filters with **`fromMacDial(e)`**, which
  checks the event's source process name is literally `"MacDial"` (and
  pid != 0), because a Bluetooth mouse wheel or trackpad gesture can
  produce the same event *shape*.
- Modifier state (which row of actions fires) comes from a **live poll**
  `liveMods()`, not from the dial event's own flags — this was a
  deliberate fix (edit log 2026-09-08) for a bug where a dial action
  that changed the frontmost app cleared the modifier tracker before
  the action could read it.
- Action tables: `dialRotate[modifier][direction]` (direction: -1 = CCW,
  1 = CW) and `dialClick[modifier]` — structurally the same idea as
  `esp-functionkeys`'s row/column action tables (one physical input +
  modifier = one action).
- There's also an optional "DIAL MODES" feature (menu-bar icon, mode
  switching, added 2026-11-02/11-13, off by default) layered on top —
  read it if present, but it's not essential to replicate day one.

## The design decision already made: don't emulate MacDial

Do **not** try to make the new board pretend to be a mouse/scrollwheel
device matching MacDial's event shape — that's fragile (depends on
exact event-type/subtype quirks that exist only because of how a
third-party BT driver happens to synthesize events) and pointless to
replicate on brand-new hardware with no such constraint.

Instead: **follow the `esp-functionkeys` model.** The firmware sends
real USB-HID keystrokes (or consumer-control codes) for each
rotate-detent / click / modifier combination; Hammerspoon binds those
keys *directly*, with no `fromMacDial`-style source-process filtering
needed at all (a genuine HID keyboard event doesn't need to be
disambiguated from mouse/trackpad noise the way a synthesized
scrollwheel event does). This is a smaller, more robust Hammerspoon
change than trying to synthesize scroll-wheel fidelity.

Read `esp-firmware/esp-functionkeys/CLAUDE.md` in full before starting
firmware work — it documents the whole pattern this project should
follow: GRID/FKEY_CODES/ROW_CTRL-style per-input action tables, the
"every input is exactly one keystroke, Hammerspoon decides behavior"
philosophy, the two-USB-port flash-vs-run gotcha (UART1 to flash, native
USB port to run as HID, and the EXIO5-low trick that makes native USB
win over a shared CAN interface — **verify this board has the same
dual-connector/EXIO quirk before assuming it; it may not**, since it's a
different physical board design even though same chip family), and the
general "edit → compile-check → flash → user looks at it → adjust" loop
this whole hardware line uses.

## What to design before writing firmware

1. What rotate-CW / rotate-CCW / click / touch should each send —
   likely new keystrokes (maybe spare F-keys, or dedicated
   consumer-control media/volume codes) distinct from the existing
   F1-F7/F13-F19 pad, so Hammerspoon can tell dial input apart from
   pad input without any MacDial-style filtering.
2. Whether per-app context switching (the Dial's old modifier-based
   mode system) is still wanted, and if so, redesign it as a
   straightforward keystroke-based Hammerspoon table (mirroring
   `dialRotate`/`dialClick`'s shape) rather than porting the
   event-filtering machinery.
3. What the round touch display should actually show — current mode,
   current app, nothing? `esp-functionkeys` has prior art for on-device
   label/theme rendering (`build_ui()`, per-cell labels, themes) that
   could inform this, but the physical shape (round, single
   control) is different enough that it's a new UI, not a port.
4. Old `fromMacDial`/`dialRotate`/`dialClick`/`dialPhysFlags` code in
   `init.lua` should eventually be removed once the new board replaces
   the physical Dial — don't leave dead code/dead Bluetooth-driver
   dependency (MacDial app) lying around once this is live.

## Context this session already has, don't re-derive

- This is unrelated to the fleet-strip board, the e-ink devices, or the
  ESP#1-board-becomes-second-macro-pad plan — separate project, separate
  session.
- General philosophy already settled across this whole hardware
  round: passive/glanceable displays (fleet wall, photo frame, fleet
  strip) use the host-renders/device-is-dumb model; interactive input
  devices (function-key pad, this knob) use the
  device-sends-HID-keystrokes/host-decides-behavior model. This project
  is squarely the second category.

# NEW PROJECT — 13.3" Spectra 6 color e-ink photo frame

Status: **hardware in hand.** 13.3" Spectra 6 E-Ink panel (SKU
100088646) + XIAO ePaper Display Board EE02 driver (SKU 100067144) as
part of "XIAO ePaper DIY Kit EE02 for 13.3" Spectra 6 E-Ink" (SKU
E26010501, $163.90). Plus **one spare standalone EE02 board** (SKU
100067144, $14.90, bought by accident, kept as a spare — not a second
photo frame, no second panel was bought).

## Decision history, briefly (don't re-litigate)

Earlier considered a cheaper 7.3" Spectra 6 (B1) + EE04 as the budget DIY
pick, and the assembled reTerminal E1002 as a no-build alternative —
**both were dropped in favor of this 13.3" large-format build.** Also
confirmed: Seeed's own EE04 does **not** drive the 13.3" panel — EE02 is
the dedicated driver for 13.3" specifically (EE04 is for 24-pin/50-pin
general panels including the 7.3"). You have the correct part.

**Own firmware, not Seeed's SenseCraft HMI** (their no-code drag-and-drop
display designer) — already decided this round: SenseCraft is for
people without a rendering pipeline; you already have `photo_producer.py`
doing exactly the shuffle/rotate/letterbox job needed, with prev/
next/freeze control already built in via `inbox/photos/control.json`.
Adopting SenseCraft would be a downgrade in flexibility for no gain.

## No case exists — you will design/adapt one yourself

Searched Printables, Thingiverse, Makerworld, GitHub, and Seeed's own
wiki/GitHub for an EE02 + 13.3" Spectra 6 specific enclosure. **Nothing
purpose-built was found.** Confirmed panel dimensions (Pakronics spec,
cross-checked across retailers):
- **208.8 x 284.7 x 0.85 mm**

The EE02 driver board's own mounting-hole pattern/dimensions were NOT
found in this search — check `wiki.seeedstudio.com/epaper_ee02/` (or
whatever the EE02-specific wiki page is; only the EE04 one was directly
confirmed as `wiki.seeedstudio.com/epaper_ee04/`) directly for a
dimensioned drawing, KiCad, or Gerber file before modeling a case from
scratch. Generic non-e-paper parametric picture-frame generators exist
on Makerworld (`models/1302211`) and Printables (`model/524813`) that
could be adapted using the dimensions above if nothing better turns up.

## Battery

EE02 has a JST-PH 2.0mm battery connector + charging IC + power switch
(confirmed, same as EE04's spec sheet — both share this connector
standard). Already identified a known-good match: **EEMB 3.7V LiPo,
JST-PH 2.0mm**, either the 1100mAh (603449, ~€9.88, ~4-8 weeks runtime
for infrequent photo refreshes) or 2000mAh (103454, ~€29.99/pack,
~2-3+ months runtime) — pick based on how deep a case you're willing to
print/mount. Confirm polarity (red=+, black=-) against the EE02 board's
silkscreen before first connection, every time you wire a new battery to
a new board — don't assume from memory.

## Architecture: reuse `wall-image/`, don't rewrite

- **Host side**: `photo_producer.py` already does the shuffle/rotate/
  letterbox/control-file logic needed. The only new work is the output
  stage: replace RGB565 packing with a **Spectra 6 six-color palette
  quantization** pass (Pillow's `Image.quantize()` against a custom
  6-entry palette matching Spectra 6's actual colors — need the exact
  RGB values for Spectra 6's palette, not yet looked up this round,
  check E Ink's own Spectra 6 spec or Seeed's SDK/sample code before
  guessing).
- **Update cadence must drop drastically.** E-ink full refresh is slow
  (seconds) and visually flashes — this should be a periodic
  change (minutes to hours), not anything resembling the current
  LCD-tuned auto-advance timer. Adjust `photo_producer.py`'s `--seconds`
  default accordingly, or better, decouple "how often the rotation
  advances" from "how often a frame is re-sent to a battery-powered
  device" (deep-sleep-between-refreshes is likely wanted here given
  there's a battery in play — see below).
- **`wall_server.py`**: new channel, same dispatch pattern as
  `/fleet/*`/`/photos/*` already there.
- **Device firmware is new** — EE02-compatible e-ink driver library
  (GxEPD2-class, or whatever Seeed's own EE02 sample firmware uses —
  check their wiki/GitHub for a reference). Needs:
  - **Deep sleep between polls** if running on battery — the current
    `fleet_wall_image` firmware polls every 15s continuously, fine on
    mains power, but would drain a 1100-2000mAh battery in days. This is
    genuinely new logic, not present anywhere in the existing codebase,
    since no other device here runs on battery.
  - Same CRC32-transfer-check discipline as the other boards (see
    `fleet_wall_image/README.md`'s checksum section).
  - Button handling (EE02 has reset + 3 user buttons) for prev/next/
    freeze, POSTing to a `wall_server.py` endpoint the same way the
    current touch-tap zones dispatch (`/display/tap` equivalent, but
    button-id based instead of x/y coordinate based).

## Context this session already has, don't re-derive

- Don't confuse this with the TRMNL fleet-status project — see
  `TODO_NEW_trmnl_fleet_status.md` — different device, different
  color/panel tech, separate session.
- The spare EE02 board has no assigned purpose yet — it's a spare part,
  not a second project. Don't invent a second photo frame build around
  it unless a second 13.3" panel gets bought later.

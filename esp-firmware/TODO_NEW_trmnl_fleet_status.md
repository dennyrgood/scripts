# NEW PROJECT — TRMNL 7.5" e-ink fleet status display

Status: **hardware in hand.** 2x TRMNL 7.5" (OG) DIY Kit (SKU 104991005,
$47.99 each), purchased and shipped. This replaces the existing RGB
Waveshare ESP32-S3-Touch-LCD-7 (`fleet_wall_image`, ESP#1) in the
fleet-status role.

## Why this device, briefly (don't re-litigate)

The old 7" RGB-parallel board had a long-running, never-fully-resolved
flicker/reboot problem caused by LVGL rendering + WiFi polling
contending for the panel's DMA bus (full history in
`esp-firmware/fleet_wall_image/README.md`). E-ink sidesteps that failure
class entirely — SPI interface, no continuous refresh, and status
content (host up/down, CPU/RAM) doesn't need fast updates anyway.
**Conclusion already reached this round: own firmware, reusing the
existing `wall-image/` host-render pipeline — not TRMNL's own cloud/
BYOS plugin system.** You already have a working Pillow rendering
pipeline; adopting TRMNL's Liquid-templating plugin model would mean
replacing working code with a new system that does the same job through
someone else's templating layer, for no benefit.

## Confirmed facts about this specific hardware

- **Reflash works exactly like a bare dev board, no case disassembly
  needed.** Confirmed: USB-C port + physical boot button are both
  externally accessible on the assembled case. To enter flash mode:
  plug in USB-C, power off, hold boot button, power back on, release.
  (Verified for the assembled "TRMNL (OG)" retail unit; the DIY kit you
  bought is presumably at least as accessible since it's explicitly a
  DIY/moddable product — recheck once in hand, shouldn't differ.)
- **No vendor lock.** TRMNL's own ToS explicitly permits disassembly,
  firmware modification, and API key retrieval. Seeed hosts an official
  wiki page "TRMNL OG DIY Kit works with ESPHome." Same ESP32-C3 chip
  under the hood either way.
- Screen: 7.5" e-ink, TRMNL's own spec says "4 grayscale, fast refresh"
  — note this is **not** 1-bit pure mono, it supports 4 gray levels,
  which is more than a naive `.convert('1')` dither would use. Worth
  checking the actual panel driver/library's expected pixel format
  before assuming 1-bit.
- Comes with enclosure + (per the DIY kit's own listing) battery
  connector support — no case-design work needed here, unlike the 13.3"
  photo project.

## Architecture: reuse `wall-image/`, don't rewrite

- **Host side**: `fleet_snapshot_producer.py`'s `draw_grid()` (6x3,
  800x480) is the right starting layout. Changes needed:
  - Output stage: replace `to_rgb565_bytes()` with a grayscale
    conversion matching whatever bit-depth this panel's driver library
    actually wants (confirm 4-level grayscale support before defaulting
    to 1-bit dithering — a wasted shortcut if the hardware can do
    better).
  - Color-coded severity (teal/orange/red in `pct_color()`) has no
    color equivalent here — needs a non-color substitute (e.g. solid
    fill vs. hatched vs. outlined bar, or a bold/inverted label) for
    WARN/CRIT states. Decide this convention before writing the
    conversion code.
  - **Separately**, there's an open task to densify `draw_grid()`
    itself regardless of which device renders it — see
    `wall-image/TODO_DENSIFY_GRID.md` (stacked CPU+RAM bars, service
    dots, GPU bar, drop the redundant status word). Do that work BEFORE
    or alongside adapting to e-ink, since it affects the same function.
- **`wall_server.py`**: already has the dispatch pattern
  (`/fleet/*`, `/photos/*`, unified `/display/*` with tap-zone
  handling) — a new e-ink channel follows the same shape, just serving
  grayscale-packed frames instead of RGB565, with hash-based "only
  refresh on change" polling (already the right behavior for e-ink,
  where an unnecessary refresh is visually jarring, not just wasteful).
- **Device firmware is new** — e-ink panel driver (GxEPD2-class
  library is the common choice for this hardware family, confirm
  against whatever TRMNL/Seeed's own open-source firmware repo uses
  since they publish one — see `trmnl.app/blog/introducing-byos` and
  their GitHub for a reference implementation you can study, even
  though you're not using their server). Keep the same dumb-client
  behavior: poll hash, fetch on change, CRC32-check every transfer (see
  `fleet_wall_image/README.md`'s checksum section for why this was
  added — real corruption-diagnosis pain, don't skip it on a new
  board).

## Open question: what's the second unit for?

You bought 2x. Decide before building: a second physical location (e.g.
travel/office), a hot spare, or two different views (e.g. one shows the
grid, one always shows a single pinned host's detail screen)? This
affects whether you need one `wall_server.py` channel or two.

## Context this session already has, don't re-derive

- Full fleet host list: root `CLAUDE.md`'s "Fleet machine aliases"
  table, `Status/readme.md`.
- Once this is live, the original RGB 7" board (`fleet_wall_image`,
  ESP#1) is freed up — plan is to repurpose it as a second
  `esp-functionkeys`-style macro pad for a second Mac (separate project,
  not this file's concern, but note the LaunchAgents serving the old
  fleet-wall pipeline on FleetDev will need decommissioning once nothing
  polls them anymore).
- Don't confuse this with the 13.3" Spectra 6 photo-album project — see
  `TODO_NEW_spectra6_photo_frame.md` — different device, different
  color/panel tech, separate session.

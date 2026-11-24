/*
 * ESP-FUNCTIONKEYS — visual macro-pad GUI, F1-F7 / F13-F19 cheat sheet / touch pad.
 * Base init sequence copied verbatim from Waveshare's official
 * examples/Arduino/examples/10_lvgl_v9_demo (esp-arduino-libs/ESP32_Display_Panel),
 * same as fleet_wall/esp-test.
 *
 * Now sends real USB HID keystrokes on release (2026-09-16) -- requires the
 * board's USB Mode set to USB-OTG/TinyUSB (USBMode=default), not the default
 * Hardware-CDC-and-JTAG mode HID can't run under. CDCOnBoot=cdc kept on too,
 * so Serial console debugging still works over the same port as a composite
 * HID+CDC device. Pattern taken from arduino-esp32's own
 * USB/examples/Keyboard/KeyboardMessage: Keyboard.begin() before USB.begin().
 *
 * Two layouts (medium-hold the top-left cell to switch): layout 0 = F1-F7,
 * layout 1 = F13-F19 (Rectangle Pro window management).
 * Grid: 7 columns (F1-F7 or F13-F19) x 4 rows (Ctrl+Shift / Ctrl / Shift / Plain),
 * mirroring the real Hammerspoon posCtrlShift/posCtrl/posShift/posPlain
 * tables -- every modifier variant is its own touch target, column = F-key,
 * so no on-screen modifier toggle is needed at all.
 *
 * Started as a 3-row grid (Ctrl+Shift and Ctrl sharing one cell for F10/
 * F11, the only two keys with all four modifier layers), but that made
 * those two cells ambiguous -- one tap target showing two different
 * keystrokes. Split to 4 rows so every cell is exactly one keystroke,
 * matching the "what you see is the exact key combo" cheat-sheet purpose.
 */

#include <Arduino.h>
#include <esp_display_panel.hpp>
#include <esp_err.h>

#include <lvgl.h>
#include <demos/lv_demos.h>

#include "esp_lv_adapter_arduino.h"

#include <USB.h>
#include <USBHIDKeyboard.h>
#include <Preferences.h>

static USBHIDKeyboard Keyboard;

// Four looks, cycled by holding the cell below for THEME_TOGGLE_MS and
// releasing: THEME_COLOR (default, per-column colors) -> THEME_CLASSIC (the
// original dark-blue/cyan look) -> THEME_AMBER -> THEME_GREEN (1970s/80s
// monochrome CRT looks) -> back to THEME_COLOR. The choice is saved to flash
// (NVS, namespace "fkeys", key "theme") and the board reboots into the next
// one; a normal tap on that cell still sends its keystroke like any other.
// THEME_COLOR keeps the per-column palette (COL_FILL_HEX/COL_DARK_TEXT
// below); the other three are monochrome and use MONO_PALETTES[] instead.
enum Theme { THEME_COLOR = 0, THEME_CLASSIC, THEME_AMBER, THEME_GREEN, THEME_COUNT };
static Theme g_theme = THEME_COLOR;
static uint32_t g_press_ms = 0;

// Two layouts, same 7x4 grid shape. Layout 0 sends F1-F7, layout 1 sends
// F13-F19 (extended-keyboard keys; Rectangle Pro does the window moves).
// Hold the top-left cell (see THEME_TOGGLE_ROW/COL) for TIERED durations:
//   < LAYOUT_TOGGLE_MS             -> normal tap, sends its keystroke
//   LAYOUT_TOGGLE_MS..THEME_TOGGLE_MS -> switch layout, sends NOTHING
//   >= THEME_TOGGLE_MS             -> next theme + reboot, sends NOTHING
// The cell's border turns yellow at the layout tier and red at the theme
// tier while the finger is still down, so you can see which one you'll get.
#define LAYOUT_COUNT 2
#define LAYOUT_TOGGLE_MS 600
static int g_layout = 0;
static int g_hold_tier = 0; // 0 none, 1 layout, 2 theme (feedback state)
#define THEME_TOGGLE_ROW 0
#define THEME_TOGGLE_COL 0
#define THEME_TOGGLE_MS  2000 // must stay > LAYOUT_TOGGLE_MS

using namespace esp_panel::drivers;
using namespace esp_panel::board;

#define COL_BG lv_color_hex(0x050d14) // page background, shows as the thin gap between cells

// One palette per monochrome theme (indexed by Theme, THEME_COLOR's slot
// unused). CRT amber/green pick a near-black cell fill and a bright, fully
// saturated border/text in that single hue -- no gradient, like a real
// phosphor display. Classic keeps its original dark-blue/cyan values.
struct MonoPalette {
    uint32_t cell, border, text, text_dim, fkey, pressed_bg, pressed_text, pressed_brd;
};
static const MonoPalette MONO_PALETTES[THEME_COUNT] = {
    /* THEME_COLOR   */ {0, 0, 0, 0, 0, 0, 0, 0}, // unused
    /* THEME_CLASSIC */ {0x0a1c2e, 0x22d3ee, 0x5fd6ee, 0x6b93a8, 0x4f7488, 0x14495c, 0xffffff, 0x8febff},
    /* THEME_AMBER   */ {0x120a00, 0xffb000, 0xffb000, 0xa5730a, 0x8a5f08, 0x2e1c00, 0xffe9b3, 0xffcf66},
    /* THEME_GREEN   */ {0x001200, 0x33ff33, 0x33ff33, 0x1f9e1f, 0x1a7f1a, 0x002e00, 0xccffcc, 0x8cff8c},
};

#define N_COLS 7
#define N_ROWS 4

// Up to 2 lines of primary content per cell (blank cell = zero lines), plus
// an optional smaller "(cyc)" tag below it. LV_SYMBOL_UP (not a raw "↑")
// because LVGL's default font subset doesn't include arbitrary Unicode
// arrows -- same class of bug fixed for FLEET_WALL's UTF-8 middle-dot.
struct CellSpec {
    const char *lines[2];
    int line_count;
    const char *tag; // sub-tag text under the label, e.g. "(cyc)"; "" = none
};

// [layout][col]. Layout 0 = F1-F7, layout 1 = F13-F19.
static const char *FKEYS[LAYOUT_COUNT][N_COLS] = {
    {"F1", "F2", "F3", "F4", "F5", "F6", "F7"},
    {"F13", "F14", "F15", "F16", "F17", "F18", "F19"},
};
static const uint8_t FKEY_CODES[LAYOUT_COUNT][N_COLS] = {
    {KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7},
    {KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17, KEY_F18, KEY_F19},
};

// Which modifiers each row's keystroke holds down. Row order matches MOD_TAG
// below: 0=Ctrl+Shift, 1=Ctrl, 2=Shift, 3=Plain (no modifier).
static const bool ROW_CTRL[N_ROWS]  = {true,  true,  false, false};
static const bool ROW_SHIFT[N_ROWS] = {true,  false, true,  false};

// One modifier tag per row, shown small next to the F-key reference in each
// cell's corner (e.g. "^Sh F10") instead of prefixed onto the big action
// word. Plain row has no tag -- bare F-key only. Text, not icons: an
// LV_SYMBOL_UP icon and a literal "^" looked near-identical at 14px, so
// Shift is spelled out ("Sh") rather than risking another symbol collision.
static const char *MOD_TAG[N_ROWS] = {"^Sh", "^", "Sh", ""};

// [row][col] -- row 0 = Ctrl+Shift, row 1 = Ctrl, row 2 = Shift, row 3 = Plain.
// Pad = F1-F7 (F8-F12 laptop keys and F13-F19 extended keys are not on the pad).
// Blank cells (line_count 0) are unlabeled (same color, not dimmed) but STILL send
// their keystroke, so a Hammerspoon binding can be added without touching
// this file.
// No modifier symbols in the action text itself anymore -- see MOD_TAG above.
// Each cell's last field is a free-text sub-tag shown under the label
// (small font, same row/col as the old "(cyc)" tag) -- "" for none, or any
// string you want, e.g. "(cyc)", "(hold)", "(2x)".
//
// ====================================================================
// AFTER EDITING THIS GRID, YOU MUST REFLASH THE BOARD, OR NOTHING CHANGES:
//   cable in UART1 connector (port /dev/cu.usbmodem5B5E0664711), then:
//     ./flash.esp.keypad          (from the scripts repo root)
//   or ./flash-fkeys.sh           (from this esp-functionkeys/ directory)
//   Then move the cable to the USB connector to use it as a keyboard again.
//   SAVE THE FILE FIRST -- an unsaved edit compiles the old content and
//   the flasher reports "no changed sectors," silently flashing nothing new.
// ====================================================================
// [layout][row][col]. Layout 1 mirrors Rectangle Pro (set in that app):
//   Plain = thirds + quarters (Hammerspoon forwards plain F13-F19 to
//           ctrl+opt+D/F/G and U/I/J/K), Shift = bottom sixths/eighths,
//   Ctrl = top sixths/eighths, Ctrl+Shift = Snap. TL/TC/TR = top left/
//   center/right, BL/BC/BR = bottom, TCL/TCR = top center-left/right.
static const CellSpec GRID[LAYOUT_COUNT][N_ROWS][N_COLS] = {
    { // layout 0: F1-F7
        { // row -- Ctrl+Shift
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"Jump", ""}, 1, "(list)"},
        },
        { // row -- Ctrl
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"", ""}, 0, ""},
            {{"open", "iTerm"}, 2, ""},
            {{"Restore", ""}, 1, "(min)"},
            {{"Jump", ""}, 1, ""},
        },
        { // row -- Shift
            {{"Delay", ""}, 1, ""},
            {{"Scroll", ""}, 1, ""},
            {{"new", ""}, 1, ""},
            {{"new", ""}, 1, ""},
            {{"new", ""}, 1, ""},
            {{"Min", ""}, 1, ""},
            {{"Tear", ""}, 1, ""},
        },
        { // row -- Plain
            {{"Area", ""}, 1, ""},
            {{"Full", ""}, 1, ""},
            {{"Term", ""}, 1, "(cyc)"},
            {{"iTerm", ""}, 1, "(cyc)"},
            {{"Finder", ""}, 1, "(cyc)"},
            {{"Max", ""}, 1, ""},
            {{"Move", ""}, 1, ""},
        },
    },
    { // layout 1: F13-F19
        { // row -- Ctrl+Shift
            {{"Snap", "Left"}, 2, ""},
            {{"Snap", "Up"}, 2, ""},
            {{"Snap", "Right"}, 2, ""},
            {{"Snap", "TL"}, 2, ""},
            {{"Snap", "TR"}, 2, ""},
            {{"Snap", "BL"}, 2, ""},
            {{"Snap", "BR"}, 2, ""},
        },
        { // row -- Ctrl
            {{"6th", "TL"}, 2, ""},
            {{"6th", "TC"}, 2, ""},
            {{"6th", "TR"}, 2, ""},
            {{"8th", "TL"}, 2, ""},
            {{"8th", "TCL"}, 2, ""},
            {{"8th", "TCR"}, 2, ""},
            {{"8th", "TR"}, 2, ""},
        },
        { // row -- Shift
            {{"6th", "BL"}, 2, ""},
            {{"6th", "BC"}, 2, ""},
            {{"6th", "BR"}, 2, ""},
            {{"8th", "BL"}, 2, ""},
            {{"8th", "BCL"}, 2, ""},
            {{"8th", "BCR"}, 2, ""},
            {{"8th", "BR"}, 2, ""},
        },
        { // row -- Plain
            {{"1/3", ""}, 1, ""},
            {{"2/3", ""}, 1, ""},
            {{"3/3", ""}, 1, ""},
            {{"1/4", "TL"}, 2, ""},
            {{"1/4", "TR"}, 2, ""},
            {{"1/4", "BL"}, 2, ""},
            {{"1/4", "BR"}, 2, ""},
        },
    },
};

// Per-column colors, per layout. Layout 0: amber, amber (capture), green x3
// (apps), purple x2 (window). Layout 1: blue (F13-F15: thirds/sixths/snap
// L-U-R), teal (F16-F19: quarters/eighths/snap corners).
static const uint32_t COL_FILL_HEX[LAYOUT_COUNT][N_COLS] = {
    {0xE8590C, 0xE8590C, 0x22C55E, 0x22C55E, 0x22C55E, 0x7B3FA6, 0x7B3FA6},
    {0x2563EB, 0x2563EB, 0x2563EB, 0x0D9488, 0x0D9488, 0x0D9488, 0x0D9488},
};
static const bool COL_DARK_TEXT[LAYOUT_COUNT][N_COLS] = {
    {true,  true,  false, false, false, false, false},
    {false, false, false, false, false, false, false},
};

// Per-cell context handed to the event callback so it knows which
// keystroke to send and which colors to restore after a press.
struct CellCtx {
    lv_obj_t *content; // nullptr for blank cells
    int row, col;
    lv_color_t fill;   // resting fill
    lv_color_t border; // resting border
};
static CellCtx CELL_CTX[N_ROWS][N_COLS];

// Sends the real USB HID keystroke for one grid cell -- the modifier(s) for
// its row (see ROW_CTRL/ROW_SHIFT) plus the F-key for its column. Held for
// a few ms rather than an instant press+release, matching how a real
// physical chord is timed (both keys down together, briefly, then up).
static void send_keystroke(int row, int col) {
    // Blank cells send too -- no line_count guard on purpose.
    if (ROW_CTRL[row])  Keyboard.press(KEY_LEFT_CTRL);
    if (ROW_SHIFT[row]) Keyboard.press(KEY_LEFT_SHIFT);
    Keyboard.press(FKEY_CODES[g_layout][col]);
    delay(15);
    Keyboard.releaseAll();
}

static void advance_theme_and_restart(void) {
    Theme next = (Theme)((g_theme + 1) % THEME_COUNT);
    Preferences prefs;
    prefs.begin("fkeys", false);
    prefs.putUChar("theme", (uint8_t)next);
    // Carry the current layout across THIS reboot only; setup() reads and
    // erases it, so a power cycle (e.g. moving the cable) boots to layout 0.
    prefs.putUChar("layout", (uint8_t)g_layout);
    prefs.end();
    Serial.printf("Theme -> %d, restarting\n", (int)next);
    delay(50);
    ESP.restart();
}

static void build_ui(void);

// Rebuild the whole screen for the new g_layout. Run via lv_async_call, NOT
// directly from the touch callback: that callback belongs to a cell that
// lv_obj_clean() is about to delete.
static void rebuild_ui_async(void *) {
    build_ui();
}

static void switch_layout(void) {
    g_layout = (g_layout + 1) % LAYOUT_COUNT;
    Serial.printf("Layout -> %d\n", g_layout);
    lv_async_call(rebuild_ui_async, nullptr);
}

static bool is_toggle_cell(const CellCtx *ctx) {
    return ctx->row == THEME_TOGGLE_ROW && ctx->col == THEME_TOGGLE_COL;
}

// Visual cue while holding the toggle cell: yellow border = release now to
// switch layout, red border = release now to change theme.
static void hold_feedback(lv_obj_t *cell, int tier) {
    if (tier == g_hold_tier) return;
    g_hold_tier = tier;
    lv_color_t c = (tier == 2) ? lv_color_hex(0xFF3B30) : lv_color_hex(0xFFD400);
    lv_obj_set_style_border_color(cell, c, 0);
    lv_obj_set_style_border_width(cell, 6, 0);
    lv_obj_set_style_shadow_color(cell, c, 0);
}

static void cell_event_cb(lv_event_t *e) {
    lv_obj_t *cell = (lv_obj_t *)lv_event_get_target(e);
    lv_event_code_t code = lv_event_get_code(e);
    CellCtx *ctx = (CellCtx *)lv_event_get_user_data(e);
    lv_obj_t *content = ctx->content;

    if (code == LV_EVENT_PRESSING) {
        if (is_toggle_cell(ctx)) {
            uint32_t held = millis() - g_press_ms;
            if (held >= THEME_TOGGLE_MS)       hold_feedback(cell, 2);
            else if (held >= LAYOUT_TOGGLE_MS) hold_feedback(cell, 1);
        }
    } else if (code == LV_EVENT_PRESSED) {
        g_press_ms = millis();
        g_hold_tier = 0;
        if (g_theme != THEME_COLOR) {
            const MonoPalette &pal = MONO_PALETTES[g_theme];
            lv_obj_set_style_bg_color(cell, lv_color_hex(pal.pressed_bg), 0);
            lv_obj_set_style_border_color(cell, lv_color_hex(pal.pressed_brd), 0);
            lv_obj_set_style_shadow_color(cell, lv_color_hex(pal.border), 0);
            if (content) lv_obj_set_style_text_color(content, lv_color_hex(pal.pressed_text), 0);
        } else {
            // Saturated fills can't "glow" by brightening like the old dark
            // cells did -- lighten the fill and flash a white border instead.
            lv_obj_set_style_bg_color(cell, lv_color_mix(lv_color_white(), ctx->fill, 90), 0);
            lv_obj_set_style_border_color(cell, lv_color_white(), 0);
            lv_obj_set_style_shadow_color(cell, lv_color_white(), 0);
        }
        lv_obj_set_style_shadow_width(cell, 22, 0);
        lv_obj_set_style_shadow_spread(cell, 2, 0);
        lv_obj_set_style_shadow_opa(cell, LV_OPA_70, 0);
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) {
        lv_obj_set_style_bg_color(cell, ctx->fill, 0);
        lv_obj_set_style_border_color(cell, ctx->border, 0);
        lv_obj_set_style_border_width(cell, 2, 0);
        g_hold_tier = 0;
        lv_obj_set_style_shadow_width(cell, 0, 0);
        lv_obj_set_style_shadow_opa(cell, LV_OPA_TRANSP, 0);
        if (g_theme != THEME_COLOR && content) {
            lv_obj_set_style_text_color(content, lv_color_hex(MONO_PALETTES[g_theme].text), 0);
        }
        // Fire on an actual release (finger lifted while still on the cell),
        // not on PRESS_LOST (finger dragged off) -- matches a real button's
        // behavior, where dragging off before releasing cancels the press.
        if (code == LV_EVENT_RELEASED) {
            // Holds on the toggle cell act INSTEAD of sending a keystroke:
            // long = next theme (reboot), medium = switch layout.
            if (is_toggle_cell(ctx)) {
                uint32_t held = millis() - g_press_ms;
                if (held >= THEME_TOGGLE_MS) {
                    advance_theme_and_restart();
                    return;
                }
                if (held >= LAYOUT_TOGGLE_MS) {
                    switch_layout();
                    return;
                }
            }
            send_keystroke(ctx->row, ctx->col);
        }
    }
}

static void build_ui(void) {
    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, COL_BG, 0);
    lv_obj_set_style_pad_all(scr, 6, 0);
    lv_obj_clear_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_clean(scr); // no-op on first build; deletes the old grid on a layout switch

    static lv_coord_t col_dsc[N_COLS + 1];
    static lv_coord_t row_dsc[N_ROWS + 1];
    for (int i = 0; i < N_COLS; i++) col_dsc[i] = LV_GRID_FR(1);
    col_dsc[N_COLS] = LV_GRID_TEMPLATE_LAST;
    for (int i = 0; i < N_ROWS; i++) row_dsc[i] = LV_GRID_FR(1);
    row_dsc[N_ROWS] = LV_GRID_TEMPLATE_LAST;

    lv_obj_t *grid = lv_obj_create(scr);
    lv_obj_set_size(grid, LV_PCT(100), LV_PCT(100));
    lv_obj_set_grid_dsc_array(grid, col_dsc, row_dsc);
    lv_obj_set_style_bg_opa(grid, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(grid, 0, 0);
    lv_obj_set_style_pad_all(grid, 0, 0);
    lv_obj_set_style_pad_gap(grid, 4, 0);
    lv_obj_clear_flag(grid, LV_OBJ_FLAG_SCROLLABLE);

    for (int row = 0; row < N_ROWS; row++) {
        for (int col = 0; col < N_COLS; col++) {
            const CellSpec &spec = GRID[g_layout][row][col];

            lv_obj_t *cell = lv_obj_create(grid);
            lv_obj_set_grid_cell(cell, LV_GRID_ALIGN_STRETCH, col, 1, LV_GRID_ALIGN_STRETCH, row, 1);
            lv_color_t base = lv_color_hex(COL_FILL_HEX[g_layout][col]);
            lv_color_t txt  = COL_DARK_TEXT[g_layout][col] ? lv_color_black() : lv_color_white();
            // Blank cells are NOT dimmed: they send a keystroke like any other,
            // so they get the same full column color, just with no label.
            lv_color_t fill = base;
            lv_color_t brd  = lv_color_mix(lv_color_white(), base, 60);
            lv_color_t cyc_col  = txt;
            lv_color_t fkey_col = txt;
            lv_opa_t cyc_opa  = LV_OPA_80;
            lv_opa_t fkey_opa = LV_OPA_70;
            if (g_theme != THEME_COLOR) {
                const MonoPalette &pal = MONO_PALETTES[g_theme];
                fill = lv_color_hex(pal.cell);
                brd  = lv_color_hex(pal.border);
                txt  = lv_color_hex(pal.text);
                cyc_col  = lv_color_hex(pal.text_dim);
                fkey_col = lv_color_hex(pal.fkey);
                cyc_opa = fkey_opa = LV_OPA_COVER;
            }
            CELL_CTX[row][col].fill = fill;
            CELL_CTX[row][col].border = brd;
            lv_obj_set_style_bg_color(cell, fill, 0);
            lv_obj_set_style_bg_opa(cell, LV_OPA_COVER, 0);
            lv_obj_set_style_border_color(cell, brd, 0);
            lv_obj_set_style_border_width(cell, 2, 0);
            lv_obj_set_style_radius(cell, 8, 0);
            lv_obj_set_style_pad_all(cell, 6, 0);
            lv_obj_clear_flag(cell, LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_add_flag(cell, LV_OBJ_FLAG_CLICKABLE);

            lv_obj_t *content = nullptr;
            if (spec.line_count > 0) {
                char buf[80];
                buf[0] = '\0';
                for (int i = 0; i < spec.line_count; i++) {
                    if (i > 0) strcat(buf, "\n");
                    strcat(buf, spec.lines[i]);
                }
                content = lv_label_create(cell);
                lv_label_set_text(content, buf);
                // 24px clipped "Terminal"/"Firefox" (8-letter words) once
                // switched to left-align -- centered had been quietly
                // clipping the same overflow symmetrically on both sides,
                // which read as "barely fits" rather than obviously broken.
                // Dropped to 20px, plus an explicit width + LONG_DOT as a
                // safety net so any future long word truncates visibly
                // ("Termin...") instead of silently cutting off mid-letter.
                lv_obj_set_style_text_font(content, &lv_font_montserrat_20, 0);
                lv_obj_set_style_text_color(content, txt, 0);
                lv_obj_set_style_text_align(content, LV_TEXT_ALIGN_LEFT, 0);
                lv_obj_set_style_text_line_space(content, 2, 0);
                lv_obj_clear_flag(content, LV_OBJ_FLAG_CLICKABLE);
                lv_label_set_long_mode(content, LV_LABEL_LONG_DOT); // needs BOTH width and height set to truncate instead of wrap/overflow
                lv_obj_set_width(content, LV_PCT(96));
                lv_obj_set_height(content, 50); // room for the one 2-line cell ("open"/"term"); single-line cells just have headroom
                // Flush top-left, per 2026-09-16 feedback that centered text
                // felt busy against the bottom-right F-key corner -- top-left
                // content vs. bottom-right reference reads cleaner as a pair.
                lv_obj_align(content, LV_ALIGN_TOP_LEFT, 2, 0);
            }

            if (spec.tag != nullptr && spec.tag[0] != '\0') {
                lv_obj_t *cyc = lv_label_create(cell);
                lv_label_set_text(cyc, spec.tag);
                lv_obj_set_style_text_font(cyc, &lv_font_montserrat_14, 0);
                lv_obj_set_style_text_color(cyc, cyc_col, 0);
                lv_obj_set_style_text_opa(cyc, cyc_opa, 0);
                lv_obj_clear_flag(cyc, LV_OBJ_FLAG_CLICKABLE);
                lv_obj_align(cyc, LV_ALIGN_TOP_LEFT, 2, 32);
            }

            // Corner reference: modifier tag + F-key together (e.g. "^Sh F10"),
            // or the bare F-key alone for the no-modifier row. Blank cells
            // send their keystroke too, so they get the tag as well.
            lv_obj_t *fkey = lv_label_create(cell);
            char fkey_buf[16];
            if (MOD_TAG[row][0] != '\0') {
                snprintf(fkey_buf, sizeof(fkey_buf), "%s %s", MOD_TAG[row], FKEYS[g_layout][col]);
            } else {
                snprintf(fkey_buf, sizeof(fkey_buf), "%s", FKEYS[g_layout][col]);
            }
            lv_label_set_text(fkey, fkey_buf);
            lv_obj_set_style_text_font(fkey, &lv_font_montserrat_14, 0);
            lv_obj_set_style_text_color(fkey, fkey_col, 0);
            lv_obj_set_style_text_opa(fkey, fkey_opa, 0);
            lv_obj_clear_flag(fkey, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_align(fkey, LV_ALIGN_BOTTOM_RIGHT, -4, -3);

            CELL_CTX[row][col].content = content;
            CELL_CTX[row][col].row = row;
            CELL_CTX[row][col].col = col;
            lv_obj_add_event_cb(cell, cell_event_cb, LV_EVENT_PRESSED, &CELL_CTX[row][col]);
            lv_obj_add_event_cb(cell, cell_event_cb, LV_EVENT_PRESSING, &CELL_CTX[row][col]);
            lv_obj_add_event_cb(cell, cell_event_cb, LV_EVENT_RELEASED, &CELL_CTX[row][col]);
            lv_obj_add_event_cb(cell, cell_event_cb, LV_EVENT_PRESS_LOST, &CELL_CTX[row][col]);
        }
    }
}

void setup()
{
    Serial.begin(115200);

    // HID keyboard + Serial console as one composite USB device. Order
    // matters: register every interface (Serial's CDC is already implicit
    // via CDCOnBoot=cdc, Keyboard needs an explicit begin()) before the
    // single USB.begin() that finalizes the descriptor and starts the stack.
    Keyboard.begin();
    USB.begin();

    Serial.println("ESP-FUNCTIONKEYS start");

    {
        Preferences prefs;
        prefs.begin("fkeys", false); // rw so the namespace is created on first boot
        uint8_t saved = prefs.getUChar("theme", THEME_COLOR);
        g_theme = (saved < THEME_COUNT) ? (Theme)saved : THEME_COLOR; // guard against a stale/garbage value
        // Layout survives only the theme-change reboot: read it, then erase.
        uint8_t lay = prefs.getUChar("layout", 0);
        g_layout = (lay < LAYOUT_COUNT) ? lay : 0;
        prefs.remove("layout");
        prefs.end();
        Serial.printf("Theme: %d, layout: %d\n", (int)g_theme, g_layout);
    }

    Board *board = new Board();
    if ((board == nullptr) || !board->init()) {
        Serial.println("Board init failed");
        while (true) {
            delay(1000);
        }
    }

    const esp_lv_adapter_rotation_t rotation = ESP_LV_ADAPTER_ROTATE_0;
    const esp_lv_adapter_tear_avoid_mode_t tear_mode = ESP_LV_ADAPTER_TEAR_AVOID_MODE_DEFAULT_RGB;
    const uint8_t frame_buffer_count = esp_lv_adapter_get_required_frame_buffer_count(tear_mode, rotation);

    LCD *lcd = board->getLCD();
    if (lcd == nullptr) {
        Serial.println("LCD device is not available");
        while (true) {
            delay(1000);
        }
    }
    auto *lcd_bus = lcd->getBus();
    if (lcd_bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
        lcd->configFrameBufferNumber(frame_buffer_count);
        static_cast<BusRGB *>(lcd_bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 20);
    }

    assert(board->begin());

    esp_lv_adapter_config_t adapter_config = ESP_LV_ADAPTER_DEFAULT_CONFIG();
    adapter_config.task_stack_size = 12 * 1024;
    adapter_config.task_priority = 2;
    adapter_config.task_core_id = ARDUINO_RUNNING_CORE;
    ESP_ERROR_CHECK(esp_lv_adapter_init(&adapter_config));

    esp_lv_adapter_display_config_t disp_config = ESP_LV_ADAPTER_DISPLAY_RGB_DEFAULT_CONFIG(
        lcd, lcd->getFrameWidth(), lcd->getFrameHeight(), rotation
    );
    disp_config.profile.use_psram = true;

    lv_display_t *disp = esp_lv_adapter_register_display(&disp_config);
    assert(disp != nullptr);

    if (board->getTouch() != nullptr) {
        esp_lv_adapter_touch_config_t touch_config = ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(disp, board->getTouch());
        lv_indev_t *touch = esp_lv_adapter_register_touch(&touch_config);
        assert(touch != nullptr);
    }

    ESP_ERROR_CHECK(esp_lv_adapter_start());

    ESP_ERROR_CHECK(esp_lv_adapter_lock(-1));
    build_ui();
    esp_lv_adapter_unlock();

    Serial.println("ESP-FUNCTIONKEYS ready");
}

void loop()
{
    delay(1000);
}

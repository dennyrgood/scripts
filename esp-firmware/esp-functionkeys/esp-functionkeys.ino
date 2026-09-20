/*
 * ESP-FUNCTIONKEYS — visual macro-pad GUI, F6-F12 cheat sheet / touch pad.
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
 * Grid: 7 columns (F6-F12) x 4 rows (Ctrl+Shift / Ctrl / Shift / Plain),
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

static USBHIDKeyboard Keyboard;

using namespace esp_panel::drivers;
using namespace esp_panel::board;

#define COL_BG           lv_color_hex(0x050d14) // page background, shows as the thin gap between cells
#define COL_CELL         lv_color_hex(0x0a1c2e)
#define COL_BORDER       lv_color_hex(0x22d3ee)
#define COL_TEXT         lv_color_hex(0x5fd6ee)
#define COL_TEXT_DIM     lv_color_hex(0x6b93a8) // "(cyc)" tag
#define COL_FKEY         lv_color_hex(0x4f7488) // corner F-key reference, dimmest element on screen
#define COL_PRESSED_BG   lv_color_hex(0x14495c)
#define COL_PRESSED_TEXT lv_color_hex(0xffffff)
#define COL_PRESSED_BRD  lv_color_hex(0x8febff)

#define N_COLS 7
#define N_ROWS 4

// Up to 2 lines of primary content per cell (blank cell = zero lines), plus
// an optional smaller "(cyc)" tag below it. LV_SYMBOL_UP (not a raw "↑")
// because LVGL's default font subset doesn't include arbitrary Unicode
// arrows -- same class of bug fixed for FLEET_WALL's UTF-8 middle-dot.
struct CellSpec {
    const char *lines[2];
    int line_count;
    bool cyc;
};

static const char *FKEYS[N_COLS] = {"F6", "F7", "F8", "F9", "F10", "F11", "F12"};
static const uint8_t FKEY_CODES[N_COLS] = {KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12};

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
// F8/F10/F11 use all four layers; F12 stops at Ctrl; F6/F7/F9 stop at Shift.
// Blank cells (line_count 0) are dark-tinted and unlabeled but STILL send
// their keystroke, so a Hammerspoon binding can be added without touching
// this file.
// No modifier symbols in the action text itself anymore -- see MOD_TAG above.
static const CellSpec GRID[N_ROWS][N_COLS] = {
    { // row 0 -- Ctrl+Shift
        {{"", ""}, 0, false},
        {{"", ""}, 0, false},
        {{"new", ""}, 1, false},
        {{"", ""}, 0, false},
        {{"email", ""}, 1, false},
        {{"move", ""}, 1, false},
        {{"arrange", ""}, 1, false},
    },
    { // row 1 -- Ctrl
        {{"", ""}, 0, false},
        {{"", ""}, 0, false},
        {{"iTerm", ""}, 1, true},
        {{"", ""}, 0, false},
        {{"live", ""}, 1, false},
        {{"tear", ""}, 1, false},
        {{"open", "iTerm"}, 2, false},
    },
    { // row 2 -- Shift
        {{"Delay", ""}, 1, false},
        {{"Scroll", ""}, 1, false},
        {{"new", ""}, 1, false},
        {{"new", ""}, 1, false},
        {{"ug", ""}, 1, false},
        {{"list", ""}, 1, false},
        {{"new", ""}, 1, false},
    },
    { // row 3 -- Plain
        {{"Area", ""}, 1, false},
        {{"Full", ""}, 1, false},
        {{"Term", ""}, 1, true},
        {{"Firefox", ""}, 1, true},
        {{"pat", ""}, 1, false},
        {{"Jump", ""}, 1, true},
        {{"Finder", ""}, 1, true},
    },
};

// Per-column colors, matching the physical printed key strip above the keys:
// amber, amber, dark green, dark green, yellow, purple, dark green.
static const uint32_t COL_FILL_HEX[N_COLS] = {0xE8590C, 0xE8590C, 0x22C55E, 0x22C55E, 0xFBBF24, 0x7B3FA6, 0x22C55E};
static const bool COL_DARK_TEXT[N_COLS]    = {true,     true,     false,    false,    true,     false,    false};

// Per-cell context handed to the event callback so it knows which
// keystroke to send and which colors to restore after a press.
struct CellCtx {
    lv_obj_t *content; // nullptr for blank cells
    int row, col;
    lv_color_t fill;   // resting fill (dimmed for blank cells)
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
    Keyboard.press(FKEY_CODES[col]);
    delay(15);
    Keyboard.releaseAll();
}

static void cell_event_cb(lv_event_t *e) {
    lv_obj_t *cell = (lv_obj_t *)lv_event_get_target(e);
    lv_event_code_t code = lv_event_get_code(e);
    CellCtx *ctx = (CellCtx *)lv_event_get_user_data(e);
    lv_obj_t *content = ctx->content;

    if (code == LV_EVENT_PRESSED) {
        // Saturated fills can't "glow" by brightening like the old dark
        // cells did -- lighten the fill and flash a white border instead.
        lv_obj_set_style_bg_color(cell, lv_color_mix(lv_color_white(), ctx->fill, 90), 0);
        lv_obj_set_style_border_color(cell, lv_color_white(), 0);
        lv_obj_set_style_shadow_color(cell, lv_color_white(), 0);
        lv_obj_set_style_shadow_width(cell, 22, 0);
        lv_obj_set_style_shadow_spread(cell, 2, 0);
        lv_obj_set_style_shadow_opa(cell, LV_OPA_70, 0);
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) {
        lv_obj_set_style_bg_color(cell, ctx->fill, 0);
        lv_obj_set_style_border_color(cell, ctx->border, 0);
        lv_obj_set_style_shadow_width(cell, 0, 0);
        lv_obj_set_style_shadow_opa(cell, LV_OPA_TRANSP, 0);
        // Fire on an actual release (finger lifted while still on the cell),
        // not on PRESS_LOST (finger dragged off) -- matches a real button's
        // behavior, where dragging off before releasing cancels the press.
        if (code == LV_EVENT_RELEASED) {
            send_keystroke(ctx->row, ctx->col);
        }
    }
}

static void build_ui(void) {
    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, COL_BG, 0);
    lv_obj_set_style_pad_all(scr, 6, 0);
    lv_obj_clear_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

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
            const CellSpec &spec = GRID[row][col];

            lv_obj_t *cell = lv_obj_create(grid);
            lv_obj_set_grid_cell(cell, LV_GRID_ALIGN_STRETCH, col, 1, LV_GRID_ALIGN_STRETCH, row, 1);
            lv_color_t base = lv_color_hex(COL_FILL_HEX[col]);
            lv_color_t txt  = COL_DARK_TEXT[col] ? lv_color_black() : lv_color_white();
            // Blank cells (no binding) get a dark tint of the column color so
            // populated cells stand out against them.
            lv_color_t fill = (spec.line_count > 0) ? base : lv_color_mix(base, COL_BG, 60);
            lv_color_t brd  = (spec.line_count > 0) ? lv_color_mix(lv_color_white(), base, 60) : lv_color_mix(base, COL_BG, 110);
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

            if (spec.cyc) {
                lv_obj_t *cyc = lv_label_create(cell);
                lv_label_set_text(cyc, "(cyc)");
                lv_obj_set_style_text_font(cyc, &lv_font_montserrat_14, 0);
                lv_obj_set_style_text_color(cyc, txt, 0);
                lv_obj_set_style_text_opa(cyc, LV_OPA_80, 0);
                lv_obj_clear_flag(cyc, LV_OBJ_FLAG_CLICKABLE);
                lv_obj_align(cyc, LV_ALIGN_TOP_LEFT, 2, 32);
            }

            // Corner reference: modifier tag + F-key together (e.g. "^Sh F10"),
            // or the bare F-key alone for the no-modifier row. Blank cells
            // send their keystroke too, so they get the tag as well.
            lv_obj_t *fkey = lv_label_create(cell);
            char fkey_buf[16];
            if (MOD_TAG[row][0] != '\0') {
                snprintf(fkey_buf, sizeof(fkey_buf), "%s %s", MOD_TAG[row], FKEYS[col]);
            } else {
                snprintf(fkey_buf, sizeof(fkey_buf), "%s", FKEYS[col]);
            }
            lv_label_set_text(fkey, fkey_buf);
            lv_obj_set_style_text_font(fkey, &lv_font_montserrat_14, 0);
            lv_obj_set_style_text_color(fkey, txt, 0);
            lv_obj_set_style_text_opa(fkey, LV_OPA_70, 0);
            lv_obj_clear_flag(fkey, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_align(fkey, LV_ALIGN_BOTTOM_RIGHT, -4, -3);

            CELL_CTX[row][col].content = content;
            CELL_CTX[row][col].row = row;
            CELL_CTX[row][col].col = col;
            lv_obj_add_event_cb(cell, cell_event_cb, LV_EVENT_PRESSED, &CELL_CTX[row][col]);
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

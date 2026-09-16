/*
 * FLEET_WALL_COMPACT — ESP32-S3-Touch-LCD-7 fleet status display,
 * consolidated single-page layout (fork of fleet_wall: same networking/JSON
 * backend, replaced the paginated 4x2 tile UI with a dense 6xN grid that
 * fits the whole fleet on one screen, one stat bar per tile).
 * Base init sequence copied verbatim from Waveshare's official
 * examples/Arduino/examples/10_lvgl_v9_demo (esp-arduino-libs/ESP32_Display_Panel),
 * with lv_demo_widgets() replaced by fleet_ui_build()/fleet_ui_refresh().
 */

#include <Arduino.h>
#include <esp_display_panel.hpp>
#include <esp_err.h>

#include <lvgl.h>
#include <demos/lv_demos.h>

#include "esp_lv_adapter_arduino.h"

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

using namespace esp_panel::drivers;
using namespace esp_panel::board;

// Forward declaration: the Arduino builder auto-generates function
// prototypes near the top of the translation unit (before struct
// definitions further down), so any function taking a MachineData
// reference needs this in scope before that happens.
struct MachineData;

// LVGL's built-in Montserrat font only covers plain ASCII; fleet_api.py's
// detail strings use UTF-8 punctuation (e.g. a middle dot as a separator)
// that renders as an unsupported-glyph box. Replace any non-ASCII byte with
// '-' when copying text in from JSON so nothing renders as tofu.
static void strlcpy_ascii(char *dst, const char *src, size_t dst_size) {
    if (dst_size == 0) return;
    size_t i = 0;
    for (; src[i] != '\0' && i < dst_size - 1; i++) {
        unsigned char c = (unsigned char)src[i];
        dst[i] = (c < 0x80) ? (char)c : '-';
    }
    dst[i] = '\0';
}

#include "fleet_wall_secrets.h" // gitignored — copy from fleet_wall_secrets.h.example and fill in

// --- fill these in ---
static const char *WIFI_SSID       = FLEET_WALL_WIFI_SSID;
static const char *WIFI_PASS       = FLEET_WALL_WIFI_PASS;
static const char *FLEET_API_HOST  = "192.168.178.158"; // amsterdamdesktop's LAN IP (ESP32 has no Tailscale client)
static const uint16_t FLEET_API_PORT = 5010;
static const uint32_t POLL_INTERVAL_MS = 15000;

// ---------------------------------------------------------------------------
// Theme tokens (from the HTML mockup's CSS custom properties)
// ---------------------------------------------------------------------------
#define COL_BG        lv_color_hex(0x0a1011)
#define COL_PANEL     lv_color_hex(0x0f1719)
#define COL_PANEL2    lv_color_hex(0x0c1416)
#define COL_LINE      lv_color_hex(0x1e2f30)
#define COL_TEAL      lv_color_hex(0x35d6c1)
#define COL_OK        lv_color_hex(0x48d17a)
#define COL_WARN      lv_color_hex(0xf0a83c)
#define COL_CRIT      lv_color_hex(0xff6259)
#define COL_TEXT      lv_color_hex(0xdfeeec)
#define COL_TEXT_DIM  lv_color_hex(0x84a09c)
#define COL_TEXT_FAINT lv_color_hex(0x4d6663)

#define GRID_COLS 6      // consolidated layout: fixed 6-column grid, no pagination
#define GRID_ROWS 3      // 6x3 = 18 tiles -- covers the current ~13-host fleet with headroom
#define MAX_TILES (GRID_COLS * GRID_ROWS)
#define MAX_MACHINES 24  // cache size for the full fleet -- one tile per machine, no pages
#define MAX_SVCS 6       // services cached per machine (tile shows none, detail view shows all)
#define MAX_DISKS 12     // disks cached per machine, shown on the detail overlay
                         // (FleetNAS alone has ~8 volumes -- 4 was truncating it)

struct DiskInfo {
    char drive[10];
    float used_gb;
    float total_gb;
};

// One compact tile: host name, a single stat bar (CPU or MEM -- whichever's
// most relevant, see pick_stat() below), and a heart+status line.
// Deliberately just 5 LVGL objects/tile (card, host_label, stat_bar,
// stat_val, health_label) -- with up to MAX_TILES (24) of these on screen at
// once, the original 10-object-per-tile design (a stripe + wrapper rows for
// the bar and health line) blew LVGL's 64KB LV_MEM_SIZE pool, and
// lv_obj_create() doesn't null-check its own allocation: it silently wrote
// through a null pointer (Guru Meditation StoreProhibited @0x4200eb31,
// lv_obj_class_create_obj, 2026-09-17). The tile's left-edge status color
// is now the card's own left border instead of a separate stripe child.
struct FleetTile {
    lv_obj_t *card;
    lv_obj_t *host_label;
    lv_obj_t *ping_label;
    lv_obj_t *stat_bar;
    lv_obj_t *stat_val; // combined "CPU 42%" text
    lv_obj_t *health_label; // combined heart-symbol + "up"/"down" text
    int machine_idx; // index into machine_cache this tile currently shows, -1 if empty
};

// One machine's worth of display data, cached so page flips / detail taps
// don't need a re-fetch. Everything here now comes from a single /api/status
// fetch -- fleet_api.py's per-machine "machine_info" block (added since this
// firmware was first written) carries real cpu/ram/disk/OS-update data, so
// there's no need for the separate per-host /api/history polling this used to do.
struct MachineData {
    char name[28];
    char role[36];
    char tailscale_name[24];
    char status[12];
    int ping;
    bool has_minfo;
    int cpu_pct;         // -1 = no machine_info for this host (e.g. unreachable)
    int ram_pct;         // -1 = same
    float ram_used_gb, ram_total_gb;
    char os_build[24];
    char last_reboot[20];
    char last_wu_date[20];
    bool pending_reboot;
    long immich_photos, immich_videos; // -1 = not an Immich host
    int disk_count;
    DiskInfo disks[MAX_DISKS];
    int svc_count;
    char svc_name[MAX_SVCS][24];
    char svc_status[MAX_SVCS][10];
    char svc_detail[MAX_SVCS][72];
};

// Consolidated tiles show one stat bar, not both -- prefer whichever's
// present; when both are, CPU is the one that spikes/matters moment-to-moment,
// so it wins. Returns false (hide the row) only when neither is available.
static bool pick_stat(const MachineData &md, const char **label, int *pct) {
    if (md.cpu_pct >= 0) { *label = "CPU"; *pct = md.cpu_pct; return true; }
    if (md.ram_pct >= 0) { *label = "MEM"; *pct = md.ram_pct; return true; }
    return false;
}

static FleetTile tiles[MAX_TILES];
static lv_obj_t *hosts_chip;
static lv_obj_t *services_chip;
static lv_obj_t *footer_label;
static lv_obj_t *alert_rail;
static lv_obj_t *alert_label;

static MachineData machine_cache[MAX_MACHINES];
static int machine_count = 0;
static lv_obj_t *detail_overlay = nullptr;

// Networking runs on its own FreeRTOS task pinned to the opposite core from
// LVGL/rendering (see setup()) so a burst of blocking HTTP requests can't
// starve the RGB display driver's timing — this was the main cause of the
// ghosting/flicker seen when polling ran inline in loop() on the same core.
// This mutex protects machine_cache/machine_count from being read (by
// render_page/show_detail_overlay on the render core) while being written
// (by the network task on the other core).
static SemaphoreHandle_t cache_mutex = nullptr;

static void render_grid(void);
static void show_detail_overlay(int machine_idx);
static void close_detail_overlay(void);

static lv_color_t status_color(const char *status) {
    if (!status) return COL_TEXT_FAINT;
    if (strcmp(status, "up") == 0)   return COL_OK;
    if (strcmp(status, "down") == 0) return COL_CRIT;
    if (strcmp(status, "warn") == 0) return COL_WARN;
    return COL_TEXT_FAINT;
}

// Same red/amber/teal thresholds the mockup uses for its CPU/MEM bars.
static lv_color_t pct_color(int pct) {
    if (pct < 0)  return COL_TEXT_FAINT;
    if (pct >= 90) return COL_CRIT;
    if (pct >= 70) return COL_WARN;
    return COL_TEAL;
}

// Formats __DATE__ ("Sep 17 2026") + __TIME__ ("00:15:32") into a compact
// "V-2026.09.17.00.15" build stamp -- the original "Version: <date> <time>"
// text was wide enough to get clipped in this layout's tighter header.
static void format_build_version(char *out, size_t out_size) {
    static const char *months[] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    char mon[4] = {0};
    int day = 0, year = 0, hour = 0, min = 0, sec = 0;
    sscanf(__DATE__, "%3s %d %d", mon, &day, &year);
    sscanf(__TIME__, "%d:%d:%d", &hour, &min, &sec);
    int mnum = 1;
    for (int i = 0; i < 12; i++) if (strncmp(mon, months[i], 3) == 0) { mnum = i + 1; break; }
    snprintf(out, out_size, "V-%04d.%02d.%02d.%02d.%02d", year, mnum, day, hour, min);
}

static void tile_click_cb(lv_event_t *e) {
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (idx < machine_count) {
        show_detail_overlay(idx);
    }
}

// Manual recovery for the periodic flicker/reboot issue -- tapping this
// reboots the board outright rather than trying to redraw in place, since
// the flicker looks like a driver/timing-level RGB LCD issue that a
// same-process redraw likely wouldn't clear.
static void reset_btn_click_cb(lv_event_t *e) {
    Serial.println("[fleet_wall] manual reset requested");
    delay(100); // let the log line actually flush over serial
    ESP.restart();
}

// A "CPU [====    ] 42%" style row: fixed-width label, a bar that grows to
// fill the remaining space, and a fixed-width value on the right.
static void make_bar_row(lv_obj_t *parent, const char *label_text, lv_obj_t **row_out, lv_obj_t **bar_out, lv_obj_t **val_out, lv_obj_t **lbl_out = nullptr) {
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_set_size(row, LV_PCT(100), 20); // must clear the font's line height or glyphs clip into unreadable slivers
    lv_obj_set_style_bg_opa(row, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(row, 0, 0);
    lv_obj_set_style_pad_all(row, 0, 0);
    lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_clear_flag(row, LV_OBJ_FLAG_CLICKABLE); // let taps pass through to the tile card / overlay behind it
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 6, 0);

    lv_obj_t *lbl = lv_label_create(row);
    lv_label_set_text(lbl, label_text);
    lv_obj_set_style_text_font(lbl, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(lbl, COL_TEXT_FAINT, 0);
    lv_obj_set_width(lbl, 36); // wide enough for "CPU"/"MEM" at 14px; clip rather than wrap if it's ever too tight
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_CLIP);

    lv_obj_t *bar = lv_bar_create(row);
    lv_obj_clear_flag(bar, LV_OBJ_FLAG_CLICKABLE); // lv_bar is clickable by default -- same passthrough reason
    lv_obj_set_flex_grow(bar, 1);
    lv_obj_set_height(bar, 6);
    lv_obj_set_style_bg_color(bar, COL_LINE, LV_PART_MAIN);
    lv_obj_set_style_border_width(bar, 0, 0);
    lv_obj_set_style_bg_color(bar, COL_TEAL, LV_PART_INDICATOR);
    lv_bar_set_range(bar, 0, 100);
    lv_bar_set_value(bar, 0, LV_ANIM_OFF);

    lv_obj_t *val = lv_label_create(row);
    lv_label_set_text(val, "--");
    lv_obj_set_style_text_font(val, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(val, COL_TEXT, 0);
    lv_obj_set_width(val, 34);
    lv_obj_set_height(val, 18); // fixed height + CLIP below: callers widen this for longer
    lv_label_set_long_mode(val, LV_LABEL_LONG_CLIP); // text ("6904/14873G") without it wrapping
    lv_obj_set_style_text_align(val, LV_TEXT_ALIGN_RIGHT, 0);          // into (and overlapping) the row below

    *row_out = row;
    *bar_out = bar;
    *val_out = val;
    if (lbl_out) *lbl_out = lbl;
}

void fleet_ui_build(void) {
    for (int i = 0; i < MAX_MACHINES; i++) {
        machine_cache[i].has_minfo = false;
        machine_cache[i].cpu_pct = -1;
        machine_cache[i].ram_pct = -1;
        machine_cache[i].immich_photos = -1;
        machine_cache[i].immich_videos = -1;
    }

    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, COL_BG, 0);
    lv_obj_set_style_pad_all(scr, 0, 0);
    lv_obj_set_flex_flow(scr, LV_FLEX_FLOW_COLUMN);

    lv_obj_t *top = lv_obj_create(scr);
    lv_obj_set_size(top, LV_PCT(100), 40);
    lv_obj_set_style_bg_color(top, COL_PANEL2, 0);
    lv_obj_set_style_border_width(top, 0, 0);
    lv_obj_set_style_radius(top, 0, 0);
    lv_obj_set_flex_flow(top, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(top, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(top, 14, 0);
    lv_obj_set_style_pad_left(top, 14, 0);

    lv_obj_t *brand = lv_label_create(top);
    lv_label_set_text(brand, "FLEET_WALL - CONSOLIDATED");
    lv_obj_set_style_text_color(brand, COL_TEAL, 0);
    lv_obj_set_style_text_font(brand, &lv_font_montserrat_14, 0);

    // Host/service totals used to live here too, duplicating the footer's
    // "UP n DOWN n" -- dropped 2026-09-17 to free up header space for the
    // reset button (their unbounded-width text had been pushing it off the
    // right edge of the screen entirely). hosts_chip/services_chip remain as
    // hidden objects so fleet_ui_refresh()'s existing update calls are cheap
    // no-ops rather than needing every call site touched.
    hosts_chip = lv_label_create(top);
    lv_obj_add_flag(hosts_chip, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(hosts_chip, LV_OBJ_FLAG_IGNORE_LAYOUT);
    lv_obj_set_size(hosts_chip, 0, 0);

    services_chip = lv_label_create(top);
    lv_obj_add_flag(services_chip, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(services_chip, LV_OBJ_FLAG_IGNORE_LAYOUT);
    lv_obj_set_size(services_chip, 0, 0);

    // pushes the reset button to the far right of the header
    lv_obj_t *spacer = lv_obj_create(top);
    lv_obj_set_style_bg_opa(spacer, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(spacer, 0, 0);
    lv_obj_clear_flag(spacer, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_clear_flag(spacer, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_grow(spacer, 1);
    lv_obj_set_height(spacer, 1);

    // Compile timestamp, so it's possible to tell at a glance whether a
    // flash actually took (2026-09-16: several confusing minutes were spent
    // unsure whether new firmware was really running after an upload that
    // reported an ambiguous error). __DATE__/__TIME__ are filled in by the
    // compiler automatically -- no manual version bump to forget.
    lv_obj_t *build_label = lv_label_create(top);
    char build_buf[24];
    format_build_version(build_buf, sizeof(build_buf));
    lv_label_set_text(build_label, build_buf);
    lv_obj_set_style_text_color(build_label, COL_TEXT_FAINT, 0);
    lv_obj_set_style_text_font(build_label, &lv_font_montserrat_14, 0);
    // Same bug class as the CPU/MEM/disk value labels earlier tonight: without
    // a fixed width + long-mode, LVGL word-wraps this onto a second line,
    // which overflows the header's fixed 40px height (the "top line wrapped
    // to bottom" / flicker reported right after adding this label).
    lv_obj_set_width(build_label, 150);
    lv_obj_set_height(build_label, 18);
    lv_label_set_long_mode(build_label, LV_LABEL_LONG_CLIP);

    lv_obj_t *reset_btn = lv_label_create(top);
    lv_label_set_text(reset_btn, LV_SYMBOL_REFRESH);
    lv_obj_set_style_text_color(reset_btn, COL_TEXT_FAINT, 0);
    lv_obj_set_style_pad_all(reset_btn, 8, 0); // bigger tap target than the glyph itself
    lv_obj_add_flag(reset_btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(reset_btn, reset_btn_click_cb, LV_EVENT_CLICKED, nullptr);

    alert_rail = lv_obj_create(scr);
    lv_obj_set_size(alert_rail, LV_PCT(100), 24);
    lv_obj_set_style_bg_color(alert_rail, lv_color_hex(0x1c0f0e), 0);
    lv_obj_set_style_border_width(alert_rail, 0, 0);
    lv_obj_set_style_radius(alert_rail, 0, 0);
    lv_obj_add_flag(alert_rail, LV_OBJ_FLAG_HIDDEN);
    alert_label = lv_label_create(alert_rail);
    lv_obj_set_style_text_color(alert_label, lv_color_hex(0xffb3ac), 0);
    lv_obj_align(alert_label, LV_ALIGN_LEFT_MID, 10, 0);

    static lv_coord_t col_dsc[GRID_COLS + 1];
    static lv_coord_t row_dsc[GRID_ROWS + 1];
    for (int c = 0; c < GRID_COLS; c++) col_dsc[c] = LV_GRID_FR(1);
    col_dsc[GRID_COLS] = LV_GRID_TEMPLATE_LAST;
    for (int r = 0; r < GRID_ROWS; r++) row_dsc[r] = LV_GRID_FR(1);
    row_dsc[GRID_ROWS] = LV_GRID_TEMPLATE_LAST;

    lv_obj_t *grid = lv_obj_create(scr);
    lv_obj_set_width(grid, LV_PCT(100));
    lv_obj_set_flex_grow(grid, 1);
    lv_obj_set_grid_dsc_array(grid, col_dsc, row_dsc);
    lv_obj_set_style_bg_color(grid, COL_LINE, 0);
    lv_obj_set_style_pad_all(grid, 1, 0);
    lv_obj_set_style_pad_gap(grid, 1, 0);
    lv_obj_set_style_border_width(grid, 0, 0);
    lv_obj_set_style_radius(grid, 0, 0);

    // Each tile is much smaller than fleet_wall's original 4x2 design -- host
    // name, one stat bar (CPU or MEM, see pick_stat()), one status row -- so
    // all up to MAX_TILES machines fit on a single, non-paginated screen.
    for (int i = 0; i < MAX_TILES; i++) {
        int col = i % GRID_COLS, row = i / GRID_COLS;
        FleetTile &t = tiles[i];

        t.machine_idx = -1;

        t.card = lv_obj_create(grid);
        lv_obj_set_grid_cell(t.card, LV_GRID_ALIGN_STRETCH, col, 1, LV_GRID_ALIGN_STRETCH, row, 1);
        lv_obj_set_style_bg_color(t.card, COL_PANEL, 0);
        // Status color is a left border on the card itself instead of a
        // separate stripe child object -- one fewer LVGL object per tile.
        lv_obj_set_style_border_width(t.card, 3, 0);
        lv_obj_set_style_border_side(t.card, LV_BORDER_SIDE_LEFT, 0);
        lv_obj_set_style_border_color(t.card, COL_TEXT_FAINT, 0);
        lv_obj_set_style_radius(t.card, 0, 0);
        lv_obj_set_style_pad_all(t.card, 6, 0);
        lv_obj_set_flex_flow(t.card, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_style_pad_row(t.card, 3, 0);
        lv_obj_clear_flag(t.card, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_flag(t.card, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(t.card, tile_click_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);

        t.host_label = lv_label_create(t.card);
        lv_obj_set_style_text_color(t.host_label, COL_TEXT, 0);
        lv_obj_set_style_text_font(t.host_label, &lv_font_montserrat_14, 0);
        lv_label_set_text(t.host_label, "-");
        lv_obj_set_width(t.host_label, LV_PCT(100));
        lv_obj_set_height(t.host_label, 18);
        lv_label_set_long_mode(t.host_label, LV_LABEL_LONG_DOT); // long host names truncate, don't wrap into the bar row

        // Ping time gets its own line -- sharing the host name line clipped
        // it off (2026-09-17), and the 3-row grid has the vertical room now.
        t.ping_label = lv_label_create(t.card);
        lv_obj_set_style_text_font(t.ping_label, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(t.ping_label, COL_TEXT_FAINT, 0);
        lv_label_set_text(t.ping_label, "");

        // One bar (CPU or MEM, see pick_stat()) with its "CPU 42%" label
        // underneath -- no wrapper row object, just two flex children.
        t.stat_bar = lv_bar_create(t.card);
        lv_obj_clear_flag(t.stat_bar, LV_OBJ_FLAG_CLICKABLE); // lv_bar is clickable by default -- let taps pass through to the card
        lv_obj_set_size(t.stat_bar, LV_PCT(100), 6);
        lv_obj_set_style_bg_color(t.stat_bar, COL_LINE, LV_PART_MAIN);
        lv_obj_set_style_border_width(t.stat_bar, 0, 0);
        lv_obj_set_style_bg_color(t.stat_bar, COL_TEAL, LV_PART_INDICATOR);
        lv_bar_set_range(t.stat_bar, 0, 100);
        lv_bar_set_value(t.stat_bar, 0, LV_ANIM_OFF);

        t.stat_val = lv_label_create(t.card);
        lv_obj_set_style_text_font(t.stat_val, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(t.stat_val, COL_TEXT_DIM, 0);
        lv_label_set_text(t.stat_val, "");

        // Bottom line: a heart glyph + "up"/"down" text combined into one
        // label (not a row of two) -- the mockup's compact replacement for
        // the old role/detail lines that don't fit in a tile this small.
        t.health_label = lv_label_create(t.card);
        lv_obj_set_style_text_font(t.health_label, &lv_font_montserrat_14, 0);
        lv_label_set_text(t.health_label, "");
    }

    lv_obj_t *bottom = lv_obj_create(scr);
    lv_obj_set_size(bottom, LV_PCT(100), 22);
    lv_obj_set_style_bg_color(bottom, COL_PANEL2, 0);
    lv_obj_set_style_border_width(bottom, 0, 0);
    lv_obj_set_style_radius(bottom, 0, 0);
    lv_obj_clear_flag(bottom, LV_OBJ_FLAG_SCROLLABLE);

    footer_label = lv_label_create(bottom);
    lv_label_set_text(footer_label, "PAGE 1/1 (Consolidated)");
    lv_obj_set_style_text_color(footer_label, COL_TEXT_FAINT, 0);
    lv_obj_set_style_text_font(footer_label, &lv_font_montserrat_14, 0);
    lv_obj_align(footer_label, LV_ALIGN_LEFT_MID, 10, 0);
}

void fleet_ui_refresh(JsonDocument &doc) {
    JsonObject summary = doc["summary"];
    int m_up = summary["machines_up"] | 0;
    int m_total = summary["machines_total"] | 0;
    int s_up = summary["services_up"] | 0;
    int s_total = summary["services_total"] | 0;

    int m_down = m_total - m_up;

    // Host/service totals live only in the footer now (used to be duplicated
    // in the header too -- see fleet_ui_build()).
    char footer_buf[80];
    snprintf(footer_buf, sizeof(footer_buf), "PAGE 1/1 (Consolidated)  HOSTS %d/%d  SERVICES %d/%d  UP %d  DOWN %d",
             m_up, m_total, s_up, s_total, m_up, m_down);
    lv_label_set_text(footer_label, footer_buf);

    bool has_alert = (m_up < m_total) || (s_up < s_total);
    if (has_alert) {
        lv_obj_clear_flag(alert_rail, LV_OBJ_FLAG_HIDDEN);
        char alert_buf[24];
        snprintf(alert_buf, sizeof(alert_buf), "%d HOST(S) DOWN", m_down);
        lv_label_set_text(alert_label, alert_buf);
    } else {
        lv_obj_add_flag(alert_rail, LV_OBJ_FLAG_HIDDEN);
    }

    // Cache every machine (not just the first 8) so render_page() can flip
    // through the whole fleet without needing another fetch.
    xSemaphoreTake(cache_mutex, portMAX_DELAY);
    JsonArray machines = doc["machines"];
    machine_count = 0;
    for (JsonObject m : machines) {
        if (machine_count >= MAX_MACHINES) break;
        MachineData &md = machine_cache[machine_count];

        strlcpy_ascii(md.name, m["machine"]["display_name"] | "?", sizeof(md.name));
        strlcpy_ascii(md.role, m["machine"]["primary_role"] | "", sizeof(md.role));
        strlcpy(md.tailscale_name, m["machine"]["tailscale_name"] | "", sizeof(md.tailscale_name));
        strlcpy(md.status, m["host"]["status"] | "unknown", sizeof(md.status));
        md.ping = m["host"]["response_time_ms"] | -1;

        JsonObject minfo = m["machine_info"];
        if (!minfo.isNull()) {
            md.has_minfo = true;
            md.cpu_pct = minfo["cpu_percent"] | -1;
            md.ram_used_gb = minfo["ram_used_gb"] | -1.0;
            md.ram_total_gb = minfo["ram_total_gb"] | -1.0;
            md.ram_pct = (md.ram_total_gb > 0) ? (int)((md.ram_used_gb / md.ram_total_gb) * 100.0f + 0.5f) : -1;
            strlcpy(md.os_build, minfo["os_build"] | "", sizeof(md.os_build));
            strlcpy(md.last_reboot, minfo["last_reboot"] | "", sizeof(md.last_reboot));
            strlcpy(md.last_wu_date, minfo["last_wu_date"] | "", sizeof(md.last_wu_date));
            md.pending_reboot = minfo["pending_reboot"] | false;
            md.immich_photos = minfo["immich_photos"] | -1;
            md.immich_videos = minfo["immich_videos"] | -1;

            md.disk_count = 0;
            JsonArray disks = minfo["disks"];
            for (JsonObject d : disks) {
                if (md.disk_count >= MAX_DISKS) break;
                DiskInfo &dk = md.disks[md.disk_count];
                strlcpy(dk.drive, d["drive"] | "", sizeof(dk.drive));
                dk.used_gb = d["used_gb"] | 0.0;
                dk.total_gb = d["total_gb"] | 0.0;
                md.disk_count++;
            }
        } else {
            md.has_minfo = false;
            md.cpu_pct = -1;
            md.ram_pct = -1;
            md.disk_count = 0;
            md.pending_reboot = false;
            md.os_build[0] = md.last_reboot[0] = md.last_wu_date[0] = '\0';
            md.immich_photos = md.immich_videos = -1;
        }

        JsonArray services = m["services"];
        md.svc_count = 0;
        for (JsonObject svc : services) {
            if (md.svc_count >= MAX_SVCS) break;
            int si = md.svc_count;
            strlcpy_ascii(md.svc_name[si], svc["name"] | "", sizeof(md.svc_name[si]));
            strlcpy(md.svc_status[si], svc["tailscale_check"]["status"] | "unknown", sizeof(md.svc_status[si]));
            strlcpy_ascii(md.svc_detail[si], svc["tailscale_check"]["detail"] | "", sizeof(md.svc_detail[si]));
            md.svc_count++;
        }

        machine_count++;
    }
    xSemaphoreGive(cache_mutex);

    ESP_ERROR_CHECK(esp_lv_adapter_lock(-1));
    render_grid();
    esp_lv_adapter_unlock();
}

// Paints tiles[] from machine_cache[] -- every cached machine gets one tile,
// no pagination. No network needed, so this could also run on a plain timer
// if a future change wants the grid to refresh between polls.
static void render_grid(void) {
    xSemaphoreTake(cache_mutex, portMAX_DELAY);

    for (int slot = 0; slot < MAX_TILES; slot++) {
        FleetTile &t = tiles[slot];

        if (slot >= machine_count) {
            // no machine for this tile -> blank it out entirely, including
            // hiding the stat bar rather than showing an empty one
            t.machine_idx = -1;
            lv_label_set_text(t.host_label, "");
            lv_label_set_text(t.ping_label, "");
            lv_label_set_text(t.health_label, "");
            lv_label_set_text(t.stat_val, "");
            lv_obj_add_flag(t.stat_bar, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_style_border_color(t.card, COL_BG, 0); // matches the tile bg -> the border disappears too
            continue;
        }

        t.machine_idx = slot;
        MachineData &md = machine_cache[slot];

        lv_label_set_text(t.host_label, md.name);
        if (md.ping >= 0) {
            char ping_buf[16];
            snprintf(ping_buf, sizeof(ping_buf), "%dms", md.ping);
            lv_label_set_text(t.ping_label, ping_buf);
        } else {
            lv_label_set_text(t.ping_label, "");
        }

        lv_color_t sc = status_color(md.status);
        lv_obj_set_style_border_color(t.card, sc, 0);
        bool is_up = strcmp(md.status, "up") == 0;
        char health_buf[16];
        snprintf(health_buf, sizeof(health_buf), "%s %s", is_up ? LV_SYMBOL_OK : LV_SYMBOL_WARNING, md.status);
        lv_label_set_text(t.health_label, health_buf);
        lv_obj_set_style_text_color(t.health_label, sc, 0);

        // One stat bar per tile (CPU or MEM, whichever's available) -- hidden
        // entirely rather than showing an empty bar when neither is (e.g.
        // the host is unreachable).
        const char *stat_lbl;
        int stat_pct;
        if (pick_stat(md, &stat_lbl, &stat_pct)) {
            lv_obj_clear_flag(t.stat_bar, LV_OBJ_FLAG_HIDDEN);
            lv_bar_set_value(t.stat_bar, stat_pct, LV_ANIM_OFF);
            lv_obj_set_style_bg_color(t.stat_bar, pct_color(stat_pct), LV_PART_INDICATOR);
            char pct_buf[16];
            snprintf(pct_buf, sizeof(pct_buf), "%s %d%%", stat_lbl, stat_pct);
            lv_label_set_text(t.stat_val, pct_buf);
        } else {
            lv_obj_add_flag(t.stat_bar, LV_OBJ_FLAG_HIDDEN);
            lv_label_set_text(t.stat_val, "");
        }
    }

    xSemaphoreGive(cache_mutex);
}

static void poll_fleet_status(void) {
    if (WiFi.status() != WL_CONNECTED) return;

    HTTPClient http;
    char url[128];
    snprintf(url, sizeof(url), "http://%s:%u/api/status", FLEET_API_HOST, FLEET_API_PORT);
    http.begin(url);
    // /api/status now carries a machine_info block per host (~17.5KB total for
    // 13 hosts, confirmed 2026-09-15) -- 4s was enough for the old services-only
    // payload but timed out (-11) on this larger one.
    http.setTimeout(10000);

    int code = http.GET();
    if (code == 200) {
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, http.getStream());
        if (!err) {
            fleet_ui_refresh(doc); // locks the LVGL adapter + cache mutex internally
        } else {
            Serial.printf("[fleet_wall] JSON parse error: %s\n", err.c_str());
        }
    } else {
        Serial.printf("[fleet_wall] GET %s -> %d\n", url, code);
    }
    http.end();
}

static void overlay_click_cb(lv_event_t *e) {
    close_detail_overlay();
    // Full repaint of the tile grid now revealed behind the closed overlay —
    // same experiment as the page-switch invalidate in loop().
    lv_obj_invalidate(lv_scr_act());
}

static void close_detail_overlay(void) {
    if (detail_overlay != nullptr) {
        // lv_obj_del_async, not lv_obj_del: this is called from the overlay's
        // own CLICKED handler, and LVGL corrupts its event-processing loop if
        // an object is deleted synchronously from inside its own event
        // callback (this was the crash-on-close / random-reboot bug).
        lv_obj_del_async(detail_overlay);
        detail_overlay = nullptr;
    }
}

// Full-screen panel for one host: every cached service, untruncated, plus
// live CPU/MEM. Tapping anywhere on it closes it. Built on lv_layer_top()
// so it floats above the tile grid without disturbing it underneath.
static void show_detail_overlay(int machine_idx) {
    xSemaphoreTake(cache_mutex, portMAX_DELAY);
    if (machine_idx < 0 || machine_idx >= machine_count) {
        xSemaphoreGive(cache_mutex);
        return;
    }
    close_detail_overlay();
    MachineData &md = machine_cache[machine_idx]; // read under cache_mutex for the rest of this function

    detail_overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(detail_overlay, LV_PCT(100), LV_PCT(100));
    lv_obj_set_style_bg_color(detail_overlay, COL_BG, 0);
    lv_obj_set_style_bg_opa(detail_overlay, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(detail_overlay, 0, 0);
    lv_obj_set_style_radius(detail_overlay, 0, 0);
    lv_obj_set_style_pad_all(detail_overlay, 20, 0);
    lv_obj_set_flex_flow(detail_overlay, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(detail_overlay, 8, 0);
    lv_obj_add_flag(detail_overlay, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(detail_overlay, overlay_click_cb, LV_EVENT_CLICKED, nullptr);

    lv_color_t sc = status_color(md.status);

    lv_obj_t *header = lv_label_create(detail_overlay);
    char header_buf[48];
    if (md.ping >= 0) snprintf(header_buf, sizeof(header_buf), "%s  %dms", md.name, md.ping);
    else snprintf(header_buf, sizeof(header_buf), "%s", md.name);
    lv_label_set_text(header, header_buf);
    lv_obj_set_style_text_color(header, COL_TEXT, 0);
    lv_obj_set_style_text_font(header, &lv_font_montserrat_14, 0);

    lv_obj_t *role = lv_label_create(detail_overlay);
    lv_label_set_text(role, md.role);
    lv_obj_set_style_text_color(role, COL_TEXT_FAINT, 0);

    lv_obj_t *health = lv_label_create(detail_overlay);
    char health_buf[24];
    snprintf(health_buf, sizeof(health_buf), "HEALTH %s", md.status);
    lv_label_set_text(health, health_buf);
    lv_obj_set_style_text_color(health, sc, 0);

    // CPU/MEM/disk bars, full width this time -- hidden per-row when this
    // host has no machine_info (e.g. unreachable) rather than showing empty.
    if (md.cpu_pct >= 0) {
        lv_obj_t *cpu_row, *cpu_bar, *cpu_val;
        make_bar_row(detail_overlay, "CPU", &cpu_row, &cpu_bar, &cpu_val);
        char pct_buf[8];
        snprintf(pct_buf, sizeof(pct_buf), "%d%%", md.cpu_pct);
        lv_label_set_text(cpu_val, pct_buf);
        lv_bar_set_value(cpu_bar, md.cpu_pct, LV_ANIM_OFF);
        lv_obj_set_style_bg_color(cpu_bar, pct_color(md.cpu_pct), LV_PART_INDICATOR);
    }
    if (md.ram_pct >= 0) {
        lv_obj_t *mem_row, *mem_bar, *mem_val;
        make_bar_row(detail_overlay, "MEM", &mem_row, &mem_bar, &mem_val);
        char val_buf[24];
        snprintf(val_buf, sizeof(val_buf), "%.1f/%.0fG", md.ram_used_gb, md.ram_total_gb);
        lv_label_set_text(mem_val, val_buf);
        lv_obj_set_width(mem_val, 90); // wide enough for "125.6/125.6G" on the biggest box
        lv_bar_set_value(mem_bar, md.ram_pct, LV_ANIM_OFF);
        lv_obj_set_style_bg_color(mem_bar, pct_color(md.ram_pct), LV_PART_INDICATOR);
    }
    for (int i = 0; i < md.disk_count; i++) {
        DiskInfo &dk = md.disks[i];
        if (dk.total_gb <= 0) continue;
        int dpct = (int)((dk.used_gb / dk.total_gb) * 100.0f + 0.5f);
        lv_obj_t *d_row, *d_bar, *d_val;
        make_bar_row(detail_overlay, dk.drive, &d_row, &d_bar, &d_val);
        char val_buf[24];
        snprintf(val_buf, sizeof(val_buf), "%.0f/%.0fG", dk.used_gb, dk.total_gb);
        lv_label_set_text(d_val, val_buf);
        lv_obj_set_width(d_val, 100); // wide enough for FleetNAS's "6904/14873G" volumes
        lv_bar_set_value(d_bar, dpct, LV_ANIM_OFF);
        lv_obj_set_style_bg_color(d_bar, pct_color(dpct), LV_PART_INDICATOR);
    }

    // OS/update/reboot footer -- only shown for hosts machine_info covers
    if (md.has_minfo) {
        lv_obj_t *sysinfo = lv_label_create(detail_overlay);
        char sysinfo_buf[80];
        snprintf(sysinfo_buf, sizeof(sysinfo_buf), "OS %s  -  reboot %s  -  WU %s",
                 md.os_build[0] ? md.os_build : "-",
                 md.last_reboot[0] ? md.last_reboot : "-",
                 md.last_wu_date[0] ? md.last_wu_date : "-");
        lv_label_set_text(sysinfo, sysinfo_buf);
        lv_obj_set_style_text_color(sysinfo, COL_TEXT_FAINT, 0);
        lv_obj_set_style_text_font(sysinfo, &lv_font_montserrat_14, 0);

        if (md.pending_reboot) {
            lv_obj_t *reboot_warn = lv_label_create(detail_overlay);
            lv_label_set_text(reboot_warn, "PENDING REBOOT");
            lv_obj_set_style_text_color(reboot_warn, COL_WARN, 0);
        }

        if (md.immich_photos >= 0) {
            lv_obj_t *immich = lv_label_create(detail_overlay);
            char immich_buf[48];
            snprintf(immich_buf, sizeof(immich_buf), "Immich: %ld photos, %ld videos", md.immich_photos, md.immich_videos);
            lv_label_set_text(immich, immich_buf);
            lv_obj_set_style_text_color(immich, COL_TEXT_DIM, 0);
        }
    }

    lv_obj_t *divider = lv_obj_create(detail_overlay);
    lv_obj_set_size(divider, LV_PCT(100), 1);
    lv_obj_set_style_bg_color(divider, COL_LINE, 0);
    lv_obj_set_style_border_width(divider, 0, 0);
    lv_obj_clear_flag(divider, LV_OBJ_FLAG_CLICKABLE); // let taps on it still close the overlay

    for (int i = 0; i < md.svc_count; i++) {
        lv_obj_t *row = lv_obj_create(detail_overlay);
        lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
        lv_obj_set_style_bg_opa(row, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(row, 0, 0);
        lv_obj_set_style_pad_all(row, 0, 0);
        lv_obj_clear_flag(row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_clear_flag(row, LV_OBJ_FLAG_CLICKABLE); // tapping anywhere on a service row still closes the overlay
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START);

        lv_obj_t *name = lv_label_create(row);
        lv_label_set_text(name, md.svc_name[i]);
        lv_obj_set_style_text_color(name, COL_TEXT, 0);

        lv_obj_t *detail = lv_label_create(row);
        lv_label_set_text(detail, md.svc_detail[i][0] ? md.svc_detail[i] : md.svc_status[i]);
        lv_obj_set_style_text_color(detail, status_color(md.svc_status[i]), 0);
        lv_label_set_long_mode(detail, LV_LABEL_LONG_WRAP);
        lv_obj_set_width(detail, LV_PCT(60));
        lv_obj_set_style_text_align(detail, LV_TEXT_ALIGN_RIGHT, 0);
    }

    lv_obj_t *hint = lv_label_create(detail_overlay);
    lv_label_set_text(hint, "tap anywhere to close");
    lv_obj_set_style_text_color(hint, COL_TEXT_FAINT, 0);
    lv_obj_align(hint, LV_ALIGN_BOTTOM_LEFT, 0, 0);

    // Full repaint of the new overlay -- same experiment as the other
    // transition points above.
    lv_obj_invalidate(detail_overlay);

    xSemaphoreGive(cache_mutex);
}

static void fleet_wifi_connect(void) {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.printf("[fleet_wall] connecting to %s", WIFI_SSID);
    uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
        delay(400);
        Serial.print(".");
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[fleet_wall] connected, IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("\n[fleet_wall] WiFi connect timed out, will retry");
    }
}

// All networking (WiFi + the /api/status and /api/history HTTP calls) runs
// here, pinned to core 0 -- the opposite core from LVGL rendering (core 1,
// see ARDUINO_RUNNING_CORE in setup()). Running it inline in loop() on the
// same core as the render task was starving the RGB display driver's timing
// during poll bursts, producing the ghosting/flicker seen 2026-09-15.
static void net_task(void *pvParameters) {
    fleet_wifi_connect();
    for (;;) {
        if (WiFi.status() != WL_CONNECTED) {
            fleet_wifi_connect();
        }
        poll_fleet_status();
        vTaskDelay(pdMS_TO_TICKS(POLL_INTERVAL_MS));
    }
}

void setup()
{
    Serial.begin(115200);
    Serial.println("FLEET_WALL_COMPACT start");

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
        // Waveshare's troubleshooting doc calls this ghosting/tearing pattern
        // "screen drift" on ESP32-S3 RGB LCDs and recommends a bigger bounce
        // buffer as the first fix; their base example used *10.
        static_cast<BusRGB *>(lcd_bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 20);
    }

    assert(board->begin());

    esp_lv_adapter_config_t adapter_config = ESP_LV_ADAPTER_DEFAULT_CONFIG();
    // Bumped 12K -> 18K: show_detail_overlay() (built on this task) grew a lot
    // once it started rendering per-disk bars and OS/reboot text.
    adapter_config.task_stack_size = 18 * 1024;
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

    cache_mutex = xSemaphoreCreateMutex();

    ESP_ERROR_CHECK(esp_lv_adapter_lock(-1));
    fleet_ui_build();
    esp_lv_adapter_unlock();

    // Pin networking to the core opposite the render task (ARDUINO_RUNNING_CORE,
    // set above as the LVGL adapter's task_core_id) so HTTP request bursts
    // can't stall the RGB display driver's timing.
    // Stack bumped 8192 -> 20480: the machine_info-based /api/status payload
    // (~17.5KB) and its parsing/formatting call chain (fleet_ui_refresh's
    // nested loops, JsonDocument, HTTPClient/WiFiClient internals) overflowed
    // the smaller stack, causing the periodic crash/auto-reboot seen 2026-09-15.
    //
    // Priority dropped 1 -> 0 (tskIDLE_PRIORITY) 2026-09-16: confirmed via
    // serial log that this task was triggering the ESP-IDF task watchdog
    // ("IDLE0 did not reset the watchdog... CPU 0: fleet_net") and rebooting
    // the board. At priority 1 -- one above idle -- a long enough
    // continuous CPU-bound stretch (deserializing the ~17.5KB JSON with no
    // yield point) can never be preempted by IDLE0 on the same core, so the
    // idle task never gets to "check in" with its own watchdog. Priority 0
    // makes fleet_net round-robin with the idle task instead of blocking it
    // outright. This is the ONE change from this round of investigation --
    // being tested in isolation before anything else is touched.
    xTaskCreatePinnedToCore(net_task, "fleet_net", 20480, nullptr, tskIDLE_PRIORITY, nullptr,
                             (ARDUINO_RUNNING_CORE == 0) ? 1 : 0);

    Serial.println("FLEET_WALL_COMPACT ready");
}

void loop()
{
    // Consolidated layout has no pagination -- networking (net_task) drives
    // every redraw via fleet_ui_refresh()/render_grid(), so loop() has
    // nothing left to do.
    delay(200);
}

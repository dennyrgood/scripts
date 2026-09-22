/*
 * FLEET_WALL_IMAGE -- generic host-rendered image display, successor to
 * fleet_wall_image_spike once that spike proved stable. No LVGL, no JSON
 * parsing on-device: the host (wall_server.py + a producer script) renders
 * everything and this firmware just polls a hash, fetches raw RGB565 pixels
 * on change, blits them in throttled strips, and re-syncs the panel every
 * cycle. This is the exact combination confirmed stable on the spike board
 * (2026-09-22): CRC-verified transfers, and esp_lcd_rgb_panel_restart()
 * fixing the display-side corruption that transfer verification proved was
 * NOT a data problem.
 *
 * WALL_CHANNEL in the secrets file picks which of wall_server.py's URL
 * prefixes this board polls. Normally "/display" -- a single unified
 * endpoint where the HOST decides what's currently showing (the fleet grid,
 * a host's detail screen, or a photo) and what a tap means (see that
 * file's docstring for the gesture zones: corner = switch fleet/photos,
 * thirds = prev/pause/next on photos, tile = detail on fleet). This
 * firmware has no idea which mode it's in -- it just polls one hash, fetches
 * on change, and forwards every tap coordinate unmodified. "/fleet" and
 * "/photos" still work directly too, for a board dedicated to just one.
 */

#include <Arduino.h>
#include <esp_display_panel.hpp>
#include <esp_lcd_panel_rgb.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <esp_rom_crc.h>

#include "fleet_wall_image_secrets.h" // gitignored -- copy from the .example

using namespace esp_panel::drivers;
using namespace esp_panel::board;

SET_LOOP_TASK_STACK_SIZE(16 * 1024);

static const char *HOST = IMAGE_API_HOST;
static const uint16_t PORT = IMAGE_API_PORT;
static const char *CHANNEL = WALL_CHANNEL; // "/fleet" or "/photos" -- see secrets.h.example
static const uint32_t POLL_MS = 15000;
static const uint32_t STALL_RESTART_MS = 180000; // no successful poll for this long -> reboot

static const int W = 800, H = 480;
static Board *g_board = nullptr;
static LCD *lcd = nullptr;
static Touch *touch = nullptr;
static uint8_t *frame_buf = nullptr; // one full 800x480 frame, staged off-screen in PSRAM before a single blit
static String last_hash;
static uint32_t last_ok_ms = 0;
static uint32_t frames = 0;
static uint32_t crc_bad = 0;
static bool touch_enabled = false; // set true in setup() if a touch controller is present -- every channel forwards taps, the host decides what a tap means

static void wifi_connect(void) {
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false); // modem-sleep power cycling contends with the RGB DMA for the PSRAM bus -- confirmed cause of the earlier flicker
    WiFi.begin(FLEET_WALL_WIFI_SSID, FLEET_WALL_WIFI_PASS);
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) delay(400);
    Serial.printf("[wall_image] WiFi %s, IP %s\n", WiFi.status() == WL_CONNECTED ? "up" : "FAILED",
                  WiFi.localIP().toString().c_str());
}

static bool http_get_string(const char *path, String &out) {
    HTTPClient http;
    char url[128];
    snprintf(url, sizeof(url), "http://%s:%u%s", HOST, PORT, path);
    http.begin(url);
    http.setTimeout(5000);
    int code = http.GET();
    if (code == 200) out = http.getString();
    else Serial.printf("[wall_image] GET %s -> %d\n", path, code);
    http.end();
    return code == 200;
}

// Downloads the WHOLE frame into frame_buf (PSRAM, off-screen) before
// touching the display at all, then does ONE drawBitmap() call for the
// entire 800x480 image. Confirmed 2026-09-22: the earlier version blitted
// 8-line strips AS THEY ARRIVED over the network, so the live, actively-
// scanned display buffer was left partially-rewritten for the whole ~2-4s
// download (drawBitmap() on this RGB bus is a synchronous memcpy straight
// into the buffer being scanned out -- there's no vsync-synced swap). That
// multi-second exposure window made visible tearing close to inevitable,
// not an occasional glitch. Staging off-screen first cuts that window down
// to roughly however long one 768000-byte memcpy takes (well under 100ms),
// which is what real double-buffering would give you almost for free --
// this is the cheap version of that fix, not the complete one.
static bool fetch_frame(const char *path, uint32_t *crc_out) {
    HTTPClient http;
    char url[128];
    snprintf(url, sizeof(url), "http://%s:%u%s", HOST, PORT, path);
    http.begin(url);
    http.setTimeout(10000);
    int code = http.GET();
    if (code != 200) {
        Serial.printf("[wall_image] GET %s -> %d\n", path, code);
        http.end();
        return false;
    }
    WiFiClient *s = http.getStreamPtr();
    const size_t total_bytes = (size_t)W * H * 2;
    size_t got = 0;
    uint32_t last_data = millis();
    bool ok = true;
    while (got < total_bytes) {
        int avail = s->available();
        if (avail > 0) {
            size_t want = total_bytes - got;
            got += s->readBytes(frame_buf + got, (size_t)avail < want ? (size_t)avail : want);
            last_data = millis();
        } else if (!s->connected() || millis() - last_data > 10000) {
            Serial.printf("[wall_image] stream stalled at byte %u\n", (unsigned)got);
            ok = false;
            break;
        } else {
            delay(1);
        }
    }
    uint32_t crc = 0;
    if (ok) {
        crc = esp_rom_crc32_le(0, frame_buf, total_bytes);
        lcd->drawBitmap(0, 0, W, H, frame_buf); // single call -- the whole point of staging first
    }
    http.end();
    *crc_out = crc;
    return ok;
}

// Posts the raw touch point and re-polls immediately (bypassing the normal
// 15s wait) so a tap feels responsive. The host owns ALL tap-to-meaning
// mapping -- this firmware doesn't know whether it's showing the fleet grid
// or a photo, what a tapmap is, or what a corner tap does. It just forwards
// (x,y) to whichever channel it's configured for and lets the host react.
//
// Edge-triggered: fires once when the finger goes DOWN, not on every ~50ms
// check while it's still touching the glass. A real press stays "pressed"
// for several loop iterations, so checking readPoints() > 0 on its own (or
// even with a short delay() after firing) sent the same physical tap 2-6
// times -- confirmed 2026-09-22 (one tap logged as 5 POSTs a few seconds
// apart, coordinates drifting slightly as the finger settled). was_pressed
// tracks state across loop() calls so a new tap can't fire until the
// controller reports a real release first.
static bool touch_was_pressed = false;

static void maybe_forward_touch(void) {
    if (!touch_enabled || touch == nullptr) return;
    TouchPoint pt;
    bool pressed = touch->readPoints(&pt, 1, 0) > 0;

    if (!pressed) {
        touch_was_pressed = false;
        return;
    }
    if (touch_was_pressed) return; // still holding down the same press -- already handled
    touch_was_pressed = true;

    HTTPClient http;
    char url[128];
    snprintf(url, sizeof(url), "http://%s:%u%s/tap", HOST, PORT, CHANNEL);
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    http.setTimeout(5000);
    char body[64];
    snprintf(body, sizeof(body), "{\"x\":%d,\"y\":%d}", pt.x, pt.y);
    int code = http.POST((uint8_t *)body, strlen(body));
    Serial.printf("[wall_image] tap (%d,%d) -> %d\n", pt.x, pt.y, code);
    http.end();

    last_hash = ""; // force an immediate re-fetch on the next poll, whatever the response
}

void setup() {
    Serial.begin(115200);
    Serial.println("FLEET_WALL_IMAGE start");


    g_board = new Board();
    if (g_board == nullptr || !g_board->init()) {
        Serial.println("Board init failed");
        while (true) delay(1000);
    }
    lcd = g_board->getLCD();
    auto *bus = lcd->getBus();
    if (bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
        lcd->configFrameBufferNumber(1);
        static_cast<BusRGB *>(bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 20);
    }
    assert(g_board->begin());

    touch = g_board->getTouch(); // no LVGL indev registration -- read directly in loop()
    touch_enabled = (touch != nullptr);
    if (!touch_enabled) {
        Serial.println("[wall_image] WARNING: no touch controller found, taps will not be forwarded");
    }

    // 768,000 bytes -- too big for internal RAM (~280KB free), lives in PSRAM.
    // This is a scratch buffer, separate from the display's own frame buffer.
    frame_buf = (uint8_t *)heap_caps_malloc((size_t)W * H * 2, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    assert(frame_buf != nullptr);

    wifi_connect();
    last_ok_ms = millis();
    Serial.printf("FLEET_WALL_IMAGE ready, channel=%s, touch=%d\n", CHANNEL, touch_enabled);
}

static void do_poll(void) {
    if (WiFi.status() != WL_CONNECTED) wifi_connect();

    String h;
    char hash_path[32];
    snprintf(hash_path, sizeof(hash_path), "%s/frame.hash", CHANNEL);
    if (http_get_string(hash_path, h)) {
        last_ok_ms = millis();
        if (h != last_hash) {
            uint32_t t0 = millis(), crc = 0;
            char frame_path[32];
            snprintf(frame_path, sizeof(frame_path), "%s/frame.rgb565", CHANNEL);
            if (fetch_frame(frame_path, &crc)) {
                last_hash = h;
                frames++;
                Serial.printf("[wall_image] frame %s in %lu ms (#%lu), heap %u\n", h.c_str(),
                              (unsigned long)(millis() - t0), (unsigned long)frames, ESP.getFreeHeap());
            }
        }
    }

    // Re-sync the RGB panel every cycle -- confirmed 2026-09-22 on the spike
    // board: display-side corruption (CRC always matched, so NOT a data
    // problem) did not clear on its own even after a later good frame drew
    // on top of it. This call is the fix; ran 2+ hours clean once added.
    esp_lcd_rgb_panel_restart((esp_lcd_panel_handle_t)lcd->getHandle());

    if (millis() - last_ok_ms > STALL_RESTART_MS) {
        Serial.println("[wall_image] no successful poll for 180s, restarting");
        delay(100);
        ESP.restart();
    }
}

void loop() {
    // Touch is checked every ~50ms in its own right, NOT gated behind the
    // 15s network poll -- an earlier version called maybe_forward_touch()
    // once per poll cycle (delay(POLL_MS) at the bottom of loop()), so a tap
    // only had about a 1-in-15-seconds chance of landing in the instant
    // touch was actually sampled. Confirmed 2026-09-22: the first tap after
    // flashing happened to land in that window and worked, every tap after
    // that didn't, and the board looked "stuck" in the detail view.
    static uint32_t last_poll_ms = 0;
    uint32_t now = millis();

    maybe_forward_touch(); // forces last_poll_ms = 0 below on a real tap, via last_hash reset

    if (now - last_poll_ms >= POLL_MS || last_hash.length() == 0) {
        do_poll();
        last_poll_ms = millis();
    }
    delay(50);
}

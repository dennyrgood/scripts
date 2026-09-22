/*
 * FLEET_WALL_IMAGE_SPIKE -- feasibility test: can this board show host-rendered
 * frames pulled over WiFi WITHOUT the RGB "screen drift"?
 * No LVGL, no JSON. Fetches a raw 800x480 RGB565 frame from image_server.py
 * and copies it into the panel framebuffer in small strips, with a 1ms yield
 * between strips so PSRAM bulk writes never monopolize the bus (the
 * throttling that the Waveshare LCD-5 drift issue found gave 100% stability).
 * Panel bring-up is the same as fleet_wall/esp-test (Waveshare's verified
 * config). WiFi sleep off, bounce buffer x20, like the production wall.
 * 2026-09-21
 */

#include <Arduino.h>
#include <esp_display_panel.hpp>
#include <WiFi.h>
#include <HTTPClient.h>
#include <esp_rom_crc.h>
#include <esp_lcd_panel_rgb.h>

#include "fleet_wall_secrets.h" // gitignored, same file as fleet_wall

using namespace esp_panel::drivers;
using namespace esp_panel::board;

SET_LOOP_TASK_STACK_SIZE(16 * 1024);

static const char *HOST = "192.168.178.241"; // this Mac (FleetDev) -- LAN IP, ESP has no Tailscale
static const uint16_t PORT = 8099;
static const uint32_t POLL_MS = 15000;
static const uint32_t STALL_RESTART_MS = 180000; // no successful poll for this long -> reboot

static const int W = 800, H = 480;
static const int STRIP_LINES = 8; // 800*8*2 = 12.8KB copied per step (H % STRIP_LINES == 0)

static LCD *lcd = nullptr;
static uint8_t *strip = nullptr;
static String last_hash;
static uint32_t last_ok_ms = 0;
static uint32_t frames = 0;
static uint32_t crc_bad = 0;

static void wifi_connect(void) {
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false);
    WiFi.begin(FLEET_WALL_WIFI_SSID, FLEET_WALL_WIFI_PASS);
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) delay(400);
    Serial.printf("[spike] WiFi %s, IP %s\n", WiFi.status() == WL_CONNECTED ? "up" : "FAILED",
                  WiFi.localIP().toString().c_str());
}

static bool fetch_hash(String &out) {
    HTTPClient http;
    char url[96];
    snprintf(url, sizeof(url), "http://%s:%u/frame.hash", HOST, PORT);
    http.begin(url);
    http.setTimeout(5000);
    int code = http.GET();
    if (code == 200) out = http.getString();
    else Serial.printf("[spike] hash GET -> %d\n", code);
    http.end();
    return code == 200;
}

// crc_out gets the CRC32 of every byte received, to compare with the
// server's: tells "data corrupted in transit" apart from "panel scan-out glitch".
static bool fetch_frame(uint32_t *crc_out) {
    uint32_t crc = 0;
    HTTPClient http;
    char url[96];
    snprintf(url, sizeof(url), "http://%s:%u/frame.rgb565", HOST, PORT);
    http.begin(url);
    http.setTimeout(10000);
    int code = http.GET();
    if (code != 200) {
        Serial.printf("[spike] frame GET -> %d\n", code);
        http.end();
        return false;
    }
    WiFiClient *s = http.getStreamPtr();
    const size_t strip_bytes = (size_t)W * STRIP_LINES * 2;
    bool ok = true;
    for (int y = 0; y < H && ok; y += STRIP_LINES) {
        size_t got = 0;
        uint32_t last_data = millis();
        while (got < strip_bytes) {
            int avail = s->available();
            if (avail > 0) {
                size_t want = strip_bytes - got;
                got += s->readBytes(strip + got, (size_t)avail < want ? (size_t)avail : want);
                last_data = millis();
            } else if (!s->connected() || millis() - last_data > 10000) {
                Serial.printf("[spike] stream stalled at line %d\n", y);
                ok = false;
                break;
            } else {
                delay(1);
            }
        }
        if (ok) {
            crc = esp_rom_crc32_le(crc, strip, strip_bytes);
            lcd->drawBitmap(0, y, W, STRIP_LINES, strip);
            vTaskDelay(pdMS_TO_TICKS(1)); // yield: keep PSRAM writes from starving the display refill
        }
    }
    http.end();
    *crc_out = crc;
    return ok;
}

void setup() {
    Serial.begin(115200);
    Serial.println("FLEET_WALL_IMAGE_SPIKE start");

    Board *board = new Board();
    if (board == nullptr || !board->init()) {
        Serial.println("Board init failed");
        while (true) delay(1000);
    }
    lcd = board->getLCD();
    auto *bus = lcd->getBus();
    if (bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
        lcd->configFrameBufferNumber(1);
        static_cast<BusRGB *>(bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 20);
    }
    assert(board->begin());

    strip = (uint8_t *)heap_caps_malloc((size_t)W * STRIP_LINES * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    assert(strip != nullptr);

    wifi_connect();
    last_ok_ms = millis();
    Serial.println("FLEET_WALL_IMAGE_SPIKE ready");
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) wifi_connect();

    String h;
    if (fetch_hash(h)) {
        last_ok_ms = millis();
        if (h != last_hash) {
            uint32_t t0 = millis(), crc = 0;
            if (fetch_frame(&crc)) {
                int colon = h.indexOf(':');
                uint32_t want = (colon >= 0) ? strtoul(h.c_str() + colon + 1, nullptr, 16) : 0;
                bool good = (crc == want);
                if (good) last_hash = h; // on a bad frame, keep the old hash so the next poll re-fetches
                else crc_bad++;
                frames++;
                Serial.printf("[spike] frame %s %s (got %08lx want %08lx) in %lu ms (#%lu, bad %lu), heap %u\n", h.c_str(),
                              good ? "CRC OK" : "CRC BAD", (unsigned long)crc, (unsigned long)want,
                              (unsigned long)(millis() - t0), (unsigned long)frames, (unsigned long)crc_bad,
                              ESP.getFreeHeap());
            }
        }
    }

    // Confirmed 2026-09-22: the corruption is NOT in the data (CRC always
    // matched) and does NOT clear on its own, even after a later good frame
    // draws on top of it -- it's the panel's own scan-out going wrong.
    // esp_lcd_rgb_panel_restart() re-syncs the RGB driver with vsync; called
    // every poll (not just on a new frame) so it can fix a bad picture even
    // when nothing else changed.
    esp_lcd_rgb_panel_restart((esp_lcd_panel_handle_t)lcd->getHandle());

    if (millis() - last_ok_ms > STALL_RESTART_MS) {
        Serial.println("[spike] no successful poll for 180s, restarting");
        delay(100);
        ESP.restart();
    }
    delay(POLL_MS);
}

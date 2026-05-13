/*
  Mac-esp32 Console Pet Runtime v6 Lite
  ESP32 OLED pet runtime + 5V fan PWM controller.

  Main path:
    Mac Brain -> bkb/desk1/mac/state + heartbeat + pet/config
    ESP32 owns face animation, display policy, fan control, and failsafe.

  Compatibility:
    v5 desired/system, desired/face, desired/display are parsed defensively.
    They are not the primary control path and cannot permanently override v6.

  Hardware safety:
    ESP32 GPIO must NOT drive a 5V fan directly. Use MOSFET/transistor,
    external 5V power, and shared GND. GPIO25 is PWM signal only.
*/

#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <U8g2lib.h>
#include <SPI.h>
#include "mbedtls/base64.h"

// ========================= Config =========================
namespace Config {
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
const char* MQTT_HOST = "192.168.1.100";
const int MQTT_PORT = 1883;
const char* DEVICE_ID = "desk1";
const char* FW_NAME = "v6.4-control-center";
const char* CONFIG_AP_SSID = "MacESP32-Setup";
const char* CONFIG_AP_PASS = "macesp32";

const uint8_t OLED_CS = 33;
const uint8_t OLED_DC = 27;
const uint8_t OLED_RST = 26;

// GPIO25 was BTN2 in v5. v6 Lite disables button interaction, so it is free for fan PWM.
const uint8_t FAN_PWM_PIN = 25;
const uint8_t FAN_PWM_CHANNEL = 0;
const uint32_t FAN_PWM_FREQ = 25000;
const uint8_t FAN_PWM_BITS = 8;

const unsigned long MAC_STATE_STALE_MS = 10000;
const unsigned long MAC_LONG_OFFLINE_MS = 60000;
const unsigned long HEARTBEAT_STALE_MS = 10000;
const unsigned long PET_STATE_MS = 10000;
const unsigned long TELEMETRY_MS = 30000;
const unsigned long FACE_FRAME_MS = 130;
const unsigned long FAN_UPDATE_MS = 200;
const unsigned long COMPAT_VIEW_MS = 6000;
const unsigned long SCENE_DEFAULT_MS = 5000;
const unsigned long MIN_BITMAP_PAGE_MS = 6000;
const unsigned long SLEEP_SCREEN_OFF_MS = 20UL * 60UL * 1000UL;
const unsigned long IDLE_SLEEPY_S = 10UL * 60UL;
const unsigned long MOOD_HOLD_MS = 1200;
const unsigned long HOT_COOLDOWN_MS = 30000;
const size_t BITMAP_1BPP_BYTES = 128 * 64 / 8;
const uint8_t MAX_BITMAP_PAGES = 8;

struct CurvePoint { int temp; int pct; };
const CurvePoint DEFAULT_FAN_CURVE[] = {
  {45, 0}, {55, 25}, {65, 40}, {75, 65}, {85, 85}, {95, 100}
};
const size_t FAN_CURVE_LEN = sizeof(DEFAULT_FAN_CURVE) / sizeof(DEFAULT_FAN_CURVE[0]);
}

// ========================= Shared Types =========================
enum Mood {
  MOOD_NORMAL,
  MOOD_HAPPY,
  MOOD_FOCUS,
  MOOD_BUSY,
  MOOD_POWER,
  MOOD_HOT,
  MOOD_IDLE,
  MOOD_SLEEPY,
  MOOD_SLEEP,
  MOOD_OFFLINE,
  MOOD_THINKING,
  MOOD_READING,
  MOOD_REPLYING,
  MOOD_CONFUSED
};

const char* moodName(Mood mood) {
  switch (mood) {
    case MOOD_NORMAL: return "normal";
    case MOOD_HAPPY: return "happy";
    case MOOD_FOCUS: return "focus";
    case MOOD_BUSY: return "busy";
    case MOOD_POWER: return "power";
    case MOOD_HOT: return "hot";
    case MOOD_IDLE: return "idle";
    case MOOD_SLEEPY: return "sleepy";
    case MOOD_SLEEP: return "sleep";
    case MOOD_OFFLINE: return "offline";
    case MOOD_THINKING: return "thinking";
    case MOOD_READING: return "reading";
    case MOOD_REPLYING: return "replying";
    case MOOD_CONFUSED: return "confused";
  }
  return "happy";
}

// ========================= NetworkConfig =========================
class NetworkConfig {
public:
  String wifiSsid = Config::WIFI_SSID;
  String wifiPass = Config::WIFI_PASS;
  String mqttHost = Config::MQTT_HOST;
  int mqttPort = Config::MQTT_PORT;

  void begin() {
    prefs.begin("bkb-net", false);
    wifiSsid = prefs.getString("ssid", Config::WIFI_SSID);
    wifiPass = prefs.getString("pass", Config::WIFI_PASS);
    mqttHost = prefs.getString("mqtt", Config::MQTT_HOST);
    mqttPort = prefs.getInt("port", Config::MQTT_PORT);
    if (mqttHost.length() == 0) {
      mqttHost = Config::MQTT_HOST;
      prefs.putString("mqtt", mqttHost);
    }
    if (wifiSsid.length() == 0) {
      wifiSsid = Config::WIFI_SSID;
      prefs.putString("ssid", wifiSsid);
    }
  }

  void save(const String& ssid, const String& pass, const String& host, int port) {
    if (ssid.length()) {
      wifiSsid = ssid;
      prefs.putString("ssid", wifiSsid);
    }
    if (pass.length()) {
      wifiPass = pass;
      prefs.putString("pass", wifiPass);
    }
    if (host.length()) {
      mqttHost = host;
      prefs.putString("mqtt", mqttHost);
    }
    if (port > 0 && port <= 65535) {
      mqttPort = port;
      prefs.putInt("port", mqttPort);
    }
  }

private:
  Preferences prefs;
};

// ========================= DisplayEngine =========================
class DisplayEngine {
public:
  U8G2_SSD1309_128X64_NONAME0_F_4W_HW_SPI oled;
  bool screenOn = true;
  bool textMode = false;
  String text[4] = {"Mac-esp32", "v6 Lite", "Booting", ""};

  DisplayEngine() : oled(U8G2_R0, Config::OLED_CS, Config::OLED_DC, Config::OLED_RST) {}

  void begin() {
    oled.begin();
    oled.setFont(u8g2_font_6x12_tr);
    drawText("Mac-esp32", "v6 Lite", "Starting", "ESP32");
  }

  void setScreen(bool on) {
    if (screenOn == on) return;
    screenOn = on;
    if (!screenOn) clear();
  }

  void clear() {
    oled.clearBuffer();
    oled.sendBuffer();
  }

  void drawText(const String& l0, const String& l1, const String& l2, const String& l3) {
    textMode = true;
    text[0] = fit16(l0); text[1] = fit16(l1); text[2] = fit16(l2); text[3] = fit16(l3);
    if (!screenOn) return;
    oled.clearBuffer();
    oled.setFont(u8g2_font_6x12_tr);
    oled.drawStr(0, 12, text[0].c_str());
    oled.drawStr(0, 28, text[1].c_str());
    oled.drawStr(0, 44, text[2].c_str());
    oled.drawStr(0, 60, text[3].c_str());
    oled.sendBuffer();
  }

  void drawConsoleText(const String& body, const String& style) {
    textMode = true;
    if (!screenOn) return;
    oled.clearBuffer();
    oled.setFont(u8g2_font_6x12_tr);

    int left = 0;
    int top = 0;
    int maxChars = 20;
    int maxLines = 5;
    if (style == "bubble") {
      oled.drawRFrame(2, 3, 124, 58, 6);
      left = 8;
      top = 13;
      maxChars = 18;
      maxLines = 4;
    } else if (style == "caption") {
      oled.drawHLine(0, 48, 128);
      left = 0;
      top = 12;
      maxChars = 20;
      maxLines = 3;
    } else {
      left = 0;
      top = 12;
      maxChars = 20;
      maxLines = 5;
    }

    String remaining = body;
    remaining.replace("\r", "");
    int y = top;
    for (int line = 0; line < maxLines && remaining.length() > 0; line++) {
      int newline = remaining.indexOf('\n');
      String chunk = newline >= 0 ? remaining.substring(0, newline) : remaining;
      if (chunk.length() > maxChars) chunk = chunk.substring(0, maxChars);
      oled.drawStr(left, y, chunk.c_str());
      int consumed = chunk.length();
      if (newline >= 0 && newline < consumed + 1) consumed = newline + 1;
      remaining = remaining.substring(min((int)remaining.length(), consumed));
      if (remaining.startsWith("\n")) remaining.remove(0, 1);
      y += 12;
    }
    oled.sendBuffer();
  }

  void drawBitmap1bpp(const uint8_t* bitmap) {
    textMode = false;
    if (!screenOn) return;
    oled.clearBuffer();
    for (uint8_t y = 0; y < 64; y++) {
      for (uint8_t x = 0; x < 128; x++) {
        size_t idx = (size_t)y * 16 + (x >> 3);
        if (bitmap[idx] & (1 << (x & 7))) oled.drawPixel(x, y);
      }
    }
    oled.sendBuffer();
  }

  void beginFaceFrame() {
    textMode = false;
    if (!screenOn) return;
    oled.clearBuffer();
  }

  void endFaceFrame() {
    if (!screenOn) return;
    oled.sendBuffer();
  }

private:
  String fit16(const String& s) {
    return s.length() <= 16 ? s : s.substring(0, 16);
  }
};

// ========================= MacLink =========================
class MacLink {
public:
  bool locked = true;
  bool online = false;
  int idleS = 0;
  int cpuPct = 0;
  int memPct = 0;
  int tempC = -1;
  String app = "Unknown";
  String timeText = "--:--";
  String modeHint = "";
  unsigned long lastStateMs = 0;
  unsigned long lastHeartbeatMs = 0;

  void handleState(JsonDocument& doc) {
    online = doc["online"] | true;
    locked = doc["locked"] | locked;
    idleS = constrain((int)(doc["idle_s"] | idleS), 0, 86400);
    cpuPct = constrain((int)(doc["cpu_pct"] | cpuPct), 0, 100);
    memPct = constrain((int)(doc["mem_pct"] | memPct), 0, 100);
    if (doc["temp_c"].is<int>()) tempC = constrain((int)doc["temp_c"], 0, 120);
    else tempC = -1;
    app = doc["app"].is<const char*>() ? String(doc["app"].as<const char*>()) : app;
    timeText = doc["time"].is<const char*>() ? String(doc["time"].as<const char*>()) : timeText;
    modeHint = doc["mode_hint"].is<const char*>() ? String(doc["mode_hint"].as<const char*>()) : "";
    lastStateMs = millis();
    lastHeartbeatMs = millis();
  }

  void handleHeartbeat(JsonDocument& doc) {
    online = doc["online"] | true;
    lastHeartbeatMs = millis();
  }

  bool hasState() const { return lastStateMs > 0; }
  bool stateFresh() const { return hasState() && millis() - lastStateMs <= Config::MAC_STATE_STALE_MS; }
  bool heartbeatFresh() const { return lastHeartbeatMs > 0 && millis() - lastHeartbeatMs <= Config::HEARTBEAT_STALE_MS; }
  bool macAvailable() const { return online && (stateFresh() || heartbeatFresh()); }
  bool longOffline() const { return !hasState() || millis() - lastStateMs > Config::MAC_LONG_OFFLINE_MS; }
  bool tempValid() const { return tempC >= 10 && tempC <= 110 && stateFresh(); }
  unsigned long stateAgeMs() const { return hasState() ? millis() - lastStateMs : 0xFFFFFFFF; }
};

// ========================= Runtime Config =========================
class RuntimeConfig {
public:
  bool lockedScreenOff = true;
  bool offlineFace = true;
  bool nightIdleOff = true;
  unsigned long sleepScreenOffMs = Config::SLEEP_SCREEN_OFF_MS;
  String fanMode = "auto";
  int offlinePct = 20;
  int failsafePct = 80;
  Config::CurvePoint curve[8];
  size_t curveLen = Config::FAN_CURVE_LEN;

  void begin() {
    for (size_t i = 0; i < Config::FAN_CURVE_LEN; i++) curve[i] = Config::DEFAULT_FAN_CURVE[i];
  }

  void apply(JsonDocument& doc) {
    JsonObject screen = doc["screen"];
    if (!screen.isNull()) {
      if (screen["locked"].is<const char*>()) lockedScreenOff = String(screen["locked"].as<const char*>()) == "off";
      if (screen["offline"].is<const char*>()) offlineFace = String(screen["offline"].as<const char*>()) == "face";
      if (screen["night_idle"].is<const char*>()) nightIdleOff = String(screen["night_idle"].as<const char*>()) == "off";
      if (screen["sleep_screen_off_ms"].is<unsigned long>()) {
        sleepScreenOffMs = constrain((unsigned long)screen["sleep_screen_off_ms"], 5000UL, Config::SLEEP_SCREEN_OFF_MS);
      }
    }
    JsonObject fan = doc["fan"];
    if (!fan.isNull()) {
      if (fan["mode"].is<const char*>()) fanMode = fan["mode"].as<const char*>();
      offlinePct = constrain((int)(fan["offline_pct"] | offlinePct), 0, 100);
      failsafePct = constrain((int)(fan["failsafe_pct"] | failsafePct), 0, 100);
      JsonArray arr = fan["curve"].as<JsonArray>();
      if (!arr.isNull()) {
        size_t n = 0;
        for (JsonVariant p : arr) {
          if (n >= 8 || !p.is<JsonArray>()) continue;
          JsonArray pair = p.as<JsonArray>();
          curve[n++] = { (int)(pair[0] | 0), constrain((int)(pair[1] | 0), 0, 100) };
        }
        if (n >= 2) curveLen = n;
      }
    }
  }
};

// ========================= FaceEngine =========================
class FaceEngine {
public:
  Mood mood = MOOD_SLEEP;
  Mood targetMood = MOOD_SLEEP;
  int intensity = 10;
  unsigned long step = 0;
  unsigned long moodSinceMs = 0;
  unsigned long lastHotMs = 0;
  int priority = 30;
  String reason = "boot";

  void updateDecision(const MacLink& mac, const RuntimeConfig& cfg, Mood sceneMood = MOOD_NORMAL, bool sceneActive = false) {
    Mood next = MOOD_NORMAL;
    int nextIntensity = 20;
    int nextPriority = 10;
    String nextReason = "normal";
    unsigned long now = millis();

    if (mac.tempValid() && mac.tempC >= 78) {
      next = MOOD_HOT;
      nextIntensity = map(constrain(mac.tempC, 78, 100), 78, 100, 65, 100);
      nextPriority = 100;
      nextReason = "hot_temp";
      lastHotMs = now;
    } else if (now - lastHotMs < Config::HOT_COOLDOWN_MS && mac.tempValid() && mac.tempC >= 70) {
      next = MOOD_HOT;
      nextIntensity = 60;
      nextPriority = 95;
      nextReason = "hot_cooldown";
    } else if (!mac.macAvailable()) {
      next = MOOD_OFFLINE;
      nextIntensity = mac.longOffline() ? 20 : 55;
      nextPriority = 80;
      nextReason = mac.longOffline() ? "mac_offline_long" : "mac_state_stale";
    } else if (mac.locked) {
      next = MOOD_SLEEP;
      nextIntensity = 10;
      nextPriority = 75;
      nextReason = "mac_locked";
    } else if (cfg.nightIdleOff && isNight(mac.timeText) && mac.idleS >= (int)Config::IDLE_SLEEPY_S) {
      next = MOOD_SLEEPY;
      nextIntensity = 12;
      nextPriority = 60;
      nextReason = "night_idle";
    } else if (sceneActive && (sceneMood == MOOD_THINKING || sceneMood == MOOD_READING || sceneMood == MOOD_REPLYING)) {
      next = sceneMood;
      nextIntensity = 55;
      nextPriority = 55;
      nextReason = moodName(sceneMood);
    } else if (mac.cpuPct >= 88 || mac.memPct >= 92) {
      next = MOOD_POWER;
      nextIntensity = max(mac.cpuPct, mac.memPct);
      nextPriority = 45;
      nextReason = "load_power";
    } else if (mac.cpuPct >= 65 || mac.memPct >= 78) {
      next = MOOD_BUSY;
      nextIntensity = max(mac.cpuPct, mac.memPct);
      nextPriority = 40;
      nextReason = "load_busy";
    } else if (mac.idleS >= (int)Config::IDLE_SLEEPY_S) {
      next = MOOD_SLEEPY;
      nextIntensity = 18;
      nextPriority = 35;
      nextReason = "idle_10m";
    } else if (mac.idleS >= 180) {
      next = MOOD_IDLE;
      nextIntensity = 20;
      nextPriority = 25;
      nextReason = "idle";
    } else if (isDevApp(mac.app) || String(mac.modeHint) == "focus" || mac.cpuPct >= 35) {
      next = MOOD_FOCUS;
      nextIntensity = max(35, mac.cpuPct);
      nextPriority = 20;
      nextReason = "dev_focus";
    } else {
      next = MOOD_HAPPY;
      nextIntensity = max(15, mac.cpuPct);
      nextPriority = 10;
      nextReason = "active_happy";
    }

    if (next != targetMood) {
      targetMood = next;
    }
    if (next != mood && (now - moodSinceMs >= Config::MOOD_HOLD_MS || nextPriority > priority)) {
      mood = next;
      step = 0;
      moodSinceMs = now;
    }
    intensity = constrain(nextIntensity, 0, 100);
    priority = nextPriority;
    reason = nextReason;
  }

  bool isSleepFamily() const {
    return mood == MOOD_SLEEP || mood == MOOD_SLEEPY || mood == MOOD_OFFLINE;
  }

  void draw(DisplayEngine& display) {
    if (!display.screenOn) return;
    display.beginFaceFrame();
    U8G2& o = display.oled;
    int bob = (step % 18 < 9) ? 0 : 1;
    bool blink = isBlinkFrame();
    int cy = 24 + bob;

    if (step < 4) drawWakeBlink(o, step);
    else {
      switch (mood) {
        case MOOD_NORMAL: drawNormal(o, bob, blink); break;
        case MOOD_HAPPY: drawHappy(o, bob, blink); break;
        case MOOD_FOCUS: drawFocus(o, blink); break;
        case MOOD_BUSY: drawBusy(o, blink); break;
        case MOOD_POWER: drawPower(o); break;
        case MOOD_HOT: drawHot(o, blink); break;
        case MOOD_IDLE: drawIdle(o, cy, blink); break;
        case MOOD_SLEEPY: drawSleepy(o, cy); break;
        case MOOD_SLEEP: drawSleep(o, cy); break;
        case MOOD_OFFLINE: drawOffline(o); break;
        case MOOD_THINKING: drawThinking(o, blink); break;
        case MOOD_READING: drawReading(o, blink); break;
        case MOOD_REPLYING: drawReplying(o, blink); break;
        case MOOD_CONFUSED: drawConfused(o); break;
      }
    }

    display.endFaceFrame();
    step++;
  }

private:
  bool isNight(const String& t) const {
    if (t.length() < 2) return false;
    int h = t.substring(0, 2).toInt();
    return h >= 23 || h < 8;
  }

  bool isDevApp(const String& app) const {
    String a = app;
    a.toLowerCase();
    return a.indexOf("terminal") >= 0 || a.indexOf("code") >= 0 || a.indexOf("xcode") >= 0 ||
           a.indexOf("arduino") >= 0 || a.indexOf("node-red") >= 0 || a.indexOf("codex") >= 0;
  }

  bool isBlinkFrame() const {
    int period = (mood == MOOD_FOCUS || mood == MOOD_BUSY || mood == MOOD_POWER) ? 28 : 42;
    return step % period == 0 || step % period == 1;
  }

  void closedEyes(U8G2& o, int y) {
    o.drawLine(28, y, 52, y);
    o.drawLine(76, y, 100, y);
  }

  void softEyes(U8G2& o, int y, int dx) {
    o.drawRFrame(28, y - 10, 24, 18, 6);
    o.drawRFrame(76, y - 10, 24, 18, 6);
    o.drawDisc(40 + dx, y, 3);
    o.drawDisc(88 + dx, y, 3);
  }

  void halfEyes(U8G2& o, int y, int dx) {
    o.drawLine(28, y - 3, 52, y - 3);
    o.drawLine(30, y + 4, 50, y + 4);
    o.drawLine(76, y - 3, 100, y - 3);
    o.drawLine(78, y + 4, 98, y + 4);
    o.drawDisc(40 + dx, y + 2, 2);
    o.drawDisc(88 + dx, y + 2, 2);
  }

  void happyEyes(U8G2& o, int y) {
    o.drawLine(28, y + 7, 34, y);
    o.drawLine(34, y, 46, y);
    o.drawLine(46, y, 52, y + 7);
    o.drawLine(76, y + 7, 82, y);
    o.drawLine(82, y, 94, y);
    o.drawLine(94, y, 100, y + 7);
  }

  void smile(U8G2& o, int big) {
    if (big) {
      o.drawLine(44, 42, 50, 50);
      o.drawLine(50, 50, 58, 54);
      o.drawLine(58, 54, 70, 54);
      o.drawLine(70, 54, 78, 50);
      o.drawLine(78, 50, 84, 42);
    } else {
      o.drawLine(56, 47, 63, 50);
      o.drawLine(63, 50, 72, 47);
    }
  }

  void sweat(U8G2& o) {
    int fall = step % 8;
    o.drawLine(108, 12 + fall, 113, 22 + fall);
    o.drawLine(113, 22 + fall, 108, 28 + fall);
  }

  void drawWakeBlink(U8G2& o, unsigned long phase) {
    int y = 25;
    if (phase < 2) closedEyes(o, y);
    else {
      o.drawLine(28, y - 3, 52, y - 3);
      o.drawLine(76, y - 3, 100, y - 3);
      o.drawPixel(40, y);
      o.drawPixel(88, y);
    }
  }

  void drawNormal(U8G2& o, int bob, bool blink) {
    if (blink) closedEyes(o, 25 + bob);
    else softEyes(o, 24 + bob, 0);
    smile(o, 0);
  }

  void drawSleep(U8G2& o, int cy) {
    closedEyes(o, cy);
    o.drawLine(55, 46, 73, 46);
    o.setFont(u8g2_font_6x12_tr);
    if (step % 20 < 10) o.drawStr(94, 53, "zZ");
    else o.drawStr(100, 48, "z");
  }

  void drawSleepy(U8G2& o, int cy) {
    halfEyes(o, cy, -1);
    o.drawLine(55, 48, 73, 48);
    o.setFont(u8g2_font_6x12_tr);
    if (step % 36 < 18) o.drawStr(101, 58, "...");
  }

  void drawHappy(U8G2& o, int bob, bool blink) {
    if (blink) closedEyes(o, 25 + bob);
    else happyEyes(o, 20 + bob);
    smile(o, intensity > 25);
    if (step % 12 < 6) {
      o.drawPixel(20, 14); o.drawPixel(108, 15); o.drawPixel(18, 17);
      o.drawLine(112, 8, 112, 12); o.drawLine(110, 10, 114, 10);
    }
  }

  void drawFocus(U8G2& o, bool blink) {
    if (blink) closedEyes(o, 25);
    else {
      o.drawLine(28, 20, 52, 20);
      o.drawLine(32, 29, 48, 29);
      o.drawLine(76, 20, 100, 20);
      o.drawLine(80, 29, 96, 29);
      o.drawDisc(42, 25, 2); o.drawDisc(90, 25, 2);
    }
    o.drawLine(53, 48, 75, 48);
    o.drawLine(15, 15, 24, 16); o.drawLine(104, 16, 113, 15);
  }

  void drawBusy(U8G2& o, bool blink) {
    int shake = (step % 6 == 0) ? 1 : 0;
    if (blink) closedEyes(o, 25);
    else {
      o.drawLine(29, 28 + shake, 51, 20 + shake);
      o.drawLine(77, 20 + shake, 99, 28 + shake);
      o.drawDisc(40, 28 + shake, 2); o.drawDisc(88, 28 + shake, 2);
    }
    o.drawLine(56, 49, 72, 44);
    if (intensity > 70) sweat(o);
  }

  void drawPower(U8G2& o) {
    int shake = (step % 2) ? 1 : -1;
    int y = 24 + shake;
    o.drawLine(27, y - 7, 52, y + 3);
    o.drawLine(29, y + 4, 50, y - 4);
    o.drawLine(76, y + 3, 101, y - 7);
    o.drawLine(78, y - 4, 99, y + 4);
    o.drawFrame(45, 40 + shake, 38, 14);
    o.drawLine(45, 47 + shake, 83, 47 + shake);
    o.drawLine(54, 40 + shake, 54, 54 + shake);
    o.drawLine(64, 40 + shake, 64, 54 + shake);
    o.drawLine(74, 40 + shake, 74, 54 + shake);
    sweat(o);
  }

  void drawIdle(U8G2& o, int cy, bool blink) {
    if (blink) closedEyes(o, cy);
    else {
      int dx = (step % 34 < 17) ? -4 : 4;
      softEyes(o, cy, dx);
    }
    if (step % 44 < 22) smile(o, 0);
    else o.drawLine(54, 48, 74, 48);
  }

  void drawHot(U8G2& o, bool blink) {
    int wave = (step % 4 < 2) ? 0 : 1;
    if (blink) closedEyes(o, 25);
    else {
      o.drawCircle(40, 24, 8);
      o.drawCircle(88, 24, 8);
      o.drawDisc(40, 27, 2);
      o.drawDisc(88, 27, 2);
    }
    o.drawLine(52, 49, 58, 45 + wave);
    o.drawLine(58, 45 + wave, 66, 49);
    o.drawLine(66, 49, 74, 45 + wave);
    sweat(o);
    o.drawLine(18, 13, 22, 20); o.drawLine(24, 13, 20, 20);
    o.drawLine(106, 12, 110, 19); o.drawLine(113, 12, 109, 19);
  }

  void drawOffline(U8G2& o) {
    int dx = (step % 28 < 14) ? -2 : 2;
    halfEyes(o, 24, dx);
    o.drawLine(54, 49, 74, 49);
    o.setFont(u8g2_font_6x12_tr);
    o.drawStr(47, 62, "offline");
    o.drawCircle(112, 16, 6); o.drawLine(108, 20, 116, 12);
  }

  void drawThinking(U8G2& o, bool blink) {
    if (blink) closedEyes(o, 25);
    else softEyes(o, 24, (step % 24 < 12) ? -2 : 2);
    o.drawLine(56, 49, 72, 49);
    int dots = (step / 5) % 4;
    for (int i = 0; i < dots; i++) o.drawDisc(53 + i * 10, 57, 2);
  }

  void drawReading(U8G2& o, bool blink) {
    if (blink) closedEyes(o, 24);
    else {
      o.drawRFrame(26, 15, 28, 18, 5); o.drawRFrame(74, 15, 28, 18, 5);
      o.drawDisc(45, 25, 2); o.drawDisc(93, 25, 2);
    }
    o.drawRFrame(46, 42, 36, 15, 3);
    o.drawLine(51, 47, 77, 47); o.drawLine(51, 52, 70, 52);
  }

  void drawReplying(U8G2& o, bool blink) {
    if (blink) closedEyes(o, 24);
    else happyEyes(o, 20);
    smile(o, 1);
    o.drawRFrame(82, 42, 34, 15, 4);
    o.drawLine(89, 48, 108, 48);
  }

  void drawConfused(U8G2& o) {
    o.drawCircle(40, 24, 8); o.drawLine(36, 20, 44, 28);
    o.drawCircle(88, 24, 8); o.drawDisc(88, 24, 2);
    o.drawLine(56, 49, 72, 51);
    o.setFont(u8g2_font_6x12_tr); o.drawStr(108, 16, "?");
  }
};

// ========================= FanController =========================
class FanController {
public:
  int fanPct = 0;
  int targetPct = 0;
  unsigned long lastUpdateMs = 0;
  unsigned long spinUntilMs = 0;

  void begin() {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcAttach(Config::FAN_PWM_PIN, Config::FAN_PWM_FREQ, Config::FAN_PWM_BITS);
#else
    ledcSetup(Config::FAN_PWM_CHANNEL, Config::FAN_PWM_FREQ, Config::FAN_PWM_BITS);
    ledcAttachPin(Config::FAN_PWM_PIN, Config::FAN_PWM_CHANNEL);
#endif
    writePct(0);
  }

  void update(const MacLink& mac, const RuntimeConfig& cfg, bool mqttConnected) {
    unsigned long now = millis();
    if (now - lastUpdateMs < Config::FAN_UPDATE_MS) return;
    lastUpdateMs = now;

    targetPct = decideTarget(mac, cfg, mqttConnected);

    if (targetPct > 0 && fanPct == 0 && spinUntilMs == 0) {
      spinUntilMs = now + 700;
      writePct(100);
      return;
    }
    if (spinUntilMs && now < spinUntilMs) {
      writePct(100);
      return;
    }
    spinUntilMs = 0;

    if (fanPct < targetPct) fanPct = min(targetPct, fanPct + 4);
    else if (fanPct > targetPct) fanPct = max(targetPct, fanPct - 3);
    writePct(fanPct);
  }

private:
  int decideTarget(const MacLink& mac, const RuntimeConfig& cfg, bool mqttConnected) {
    if (cfg.fanMode == "off") return 0;
    if (cfg.fanMode == "manual") return cfg.offlinePct;

    if (!mqttConnected && !mac.longOffline()) return cfg.failsafePct;
    if (!mac.macAvailable()) return mac.longOffline() ? cfg.offlinePct : cfg.failsafePct;
    if (!mac.stateFresh()) return cfg.failsafePct;

    if (mac.tempValid()) return fromCurve(mac.tempC, cfg);
    return cpuFallback(mac.cpuPct, cfg);
  }

  int fromCurve(int temp, const RuntimeConfig& cfg) {
    if (cfg.curveLen == 0) return 0;
    if (temp < cfg.curve[0].temp) return cfg.curve[0].pct;
    for (size_t i = 1; i < cfg.curveLen; i++) {
      if (temp < cfg.curve[i].temp) return cfg.curve[i].pct;
    }
    return cfg.curve[cfg.curveLen - 1].pct;
  }

  int cpuFallback(int cpu, const RuntimeConfig& cfg) {
    if (cpu >= 90) return max(75, cfg.failsafePct);
    if (cpu >= 75) return 65;
    if (cpu >= 60) return 45;
    if (cpu >= 40) return 25;
    return 0;
  }

  void writePct(int pct) {
    pct = constrain(pct, 0, 100);
    fanPct = pct;
    int duty = map(pct, 0, 100, 0, 255);
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcWrite(Config::FAN_PWM_PIN, duty);
#else
    ledcWrite(Config::FAN_PWM_CHANNEL, duty);
#endif
  }
};

// ========================= SceneEngine =========================
enum SceneKind {
  SCENE_FACE,
  SCENE_TEXT,
  SCENE_BITMAP,
  SCENE_PAGES,
  SCENE_THINKING
};

class SceneEngine {
public:
  SceneKind kind = SCENE_FACE;
  unsigned long untilMs = 0;
  bool dirty = false;
  String text = "";
  String style = "full";
  String source = "";
  String bitmapId = "";
  uint8_t bitmap[Config::BITMAP_1BPP_BYTES];
  uint8_t pages[Config::MAX_BITMAP_PAGES][Config::BITMAP_1BPP_BYTES];
  bool pageReady[Config::MAX_BITMAP_PAGES] = {false};
  uint8_t pageCount = 0;
  uint8_t currentPage = 0;
  unsigned long pageDurationMs = Config::MIN_BITMAP_PAGE_MS;
  unsigned long nextPageMs = 0;

  const char* sceneName() const {
    if (kind == SCENE_TEXT && millis() < untilMs) return "text";
    if (kind == SCENE_BITMAP && millis() < untilMs) return "bitmap";
    if (kind == SCENE_PAGES && millis() < untilMs) return "pages";
    if (kind == SCENE_THINKING && millis() < untilMs) return "thinking";
    return "face";
  }

  Mood sceneMood() const {
    if (kind == SCENE_THINKING) return MOOD_THINKING;
    if (kind == SCENE_TEXT) return MOOD_READING;
    if (kind == SCENE_BITMAP || kind == SCENE_PAGES) return source == "deepseek" ? MOOD_REPLYING : MOOD_READING;
    return MOOD_NORMAL;
  }

  bool active(unsigned long now) {
    expire(now);
    return kind != SCENE_FACE;
  }

  void cancel() {
    kind = SCENE_FACE;
    untilMs = 0;
    dirty = false;
    pageCount = 0;
    currentPage = 0;
  }

  void showText(const String& value, unsigned long durationMs, const String& styleName, const String& sourceName) {
    text = value.substring(0, 240);
    style = styleName.length() ? styleName : "full";
    source = sourceName;
    untilMs = millis() + clampDuration(durationMs);
    kind = SCENE_TEXT;
    dirty = true;
  }

  bool showBitmapBase64(const String& id, const char* data, unsigned long durationMs, const String& sourceName = "console") {
    if (!data || strlen(data) == 0) return false;
    size_t decodedLen = 0;
    int rc = mbedtls_base64_decode(
      bitmap,
      sizeof(bitmap),
      &decodedLen,
      reinterpret_cast<const unsigned char*>(data),
      strlen(data)
    );
    if (rc != 0 || decodedLen != sizeof(bitmap)) return false;

    bitmapId = id;
    source = sourceName;
    pageDurationMs = clampBitmapDuration(durationMs);
    untilMs = millis() + pageDurationMs;
    kind = SCENE_BITMAP;
    dirty = true;
    return true;
  }

  void showThinking(unsigned long durationMs, const String& sourceName) {
    source = sourceName;
    untilMs = millis() + clampDuration(durationMs);
    kind = SCENE_THINKING;
    dirty = true;
  }

  bool addBitmapPageBase64(const String& batchId, uint8_t pageIndex, uint8_t totalPages, const char* data, unsigned long durationMs, const String& sourceName) {
    if (!data || totalPages == 0 || totalPages > Config::MAX_BITMAP_PAGES || pageIndex >= totalPages) return false;
    size_t decodedLen = 0;
    int rc = mbedtls_base64_decode(
      pages[pageIndex],
      Config::BITMAP_1BPP_BYTES,
      &decodedLen,
      reinterpret_cast<const unsigned char*>(data),
      strlen(data)
    );
    if (rc != 0 || decodedLen != Config::BITMAP_1BPP_BYTES) return false;
    if (batchId != bitmapId || pageCount != totalPages) {
      bitmapId = batchId;
      pageCount = totalPages;
      currentPage = 0;
      for (uint8_t i = 0; i < Config::MAX_BITMAP_PAGES; i++) pageReady[i] = false;
    }
    pageReady[pageIndex] = true;
    source = sourceName;
    pageDurationMs = clampBitmapDuration(durationMs);
    if (allPagesReady()) {
      kind = SCENE_PAGES;
      untilMs = millis() + pageDurationMs * pageCount;
      nextPageMs = millis() + pageDurationMs;
      currentPage = 0;
      dirty = true;
    }
    return true;
  }

  bool shouldYieldToFace(Mood mood) const {
    return kind != SCENE_FACE &&
      (mood == MOOD_HOT || mood == MOOD_SLEEP || mood == MOOD_OFFLINE);
  }

  bool render(DisplayEngine& display, unsigned long now) {
    expire(now);
    if (kind == SCENE_FACE) return false;
    if (kind == SCENE_PAGES && now >= nextPageMs && currentPage + 1 < pageCount) {
      currentPage++;
      nextPageMs = now + pageDurationMs;
      dirty = true;
    }
    if (kind == SCENE_THINKING) dirty = true;
    if (!dirty) return true;

    display.setScreen(true);
    if (kind == SCENE_TEXT) {
      display.drawConsoleText(text, style);
    } else if (kind == SCENE_BITMAP) {
      display.drawBitmap1bpp(bitmap);
    } else if (kind == SCENE_PAGES) {
      display.drawBitmap1bpp(pages[currentPage]);
    } else if (kind == SCENE_THINKING) {
      drawThinkingScene(display, now);
    }
    dirty = false;
    return true;
  }

private:
  unsigned long clampDuration(unsigned long durationMs) const {
    if (durationMs == 0) return Config::SCENE_DEFAULT_MS;
    return constrain(durationMs, 500UL, 30000UL);
  }

  unsigned long clampBitmapDuration(unsigned long durationMs) const {
    if (durationMs < Config::MIN_BITMAP_PAGE_MS) return Config::MIN_BITMAP_PAGE_MS;
    return constrain(durationMs, Config::MIN_BITMAP_PAGE_MS, 30000UL);
  }

  bool allPagesReady() const {
    if (pageCount == 0) return false;
    for (uint8_t i = 0; i < pageCount; i++) if (!pageReady[i]) return false;
    return true;
  }

  void drawThinkingScene(DisplayEngine& display, unsigned long now) {
    if (!display.screenOn) return;
    display.oled.clearBuffer();
    display.oled.setFont(u8g2_font_6x12_tr);
    display.oled.drawStr(28, 18, "thinking");
    int dots = (now / 350) % 4;
    for (int i = 0; i < dots; i++) display.oled.drawDisc(47 + i * 10, 35, 2);
    display.oled.drawCircle(64, 48, 8);
    display.oled.sendBuffer();
  }

  void expire(unsigned long now) {
    if (kind != SCENE_FACE && (long)(now - untilMs) >= 0) cancel();
  }
};

// ========================= ScreenPolicy =========================
class ScreenPolicy {
public:
  bool screenOn = true;
  unsigned long inactiveSinceMs = 0;
  unsigned long manualOffUntilMs = 0;
  String offReason = "";

  void update(DisplayEngine& display, const FaceEngine& face, const SceneEngine& scene, const RuntimeConfig& cfg, const MacLink& mac, bool fanFailsafe) {
    unsigned long now = millis();
    bool forceOn = scene.kind != SCENE_FACE || face.mood == MOOD_HOT || fanFailsafe;
    bool sleepish = face.isSleepFamily();

    if (manualOffUntilMs && (long)(now - manualOffUntilMs) < 0 && !forceOn) {
      offReason = "manual_screen_off";
      set(display, false);
      return;
    }
    if (manualOffUntilMs && (long)(now - manualOffUntilMs) >= 0) {
      manualOffUntilMs = 0;
    }

    if (!sleepish || forceOn) {
      inactiveSinceMs = 0;
      offReason = "";
      set(display, true);
      return;
    }

    if (inactiveSinceMs == 0) inactiveSinceMs = now;
    if (now - inactiveSinceMs >= cfg.sleepScreenOffMs) {
      if (mac.locked) offReason = "locked_sleep_timeout";
      else if (!mac.macAvailable()) offReason = "offline_timeout";
      else offReason = "idle_sleep_timeout";
      set(display, false);
    } else {
      offReason = "";
      set(display, true);
    }
  }

  unsigned long inactiveAgeMs() const {
    return inactiveSinceMs ? millis() - inactiveSinceMs : 0;
  }

  void wake(DisplayEngine& display) {
    manualOffUntilMs = 0;
    inactiveSinceMs = 0;
    offReason = "";
    set(display, true);
  }

  void requestManualOff(DisplayEngine& display, unsigned long durationMs = 300000UL) {
    manualOffUntilMs = millis() + durationMs;
    inactiveSinceMs = millis();
    offReason = "manual_screen_off";
    set(display, false);
  }

private:
  void set(DisplayEngine& display, bool on) {
    screenOn = on;
    display.setScreen(on);
  }
};

// ========================= ConfigPortal =========================
class ConfigPortal {
public:
  WebServer server;
  bool active = false;

  ConfigPortal() : server(80) {}

  void begin(NetworkConfig& cfg, DisplayEngine& display) {
    if (active) return;
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(Config::CONFIG_AP_SSID, Config::CONFIG_AP_PASS);
    active = true;
    bindRoutes(cfg);
    server.begin();
    display.setScreen(true);
    display.drawText("Config AP", Config::CONFIG_AP_SSID, "192.168.4.1", "pass macesp32");
    Serial.printf("Config portal active: ssid=%s ip=%s\n", Config::CONFIG_AP_SSID, WiFi.softAPIP().toString().c_str());
  }

  void loop() {
    if (active) server.handleClient();
  }

private:
  void bindRoutes(NetworkConfig& cfg) {
    server.on("/", HTTP_GET, [&cfg, this]() {
      String html = "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
                    "<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:28px;background:#111;color:#f5f5f7}"
                    "input,button{font:inherit;width:100%;box-sizing:border-box;margin:8px 0;padding:12px;border-radius:10px;border:0}"
                    "button{background:#0a84ff;color:white}.card{max-width:420px;margin:auto}</style></head><body><div class='card'>"
                    "<h2>Mac-esp32 Setup</h2><form method='post' action='/config'>"
                    "<input name='ssid' placeholder='Wi-Fi SSID' value='" + cfg.wifiSsid + "'>"
                    "<input name='pass' placeholder='Wi-Fi Password' type='password'>"
                    "<input name='mqtt' placeholder='Mac MQTT IP' value='" + cfg.mqttHost + "'>"
                    "<input name='port' placeholder='MQTT Port' value='" + String(cfg.mqttPort) + "'>"
                    "<button>Save & Restart</button></form></div></body></html>";
      server.send(200, "text/html", html);
    });
    server.on("/status", HTTP_GET, [&cfg, this]() {
      StaticJsonDocument<256> doc;
      doc["ok"] = true;
      doc["ssid"] = cfg.wifiSsid;
      doc["mqtt_host"] = cfg.mqttHost;
      doc["mqtt_port"] = cfg.mqttPort;
      doc["ap_ssid"] = Config::CONFIG_AP_SSID;
      char out[256];
      size_t n = serializeJson(doc, out);
      server.send(200, "application/json", String(out).substring(0, n));
    });
    server.on("/config", HTTP_OPTIONS, [this]() {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.sendHeader("Access-Control-Allow-Headers", "content-type");
      server.send(204);
    });
    server.on("/config", HTTP_POST, [&cfg, this]() {
      String ssid;
      String pass;
      String mqtt;
      int port = Config::MQTT_PORT;
      if (server.hasHeader("Content-Type") && server.header("Content-Type").indexOf("application/json") >= 0) {
        StaticJsonDocument<512> doc;
        DeserializationError err = deserializeJson(doc, server.arg("plain"));
        if (err) {
          server.send(400, "application/json", "{\"ok\":false,\"error\":\"bad_json\"}");
          return;
        }
        ssid = doc["ssid"] | "";
        pass = doc["password"] | "";
        mqtt = doc["mqtt_host"] | "";
        port = doc["mqtt_port"] | Config::MQTT_PORT;
      } else {
        ssid = server.arg("ssid");
        pass = server.arg("pass");
        mqtt = server.arg("mqtt");
        port = server.arg("port").toInt();
      }
      cfg.save(ssid, pass, mqtt, port);
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.send(200, "application/json", "{\"ok\":true,\"restarting\":true}");
      delay(500);
      ESP.restart();
    });
  }
};

// ========================= Globals =========================
DisplayEngine display;
RuntimeConfig runtimeConfig;
NetworkConfig networkConfig;
MacLink macLink;
FaceEngine faceEngine;
FanController fanController;
SceneEngine sceneEngine;
ScreenPolicy screenPolicy;
ConfigPortal configPortal;
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

unsigned long lastMqttAttemptMs = 0;
uint8_t mqttFailCount = 0;
unsigned long lastPetStateMs = 0;
unsigned long lastTelemetryMs = 0;
unsigned long lastFaceFrameMs = 0;

// ========================= MQTT Bridge =========================
void publishPetState(bool retain) {
  StaticJsonDocument<1024> doc;
  doc["v"] = 1;
  doc["id"] = Config::DEVICE_ID;
  doc["fw"] = Config::FW_NAME;
  doc["uptime_ms"] = millis();
  doc["ip"] = WiFi.localIP().toString();
  doc["rssi"] = WiFi.RSSI();
  doc["mqtt_host"] = networkConfig.mqttHost;
  doc["config_portal"] = configPortal.active;
  doc["config_ap"] = Config::CONFIG_AP_SSID;
  doc["mac_link"] = macLink.macAvailable() ? "ok" : (macLink.longOffline() ? "offline" : "stale");
  doc["mood"] = moodName(faceEngine.mood);
  doc["current_mood"] = moodName(faceEngine.mood);
  doc["scene"] = sceneEngine.sceneName();
  doc["current_scene"] = sceneEngine.sceneName();
  doc["mood_reason"] = faceEngine.reason;
  doc["priority"] = faceEngine.priority;
  doc["screen_on"] = display.screenOn;
  doc["inactive_age_ms"] = screenPolicy.inactiveAgeMs();
  doc["screen_off_reason"] = screenPolicy.offReason;
  doc["fan_pct"] = fanController.fanPct;
  doc["temp_c_seen"] = macLink.tempValid() ? macLink.tempC : -1;
  doc["mqtt_connected"] = mqttClient.connected();
  char buf[1024];
  size_t n = serializeJson(doc, buf);
  mqttClient.publish("bkb/desk1/pet/state", (const uint8_t*)buf, n, retain);
}

void publishLegacyOnline(const char* status) {
  mqttClient.publish("bkb/desk1/state/online", status, true);
}

void publishTelemetry() {
  StaticJsonDocument<768> doc;
  doc["v"] = 1;
  doc["id"] = Config::DEVICE_ID;
  doc["fw"] = Config::FW_NAME;
  doc["uptime_ms"] = millis();
  doc["heap"] = ESP.getFreeHeap();
  doc["ip"] = WiFi.localIP().toString();
  doc["rssi"] = WiFi.RSSI();
  doc["mqtt_host"] = networkConfig.mqttHost;
  doc["mqtt_connected"] = mqttClient.connected();
  doc["config_portal"] = configPortal.active;
  doc["config_ap"] = Config::CONFIG_AP_SSID;
  doc["mood"] = moodName(faceEngine.mood);
  doc["current_mood"] = moodName(faceEngine.mood);
  doc["scene"] = sceneEngine.sceneName();
  doc["current_scene"] = sceneEngine.sceneName();
  doc["mood_reason"] = faceEngine.reason;
  doc["priority"] = faceEngine.priority;
  doc["screen_on"] = display.screenOn;
  doc["inactive_age_ms"] = screenPolicy.inactiveAgeMs();
  doc["screen_off_reason"] = screenPolicy.offReason;
  doc["fan_pct"] = fanController.fanPct;
  doc["last_mac_state_age_ms"] = macLink.stateAgeMs();
  doc["temp_c_seen"] = macLink.tempValid() ? macLink.tempC : -1;
  char buf[768];
  size_t n = serializeJson(doc, buf);
  mqttClient.publish("bkb/desk1/pet/telemetry", (const uint8_t*)buf, n, false);
}

void handleCompatTopic(const String& topic, JsonDocument& doc) {
  if (topic == "bkb/desk1/desired/display") {
    String l0 = doc["l0"] | "";
    String l1 = doc["l1"] | "";
    String l2 = doc["l2"] | "";
    String l3 = doc["l3"] | "";
    sceneEngine.showText(l0 + "\n" + l1 + "\n" + l2 + "\n" + l3, Config::COMPAT_VIEW_MS, "full", "v5");
  } else if (topic == "bkb/desk1/desired/system") {
    // Parse safely, but v6 policy takes over on the next face tick.
    const char* screen = doc["screen"] | "";
    if (String(screen) == "on") display.setScreen(true);
    else if (String(screen) == "off" && !macLink.macAvailable()) display.setScreen(false);
  } else if (topic == "bkb/desk1/desired/face") {
    // v5 retained face is accepted but not applied as authority.
  }
}

void mqttCallback(char* rawTopic, byte* payload, unsigned int length) {
  String topic(rawTopic);
  StaticJsonDocument<4096> doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) return;

  if (topic == "bkb/desk1/mac/state") {
    macLink.handleState(doc);
  } else if (topic == "bkb/desk1/mac/heartbeat") {
    macLink.handleHeartbeat(doc);
  } else if (topic == "bkb/desk1/pet/config") {
    runtimeConfig.apply(doc);
  } else if (topic == "bkb/desk1/cmd/text") {
    String text = doc["text"] | "";
    String style = doc["style"] | "full";
    String source = doc["source"] | "mqtt";
    unsigned long durationMs = (unsigned long)(doc["duration_ms"] | Config::SCENE_DEFAULT_MS);
    if (text.length()) {
      sceneEngine.showText(text, durationMs, style, source);
      publishPetState(true);
    }
  } else if (topic == "bkb/desk1/cmd/bitmap") {
    int w = doc["w"] | 0;
    int h = doc["h"] | 0;
    String format = doc["format"] | "";
    String encoding = doc["encoding"] | "";
    unsigned long durationMs = (unsigned long)(doc["duration_ms"] | Config::SCENE_DEFAULT_MS);
    const char* data = doc["data"] | "";
    String id = doc["id"] | "";
    String source = doc["source"] | "console";
    if (w == 128 && h == 64 && format == "1bpp" && encoding == "base64" &&
        sceneEngine.showBitmapBase64(id, data, durationMs, source)) {
      publishPetState(true);
    }
  } else if (topic == "bkb/desk1/cmd/bitmap/page") {
    int w = doc["w"] | 0;
    int h = doc["h"] | 0;
    String format = doc["format"] | "";
    String encoding = doc["encoding"] | "";
    unsigned long durationMs = (unsigned long)(doc["duration_ms"] | Config::MIN_BITMAP_PAGE_MS);
    const char* data = doc["data"] | "";
    String id = doc["id"] | "";
    String source = doc["source"] | "console";
    int pageIndex = doc["page_index"] | 0;
    int pageCount = doc["page_count"] | 0;
    if (w == 128 && h == 64 && format == "1bpp" && encoding == "base64" &&
        sceneEngine.addBitmapPageBase64(id, pageIndex, pageCount, data, durationMs, source)) {
      publishPetState(true);
    }
  } else if (topic == "bkb/desk1/cmd/scene") {
    String scene = doc["scene"] | "";
    String source = doc["source"] | "console";
    unsigned long durationMs = (unsigned long)(doc["duration_ms"] | Config::SCENE_DEFAULT_MS);
    if (scene == "thinking") {
      sceneEngine.showThinking(durationMs, source);
      publishPetState(true);
    }
  } else if (topic == "bkb/desk1/cmd/device") {
    String action = doc["action"] | "";
    if (action == "wake" || action == "screen_on") {
      screenPolicy.wake(display);
      sceneEngine.showText("Mac-esp32\nawake", 2500, "bubble", "device");
      publishPetState(true);
    } else if (action == "screen_off") {
      sceneEngine.cancel();
      screenPolicy.requestManualOff(display);
      publishPetState(true);
    } else if (action == "clear_scene") {
      sceneEngine.cancel();
      screenPolicy.wake(display);
      publishPetState(true);
    } else if (action == "test_pattern") {
      screenPolicy.wake(display);
      sceneEngine.showText("Mac-esp32\nTEST\n128x64", 6000, "full", "device");
      publishPetState(true);
    } else if (action == "config_portal") {
      configPortal.begin(networkConfig, display);
      publishPetState(true);
    } else if (action == "reboot") {
      publishPetState(true);
      delay(250);
      ESP.restart();
    }
  } else if (topic == "bkb/desk1/cmd/netconfig") {
    String ssid = doc["ssid"] | "";
    String pass = doc["password"] | "";
    String mqttHost = doc["mqtt_host"] | "";
    int mqttPort = doc["mqtt_port"] | Config::MQTT_PORT;
    networkConfig.save(ssid, pass, mqttHost, mqttPort);
    publishPetState(true);
    delay(250);
    ESP.restart();
  } else if (topic == "bkb/desk1/desired/system" || topic == "bkb/desk1/desired/face" || topic == "bkb/desk1/desired/display") {
    handleCompatTopic(topic, doc);
  }
}

bool connectMqtt() {
  String clientId = "bkb-desk-pet-v6-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.printf("MQTT connecting to %s:%d\n", networkConfig.mqttHost.c_str(), networkConfig.mqttPort);
  if (!mqttClient.connect(clientId.c_str(), "bkb/desk1/state/online", 0, true, "offline")) {
    Serial.printf("MQTT connect failed state=%d\n", mqttClient.state());
    mqttFailCount++;
    if (mqttFailCount >= 3) configPortal.begin(networkConfig, display);
    return false;
  }
  mqttFailCount = 0;
  mqttClient.subscribe("bkb/desk1/mac/state");
  mqttClient.subscribe("bkb/desk1/mac/heartbeat");
  mqttClient.subscribe("bkb/desk1/pet/config");
  mqttClient.subscribe("bkb/desk1/cmd/text");
  mqttClient.subscribe("bkb/desk1/cmd/bitmap");
  mqttClient.subscribe("bkb/desk1/cmd/bitmap/page");
  mqttClient.subscribe("bkb/desk1/cmd/scene");
  mqttClient.subscribe("bkb/desk1/cmd/device");
  mqttClient.subscribe("bkb/desk1/cmd/netconfig");
  mqttClient.subscribe("bkb/desk1/desired/system");
  mqttClient.subscribe("bkb/desk1/desired/face");
  mqttClient.subscribe("bkb/desk1/desired/display");
  publishLegacyOnline("online");
  publishPetState(true);
  publishTelemetry();
  Serial.println("MQTT connected and v6 topics subscribed");
  return true;
}

void ensureWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(configPortal.active ? WIFI_AP_STA : WIFI_STA);
  WiFi.begin(networkConfig.wifiSsid.c_str(), networkConfig.wifiPass.c_str());
  Serial.printf("WiFi connecting to %s\n", networkConfig.wifiSsid.c_str());
  display.drawText("WiFi", "Connecting", networkConfig.wifiSsid, "");
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 12000) {
    delay(250);
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("WiFi OK ip=%s rssi=%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    display.drawText("WiFi OK", WiFi.localIP().toString(), "MQTT next", "");
  } else {
    Serial.println("WiFi failed; local fallback");
    display.drawText("WiFi failed", "local fallback", "", "");
    configPortal.begin(networkConfig, display);
  }
}

// ========================= Arduino lifecycle =========================
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("Mac-esp32 v6.4 control center boot");
  networkConfig.begin();
  Serial.printf("OLED CS=%d DC=%d RST=%d FAN_PWM_PIN=%d MQTT_HOST=%s\n",
                Config::OLED_CS, Config::OLED_DC, Config::OLED_RST,
                Config::FAN_PWM_PIN, networkConfig.mqttHost.c_str());
  runtimeConfig.begin();
  display.begin();
  fanController.begin();
  ensureWiFi();
  configPortal.begin(networkConfig, display);
  mqttClient.setServer(networkConfig.mqttHost.c_str(), networkConfig.mqttPort);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(4096);
}

void loop() {
  unsigned long now = millis();
  configPortal.loop();

  if (WiFi.status() != WL_CONNECTED) ensureWiFi();
  if (WiFi.status() == WL_CONNECTED && !mqttClient.connected() && now - lastMqttAttemptMs > 2500) {
    lastMqttAttemptMs = now;
    connectMqtt();
  }
  if (mqttClient.connected()) mqttClient.loop();

  bool sceneCurrentlyActive = sceneEngine.active(now);
  faceEngine.updateDecision(macLink, runtimeConfig, sceneEngine.sceneMood(), sceneCurrentlyActive);
  if (sceneEngine.shouldYieldToFace(faceEngine.mood)) sceneEngine.cancel();

  fanController.update(macLink, runtimeConfig, mqttClient.connected());
  bool fanFailsafe = fanController.targetPct >= runtimeConfig.failsafePct && !macLink.longOffline();
  screenPolicy.update(display, faceEngine, sceneEngine, runtimeConfig, macLink, fanFailsafe);

  bool sceneActive = display.screenOn && sceneEngine.render(display, now);
  if (display.screenOn && !sceneActive && now - lastFaceFrameMs >= Config::FACE_FRAME_MS) {
    lastFaceFrameMs = now;
    faceEngine.draw(display);
  }

  if (mqttClient.connected() && now - lastPetStateMs >= Config::PET_STATE_MS) {
    lastPetStateMs = now;
    publishPetState(true);
  }
  if (mqttClient.connected() && now - lastTelemetryMs >= Config::TELEMETRY_MS) {
    lastTelemetryMs = now;
    publishTelemetry();
  }
}

# BKB Desk Pet v6.1 Console

## Goal

v6.1 upgrades screen interaction without changing the v6 responsibility split. ESP32 owns local face animation and scene switching. The Mac console owns Chinese text layout and bitmap rendering.

DeepSeek/API key UI is only reserved for v6.2. No API key is stored in the repository and no cloud AI call is implemented in v6.1.

## New MQTT Topics

`bkb/desk1/cmd/text`

```json
{
  "v": 1,
  "text": "hello",
  "duration_ms": 5000,
  "style": "bubble",
  "source": "console"
}
```

`bkb/desk1/cmd/bitmap`

```json
{
  "v": 1,
  "id": "msg-001",
  "w": 128,
  "h": 64,
  "format": "1bpp",
  "encoding": "base64",
  "duration_ms": 6000,
  "data": "..."
}
```

`pet/state` and `pet/telemetry` now include:

```json
{ "scene": "face" }
```

Scene values are `face`, `text`, and `bitmap`.

## New HTTP Endpoints

Node-RED forwards console commands:

- `POST http://127.0.0.1:1880/bkb/console/text`
- `POST http://127.0.0.1:1880/bkb/console/bitmap`

Both return:

```json
{ "ok": true }
```

## Chinese Display Strategy

The Mac app renders Chinese using macOS system fonts with CoreText/CoreGraphics. It packs the rendered 128x64 grayscale buffer into 1bpp bytes using LSB-first bit order per row. ESP32 decodes the base64 payload and displays pixels directly.

This avoids storing a full Chinese font on ESP32 and keeps OLED rendering predictable.

## Console App

Project:

`~/mac-esp32-console/macos/MacESP32Console`

Run:

```sh
cd "~/mac-esp32-console/macos/MacESP32Console"
./script/build_and_run.sh
```

Module 1 supports:
- Node-RED URL configuration.
- Chinese text input.
- Duration in milliseconds.
- Style: `full`, `bubble`, `caption`.
- 128x64 OLED preview.
- Send bitmap to ESP32 through Node-RED.
- Status log.

v0.2 adds:
- Native macOS sidebar/detail layout with resizable window behavior.
- Independent panels for screen display, DeepSeek conversation, and Mac status.
- DeepSeek API key input and streaming replies to OLED bitmap frames.
- Mac performance snapshot: CPU, memory, CPU temperature, foreground app, and storage usage.
- Telegram Bot polling with `/show`, `/ask`, and `/status`.

v0.3 adds:
- Long Chinese text pagination into multiple 128x64 bitmap pages.
- Per-page display duration of at least 6 seconds.
- ESP32-side automatic page playback through `bkb/desk1/cmd/bitmap/page`.
- DeepSeek thinking scene before response and automatic final-page playback.

## Limitations

- Long text is clipped to the first page; pagination is not implemented yet.
- DeepSeek and Telegram require user-provided API key/token at runtime.
- The ESP32 text command is for English/debug text. Chinese should use bitmap.
- Real fan hardware testing is intentionally not part of v6.1.

# v7.0.0-alpha1 Plan

Theme: Mac Ecosystem Display + OTA + Device Management.

This release is a conservative first step on top of v6.6.0. It does not remove existing `/bkb/...` HTTP endpoints, MQTT topics, Telegram commands, Chinese bitmap display, diagnostics, provisioning, or network recovery behavior.

## Added Scope

- Menu bar icon changes from Apple logo to a robot SF Symbol with a CPU fallback.
- Telegram `/wake` now means OLED wake, not Mac wake.
- Telegram adds `/screen_on`, `/screen_off`, `/repair`, and `/help`.
- Device page adds richer ESP32 fields, copy status, diagnostic export, test expression buttons, widget tests, and an OTA area.
- ESP32 reports `network_reason`, sketch size, free sketch space, heap, firmware version, and stale Mac state age.
- ESP32 exposes conservative OTA endpoints:
  - `GET /ota/status`
  - `POST /ota/upload`
- App can select and upload a `.bin` file directly to the ESP32 over LAN when OTA is supported.
- DisplayKit adds reusable OLED widget rendering for dashboard, music, calendar, network error, OTA progress, and dreamcore text scenes.
- MacContext adds low-risk providers for foreground window title and now-playing metadata.
- Release packaging is moved to `tools/package_release.sh`.

## Compatibility

The public product name remains Mac-ESP32 Console / Mac-esp32 控制台. Internal compatibility topics still use `bkb/desk1/...` and remain intentionally unchanged.

Secrets are not written to the repository. DeepSeek keys and Telegram bot tokens remain in macOS Keychain.

## Known Alpha Limits

- OTA depends on ESP32 partition layout and free sketch space. If the current board was flashed with a partition scheme that leaves no OTA space, the UI reports unsupported and USB flashing is still required.
- OTA token hardening is not complete in alpha1. Use OTA only on a trusted LAN.
- Calendar provider is currently a safe placeholder. EventKit permission flow is planned later.
- Now Playing uses AppleScript best-effort checks for Apple Music and Spotify. Missing permissions or inactive players return no data without failing the app.
- OTA upload progress is first-stage and may report coarse progress.
- Display scene presets are rendered by the Mac app as bitmap widgets first; the ESP32 native expression engine remains compatible and is not rewritten in this alpha.

## Validation Checklist

- `swift build` in `macos/MacESP32Console`
- `macos/MacESP32Console/script/build_and_run.sh --verify`
- `python3 nodered/make_flow_v6_lite.py`
- `arduino-cli compile --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite`
- Device page can query `/ota/status`
- Telegram `/wake` does not claim to wake the Mac
- Scene preset buttons publish bitmap pages and return to face

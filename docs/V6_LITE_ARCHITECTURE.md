# BKB Desk Pet v6 Lite Architecture

## Why v6 Is A Rebuild

v5 proved the route works: Mac events, Node-RED, MQTT, and ESP32 OLED rendering can operate together. v6 Lite changes the responsibility split. It is not a patch on the v5 screen-remote model.

v5 mostly let the Mac/Node-RED decide what the screen should show. v6 makes ESP32 a pet runtime with its own local brain for expression, animation, display policy, fan control, link monitoring, and failsafe behavior.

## Scope

Included:
- Local OLED face simulation on ESP32.
- Mac state integration through Node-RED.
- 5V fan PWM control through ESP32.
- Mac online/offline switching.
- Basic safety and fallback behavior.
- v5 MQTT compatibility parsing.

Excluded for v6 Lite:
- Voice.
- AI dialogue.
- Button interaction.
- Servo control.
- Cloud AI.
- Complex Mac automation.

These are intentionally excluded so the first pet runtime stays reliable and inspectable.

## Mac Brain

Mac Brain is implemented by Hammerspoon, `macbrain_status_v6.sh`, and Node-RED.

Responsibilities:
- Detect lock/unlock/sleep/wake/app activation.
- Collect CPU, memory, idle time, foreground app, time, lock state, and temperature.
- Publish unified state to `bkb/desk1/mac/state`.
- Publish heartbeat to `bkb/desk1/mac/heartbeat`.
- Publish config to `bkb/desk1/pet/config`.

Mac Brain does not decide OLED drawing details or animation frames.

## ESP32 Pet Runtime

Responsibilities:
- Maintain MacLink state freshness.
- Choose local mood from Mac state.
- Render pixel expressions locally.
- Control OLED screen policy.
- Control fan PWM.
- Publish pet state and telemetry.
- Survive bad JSON, MQTT loss, Wi-Fi loss, stale Mac state, and old v5 retained messages.

## MQTT Schema

Mac to ESP32:
- `bkb/desk1/mac/state`, retained.
- `bkb/desk1/mac/heartbeat`, retained.
- `bkb/desk1/pet/config`, retained.

ESP32 to Mac:
- `bkb/desk1/pet/state`, retained.
- `bkb/desk1/pet/telemetry`, not retained.

Compatibility input:
- `bkb/desk1/desired/system`
- `bkb/desk1/desired/face`
- `bkb/desk1/desired/display`

The compatibility topics are defensive inputs only. They are not the v6 main path.

## FaceEngine

FaceEngine maps MacLink state to local moods:
- `sleep`
- `happy`
- `focus`
- `busy`
- `power`
- `idle`
- `hot`
- `offline`

It owns blink, bobbing, eye drift, heat stress, offline expression, sleep face, and local frame timing.

## DisplayEngine

DisplayEngine owns U8g2 initialization and OLED refresh. It supports:
- Face page.
- Temporary text page for compatibility.
- v6.1 temporary text and bitmap scenes.
- Screen on/off.
- Full-buffer refresh on SSD1309 128x64.

## SceneEngine

v6.1 adds a Screen Scene Engine on ESP32. The default scene is `face`; temporary scenes are `text` and `bitmap`.

New command topics:
- `bkb/desk1/cmd/text`: English/debug text, duration, style.
- `bkb/desk1/cmd/bitmap`: 128x64 1bpp base64 bitmap, duration.

Temporary scenes expire locally and return to `face`. Safety moods such as `hot`, `sleep`, and `offline` can interrupt temporary display. Node-RED and the Mac console do not send face frames; ESP32 still owns animation and scene switching.

## Console Path

The Mac console app renders Chinese text on the Mac with system fonts, packs it as a 128x64 1bpp bitmap, and posts it to Node-RED. Node-RED only forwards the command to MQTT:

`Console -> POST /bkb/console/bitmap -> bkb/desk1/cmd/bitmap -> ESP32 SceneEngine`

Chinese bitmap rendering stays on the Mac side. ESP32 keeps a simple text renderer for English/debug and v5 compatibility, but does not carry a full Chinese font.

## FanController

FanController uses ESP32 LEDC PWM on GPIO25.

Default curve:
- `<45C`: 0%
- `45-55C`: 25%
- `55-65C`: 40%
- `65-75C`: 65%
- `75-85C`: 85%
- `>=85C`: 100%

Failsafe:
- Mac online but state stale: 80%.
- MQTT disconnected while Mac is not known long-offline: 80%.
- Mac long offline: 20%.
- Temperature unavailable and CPU high: CPU fallback.

## MacLink

MacLink stores the latest `mac/state` and heartbeat. It decides:
- Mac available.
- State fresh/stale.
- Long offline.
- Temperature valid.

## Hardware Safety

ESP32 GPIO must not directly drive a 5V fan.

Required:
- MOSFET or transistor driver.
- External 5V fan power.
- Shared GND between ESP32 and 5V supply.
- GPIO25 only as PWM signal.

## v5 Compatibility

ESP32 still subscribes to:
- `desired/system`
- `desired/face`
- `desired/display`

Old retained messages are parsed safely. Display text may appear briefly as a compatibility overlay, but v6 Mac state and local runtime remain authoritative.

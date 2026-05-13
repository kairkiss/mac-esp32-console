# Deploy BKB Desk Pet v6 Lite

Project root:

`~/mac-esp32-console`

## Deploy Mac Runtime

Run:

```sh
cd "~/mac-esp32-console"
./tools/deploy_v6_lite.sh
```

This backs up live files under `backups/YYYYMMDD_HHMMSS/`, deploys:
- `~/bin/macbrain_status_v6.sh`
- `~/.hammerspoon/init.lua`
- `~/.node-red/flows.json`

It also reloads Hammerspoon and restarts Node-RED.

## Node-RED

v6 flow:

`nodered/bkb_desk_pet_v6_lite_flow.json`

The deployment script disables old BKB Desk Node v3/v4/v5 tabs and enables `BKB Desk Pet v6 Lite`.

HTTP endpoint:

`POST http://127.0.0.1:1880/bkb/mac/event`

v6.1 console endpoints:

`POST http://127.0.0.1:1880/bkb/console/text`

`POST http://127.0.0.1:1880/bkb/console/bitmap`

## Hammerspoon

v6 bridge:

`hammerspoon/hammerspoon_bkb_bridge_v6_lite.lua`

It posts lock/unlock/app events to Node-RED and shows:

`BKB v6 Lite bridge loaded`

## ESP32

Sketch:

`esp32/bkb_desk_pet_v6_lite/bkb_desk_pet_v6_lite.ino`

Before flashing, confirm:
- `WIFI_SSID`
- `WIFI_PASS`
- `MQTT_HOST`
- `MQTT_PORT`
- `FAN_PWM_PIN`

Current defaults:
- MQTT host: `192.168.1.100`
- Fan PWM pin: GPIO25
- OLED CS/DC/RST: 33/27/26

## MQTT Host

Node-RED uses local broker `127.0.0.1:1883`.

ESP32 must use the Mac LAN IP that runs Mosquitto. If the Mac IP changed, update `Config::MQTT_HOST` before flashing.

## OLED Verification

Expected:
- Boot text.
- Wi-Fi status.
- Local face after receiving `mac/state`.
- `offline` face if Mac state/heartbeat becomes stale.

## Fan Verification

Do not connect the fan directly to GPIO.

Required wiring:
- ESP32 GPIO25 -> MOSFET/transistor gate/base driver.
- Fan powered by external 5V.
- ESP32 GND connected to 5V supply GND.

Test with simulated state:

```sh
./tools/test_v6_lite.sh
```

Watch `bkb/desk1/pet/state` for `fan_pct`.

## Mac-esp32 控制台

Desktop app:

`~/Desktop/Mac-esp32控制台.app`

Source:

`macos/MacESP32Console`

Build:

```sh
cd "~/mac-esp32-console/macos/MacESP32Console"
swift build
```

Run:

```sh
./script/build_and_run.sh
```

The app renders Chinese text to 128x64 monochrome bitmap pages and posts through Node-RED:

- `GET /mac-esp32/console/status`
- `POST /mac-esp32/console/bitmap`
- `POST /mac-esp32/console/bitmap/page`
- `POST /mac-esp32/console/scene`
- `POST /mac-esp32/console/device`
- `POST /mac-esp32/console/netconfig`

v6.4 device controls are soft controls. ESP32 must already be powered; the app cannot power on a physically disconnected board.

## v6.5 Diagnostics

Run from the repository root:

```sh
./tools/doctor_v6_5.sh
```

The macOS App also includes a `诊断与向导` section. It checks Mosquitto, Node-RED, Hammerspoon, `macbrain_status_v6.sh`, Node-RED HTTP endpoints, ESP32 status, and the current Mac LAN IP.

Package the App:

```sh
./tools/package_app_v6_5.sh
```

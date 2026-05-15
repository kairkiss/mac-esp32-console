# Mac-ESP32 Console

<p align="center">
  <strong>A local ambient console for macOS, ESP32 and OLED.</strong><br>
  <span>一个把 Mac 状态、AI 回复、桌面自动化与 ESP32 OLED 小屏连接起来的桌面控制台 / 桌宠系统。</span>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-SwiftUI-black?logo=apple">
  <img alt="ESP32" src="https://img.shields.io/badge/ESP32-Arduino-red?logo=espressif">
  <img alt="Node-RED" src="https://img.shields.io/badge/Node--RED-Automation-red?logo=nodered">
  <img alt="MQTT" src="https://img.shields.io/badge/MQTT-Mosquitto-blue">
  <img alt="OLED" src="https://img.shields.io/badge/OLED-128x64-lightgrey">
</p>

---

## Overview / 项目概览

**Mac-ESP32 Console** is a local-first desktop companion system built with **macOS + Node-RED + MQTT + ESP32 + OLED**.

It turns the Mac into a live state publisher and the ESP32 into a small physical runtime. macOS collects system signals, Node-RED coordinates state and commands, MQTT carries messages, and the ESP32 renders faces, scenes, status pages and bitmap text on a 128x64 OLED display.

中文简介：这是一个本地优先的 Mac 桌面状态屏 / ESP32 桌宠项目。Mac 负责采集状态和处理高级逻辑，Node-RED 负责状态编排与 HTTP API，MQTT 负责通信，ESP32 负责本地表情引擎、OLED 渲染、设备状态与 failsafe。

Current version: `v6.5-diagnostics-setup`

---

## Core Features / 核心功能

### Mac-aware OLED companion

The OLED display reacts to Mac activity such as CPU usage, memory usage, temperature, idle time, foreground app and lock state.

The ESP32 expression engine supports moods including:

```text
happy / focus / busy / power / hot / idle / sleepy / sleep / offline / thinking / reading / replying
```

### Local ESP32 runtime

The firmware runs the essential device logic locally:

- FaceEngine and SceneEngine
- OLED rendering
- MacLink state handling
- MQTT command handling
- offline / failsafe behavior
- optional GPIO25 PWM fan-control logic

### Chinese bitmap display

The macOS app renders Chinese text into `128x64` 1-bit bitmap pages, then sends those pages to ESP32 through Node-RED and MQTT. This makes Chinese short messages, status prompts and AI replies readable on a small OLED screen.

### macOS SwiftUI console

The SwiftUI app in `macos/MacESP32Console` provides:

- Chinese bitmap preview and sending
- DeepSeek short-response streaming to OLED
- Telegram bridge
- ESP32 online state, firmware version, IP and RSSI
- MQTT / MacLink state
- current mood, scene, screen state and fan percentage
- soft wake, screen off, return-to-face, test image and ESP32 restart
- setup assistant and diagnostics

### Diagnostics

v6.5 includes an in-app diagnostics page and a terminal doctor script:

```sh
./tools/doctor_v6_5.sh
```

It checks Mosquitto, Node-RED, Hammerspoon, Mac telemetry script, console endpoints, ESP32 status and local network IP candidates.

---

## Architecture / 系统架构

```text
Mac telemetry + Hammerspoon events
        ↓
Node-RED state orchestration and HTTP API
        ↓
Mosquitto MQTT broker
        ↓
ESP32 local runtime
        ↓
OLED face / scene / Chinese bitmap / device feedback
```

Main roles:

| Layer | Role |
|---|---|
| macOS script | Collects CPU, memory, temperature, idle and system status |
| Hammerspoon | Sends lock, unlock and foreground-app events |
| Node-RED | Coordinates state, HTTP endpoints and MQTT publishing |
| Mosquitto | Local MQTT broker |
| ESP32 | Runs the Pet Runtime and OLED rendering |
| SwiftUI App | Provides control panel, bitmap rendering, AI display and diagnostics |

---

## Hardware / 硬件配置

Verified OLED setup:

| Part | Value |
|---|---|
| MCU | ESP32 Dev Module |
| Display | SSD1309 128x64 monochrome OLED |
| U8g2 constructor | `U8G2_SSD1309_128X64_NONAME0_F_4W_HW_SPI` |
| OLED CS | GPIO33 |
| OLED DC | GPIO27 |
| OLED RST | GPIO26 |
| Fan PWM | GPIO25 |

Fan note:

ESP32 GPIO pins must not drive a 5V fan directly. Use a MOSFET or transistor driver, power the fan from an external 5V supply, and connect ESP32 GND with the external supply GND.

中文说明：如果接风扇，不能把风扇直接接到 ESP32 GPIO。必须使用 MOSFET / 三极管驱动，外部 5V 供电，并且 ESP32 与外部电源共地。

---

## Repository Layout / 仓库结构

```text
esp32/
  bkb_desk_pet_v6_lite/          ESP32 Arduino firmware
  v5_original/                   Sanitized v5 reference / rollback source

mac/
  macbrain_status_v6.sh          Mac telemetry script

nodered/
  make_flow_v6_lite.py           Node-RED flow generator
  bkb_desk_pet_v6_lite_flow.json Generated Node-RED flow

hammerspoon/
  hammerspoon_bkb_bridge_v6_lite.lua

macos/
  MacESP32Console/               SwiftUI macOS control console

tools/
  deploy_v6_lite.sh              Deploy Mac runtime
  rollback_v5.sh                 Roll back to v5
  test_v6_lite.sh                Test MQTT / state flow
  doctor_v6_5.sh                 v6.5 diagnostics
  package_app_v6_5.sh            Package macOS app

docs/
  Architecture, deployment, rollback, console and expression-engine docs
```

Compatibility note: internal MQTT topics still use `bkb/desk1/...` for compatibility with v5 / v6 retained payloads and deployed firmware. The public-facing product name is **Mac-ESP32 Console** / **Mac-esp32 控制台**.

---

## Quick Start / 快速开始

Full guide: [`docs/DEPLOY_V6_LITE.md`](docs/DEPLOY_V6_LITE.md)

### 1. Clone

```sh
git clone https://github.com/kairkiss/mac-esp32-console.git
cd mac-esp32-console
```

### 2. Install ESP32 dependencies

```sh
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install PubSubClient
arduino-cli lib install ArduinoJson
arduino-cli lib install U8g2
```

### 3. Deploy Mac runtime

```sh
./tools/deploy_v6_lite.sh
```

The script deploys:

```text
~/bin/macbrain_status_v6.sh
~/.hammerspoon/init.lua
~/.node-red/flows.json
```

### 4. Build and upload ESP32 firmware

```sh
arduino-cli compile --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
arduino-cli upload -p /dev/cu.usbserial-0001 --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
```

Replace `/dev/cu.usbserial-0001` with your actual serial port.

### 5. Run the macOS app

```sh
cd macos/MacESP32Console
swift build
swift run MacESP32Console
```

### 6. Run diagnostics

```sh
./tools/doctor_v6_5.sh
```

---

## Node-RED HTTP API

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/mac-esp32/console/status` | Read console status |
| POST | `/mac-esp32/console/bitmap` | Send one bitmap frame |
| POST | `/mac-esp32/console/bitmap/page` | Send paged bitmap content |
| POST | `/mac-esp32/console/scene` | Switch scene |
| POST | `/mac-esp32/console/device` | Device control |
| POST | `/mac-esp32/console/netconfig` | Network configuration |
| POST | `/bkb/mac/event` | Hammerspoon event bridge |

---

## MQTT Topics

Primary topics:

```text
bkb/desk1/mac/state
bkb/desk1/mac/heartbeat
bkb/desk1/pet/config
bkb/desk1/pet/state
bkb/desk1/pet/telemetry
bkb/desk1/cmd/text
bkb/desk1/cmd/bitmap
bkb/desk1/cmd/bitmap/page
bkb/desk1/cmd/scene
bkb/desk1/cmd/device
bkb/desk1/cmd/netconfig
```

Compatibility topics:

```text
bkb/desk1/desired/system
bkb/desk1/desired/face
bkb/desk1/desired/display
```

---

## Local-first Notes / 本地优先说明

This project is designed to run mainly on your own Mac and local network. Keep local runtime data, personal backups, exported flows with personal values, retained MQTT dumps and local preference files out of public commits.

---

## Release

A release may include source tag, release notes and a packaged macOS app zip if locally buildable.

```sh
./tools/package_app_v6_5.sh
```

---

## License / 许可证

No open-source license has been specified yet. Without a `LICENSE` file, this public repository remains copyrighted by default. If you want others to use, modify or redistribute this project, add an explicit license such as MIT, Apache-2.0 or GPL.

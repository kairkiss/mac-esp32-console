# Mac-esp32 控制台

Mac-esp32 控制台是一套 Mac + Node-RED + MQTT + ESP32 + OLED 的桌面状态屏/桌宠系统。

当前版本：`v6.5-diagnostics-setup`

它把 Mac 作为状态发布端，把 ESP32 作为本地 Pet Runtime：

- Mac 采集 CPU、内存、温度、idle、前台 App、锁屏状态。
- Hammerspoon 把锁屏/解锁/App 切换事件发给 Node-RED。
- Node-RED 发布统一 `mac/state`、heartbeat、配置和控制命令。
- ESP32 本地运行 FaceEngine、SceneEngine、OLED 渲染、MacLink、failsafe。
- macOS SwiftUI App 负责中文 bitmap 预览、DeepSeek 流式上屏、Telegram 远程控制、设备状态页和配网。

## 功能

- 128x64 SSD1309 单色 OLED 表情桌宠。
- ESP32 本地表情引擎：
  - happy / focus / busy / power / hot / idle / sleepy / sleep / offline / thinking / reading / replying。
- 中文显示：
  - macOS App 把中文渲染为 128x64 1bpp bitmap。
  - 支持多页消息，每页至少 6 秒。
- DeepSeek：
  - API Key 只保存在本机 Keychain。
  - 回复短句化，并自动流式显示到 OLED。
- Telegram：
  - Bot Token 只保存在本机 Keychain。
  - 支持 chat_id 白名单。
  - 支持 `/show`、`/ask`、`/status`、`/device`、`/wake`。
- 设备管理：
  - App 显示 ESP32 online、fw、IP、RSSI、MQTT、MacLink、mood、scene、screen_on、fan_pct。
  - 支持软唤醒、熄屏、回到表情、测试图、重启 ESP32、开启配网热点。
- 诊断与向导：
  - 首次启动配置向导。
  - App 内检查 Mosquitto、Node-RED、Hammerspoon、Mac 状态脚本、ESP32 在线状态。
  - 自动检测 Mac 局域网 IP，并可一键填入 MQTT_HOST。
- 风扇控制：
  - 固件保留 GPIO25 PWM 风扇控制逻辑。
  - 本仓库不包含真实风扇硬件测试。

## 硬件

已验证的 OLED 配置：

- ESP32 Dev Module
- SSD1309 128x64 OLED
- U8g2 构造：`U8G2_SSD1309_128X64_NONAME0_F_4W_HW_SPI`
- OLED CS: GPIO33
- OLED DC: GPIO27
- OLED RST: GPIO26
- Fan PWM: GPIO25

风扇安全要求：

- ESP32 GPIO 不能直接驱动 5V 风扇。
- 必须使用 MOSFET 或三极管驱动。
- 风扇使用外部 5V 电源。
- ESP32 GND 与 5V 电源 GND 必须共地。

## 仓库结构

```text
esp32/
  bkb_desk_pet_v6_lite/          ESP32 Arduino 固件
  v5_original/                   v5 参考/回滚源码，已脱敏
mac/
  macbrain_status_v6.sh          Mac 状态采集脚本
nodered/
  make_flow_v6_lite.py           Node-RED flow 生成器
  bkb_desk_pet_v6_lite_flow.json 生成后的 flow
hammerspoon/
  hammerspoon_bkb_bridge_v6_lite.lua
macos/
  MacESP32Console/               SwiftUI macOS 控制台 App
tools/
  deploy_v6_lite.sh
  rollback_v5.sh
  test_v6_lite.sh
docs/
  详细架构、部署、回滚、控制台、表达引擎文档
```

> 说明：内部 MQTT topic 仍保留 `bkb/desk1/...`，这是为了兼容 v5/v6 retained payload 和已部署固件。App 对外显示名称已改为 Mac-esp32 控制台。

## 快速部署

详细步骤见 [docs/DEPLOY_V6_LITE.md](docs/DEPLOY_V6_LITE.md)。

最小部署顺序：

1. 安装并启动 Mosquitto。
2. 安装并启动 Node-RED。
3. 部署 `nodered/bkb_desk_pet_v6_lite_flow.json` 到 `~/.node-red/flows.json`。
4. 部署 `mac/macbrain_status_v6.sh` 到 `~/bin/macbrain_status_v6.sh`，并 `chmod +x`。
5. 部署 Hammerspoon bridge 到 `~/.hammerspoon/init.lua`。
6. 用 Arduino CLI 编译并烧录 ESP32。
7. 运行 macOS App。
8. 在 App 的 `诊断与向导` 中运行检查。

## ESP32 编译

安装 core 和库：

```sh
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install PubSubClient
arduino-cli lib install ArduinoJson
arduino-cli lib install U8g2
```

编译：

```sh
arduino-cli compile --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
```

烧录：

```sh
arduino-cli upload -p /dev/cu.usbserial-0001 --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
```

首次使用请在固件中修改：

```cpp
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
const char* MQTT_HOST = "192.168.1.100";
```

也可以使用 ESP32 配网热点：

- AP: `MacESP32-Setup`
- Password: `macesp32`
- Portal: `http://192.168.4.1`

## macOS App

源码：

```sh
cd macos/MacESP32Console
swift build
swift run MacESP32Console
```

App 不会把 DeepSeek API Key、Telegram Token、Wi-Fi 密码写进仓库：

- DeepSeek API Key: macOS Keychain
- Telegram Bot Token: macOS Keychain
- Wi-Fi Password: macOS Keychain
- 普通偏好：UserDefaults

## 诊断

App 内置 `诊断与向导` 板块。也可以在终端运行：

```sh
./tools/doctor_v6_5.sh
```

它会检查本机服务、Node-RED endpoint、Mac 状态脚本、ESP32 在线状态和 Mac MQTT IP。

## Node-RED HTTP API

App 使用这些 endpoint：

- `GET /mac-esp32/console/status`
- `POST /mac-esp32/console/bitmap`
- `POST /mac-esp32/console/bitmap/page`
- `POST /mac-esp32/console/scene`
- `POST /mac-esp32/console/device`
- `POST /mac-esp32/console/netconfig`

Hammerspoon 使用：

- `POST /bkb/mac/event`

## MQTT Topic

主路径：

- `bkb/desk1/mac/state`
- `bkb/desk1/mac/heartbeat`
- `bkb/desk1/pet/config`
- `bkb/desk1/pet/state`
- `bkb/desk1/pet/telemetry`
- `bkb/desk1/cmd/text`
- `bkb/desk1/cmd/bitmap`
- `bkb/desk1/cmd/bitmap/page`
- `bkb/desk1/cmd/scene`
- `bkb/desk1/cmd/device`
- `bkb/desk1/cmd/netconfig`

兼容层：

- `bkb/desk1/desired/system`
- `bkb/desk1/desired/face`
- `bkb/desk1/desired/display`

## 安全说明

仓库不应包含：

- DeepSeek API Key
- Telegram Bot Token
- Wi-Fi 密码
- 私有 retained MQTT payload dump
- live Node-RED 备份
- macOS Keychain / UserDefaults 数据

上传前可运行：

```sh
rg -n --hidden --glob '!.git/**' --glob '!backups/**' '(api[_-]?key|token|password|secret|Bearer|WIFI_PASS)'
```

匹配到源码变量名是正常的；匹配到真实密钥或密码必须先删除。

## Release

本仓库的 GitHub Release 包含：

- 源码 tag
- release notes
- macOS App zip，如本地可构建

## 许可证

当前未指定开源许可证。公开仓库默认保留版权；如果要允许他人复用，请后续添加明确 LICENSE。

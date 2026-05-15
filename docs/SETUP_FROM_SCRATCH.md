# 从零部署 Mac-esp32 控制台

这份文档面向第一次接触项目的人。

## 1. 准备 Mac

需要：

- macOS 13+
- Hammerspoon
- Node.js / npm
- Node-RED
- Mosquitto
- Arduino CLI 或 Arduino IDE
- Swift 5.9+

安装方式可以按自己的环境选择。项目不要求把 DeepSeek 或 Telegram 凭据写入源码。

## 2. 启动 MQTT Broker

默认使用本机 Mosquitto：

```sh
mosquitto -p 1883
```

如果使用 launchd 或 Homebrew service，请确保本机 `1883` 可访问。

检查：

```sh
mosquitto_sub -h 127.0.0.1 -t '#' -v
```

## 3. 部署 Mac 状态脚本

```sh
mkdir -p ~/bin
cp mac/macbrain_status_v6.sh ~/bin/macbrain_status_v6.sh
chmod +x ~/bin/macbrain_status_v6.sh
~/bin/macbrain_status_v6.sh
```

输出必须是单行 JSON。

温度采集优先使用：

```text
/Applications/Stats.app/Contents/Resources/smc list -t
```

没有 Stats.app 时，`temp_c` 会是 `null`，系统仍可运行。

## 4. 部署 Node-RED Flow

生成 flow：

```sh
python3 nodered/make_flow_v6_lite.py
```

部署前备份：

```sh
cp ~/.node-red/flows.json ~/.node-red/flows.json.backup
```

把 `nodered/bkb_desk_pet_v6_lite_flow.json` 合并或导入 Node-RED。

项目提供合并脚本：

```sh
node tools/merge_v6_flow.js ~/.node-red/flows.json nodered/bkb_desk_pet_v6_lite_flow.json /tmp/flows.merged.json
cp /tmp/flows.merged.json ~/.node-red/flows.json
```

重启 Node-RED 后检查：

```sh
curl http://127.0.0.1:1880/mac-esp32/console/status
```

## 5. 部署 Hammerspoon

备份：

```sh
cp ~/.hammerspoon/init.lua ~/.hammerspoon/init.lua.backup
```

复制：

```sh
cp hammerspoon/hammerspoon_bkb_bridge_v6_lite.lua ~/.hammerspoon/init.lua
```

Reload Config 后，应看到加载提示。

## 6. 配置 ESP32 固件

编辑：

```text
esp32/bkb_desk_pet_v6_lite/bkb_desk_pet_v6_lite.ino
```

设置：

```cpp
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
const char* MQTT_HOST = "YOUR_MAC_LAN_IP";
```

获取 Mac 局域网 IP：

```sh
ifconfig | rg 'inet (192\\.168|10\\.|172\\.)'
```

## 7. 编译和烧录 ESP32

```sh
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install PubSubClient
arduino-cli lib install ArduinoJson
arduino-cli lib install U8g2
```

确认端口：

```sh
arduino-cli board list
ls /dev/cu.*
```

编译：

```sh
arduino-cli compile --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
```

烧录：

```sh
arduino-cli upload -p /dev/cu.usbserial-0001 --fqbn esp32:esp32:esp32 esp32/bkb_desk_pet_v6_lite
```

不要在端口不明确时烧录。

## 8. 运行 macOS App

```sh
cd macos/MacESP32Console
swift run MacESP32Console
```

App 默认 Node-RED URL：

```text
http://127.0.0.1:1880
```

在设备页确认：

- Online = true
- fw = v6.4-control-center
- mood 正常变化
- scene 可切换
- screen_on 有状态

第一次启动 App 时会打开配置向导。建议按顺序完成：

1. 测试 Node-RED 和本机服务。
2. 填写 Wi-Fi、Mac MQTT IP 和 MQTT port。
3. 填写可选的 DeepSeek API Key、Telegram Bot Token、chat_id 白名单。
4. 运行最终诊断。

也可以随时打开 `诊断与向导` 板块重新检查系统。

v6.6 起，App 顶部菜单栏会出现一个小 Apple 图标。点击后可以打开主控制台、运行诊断、执行一键连接恢复、启动或停止 Telegram。

## 9. DeepSeek

在 App 中填入 DeepSeek API Key。

API Key 保存在 macOS Keychain，不进入 Git 仓库。

## 10. Telegram

在 App 中填入 Telegram Bot Token。

建议填写允许的 `chat_id` 白名单。

命令：

```text
/show 文字
/ask 问题
/status
/device
/wake
```

## 11. 故障排查

ESP32 没上线：

- 检查 `MQTT_HOST` 是否是 Mac 局域网 IP，不能是 `127.0.0.1`。
- 检查 Mosquitto 是否在 1883。
- 检查 Mac 和 ESP32 是否在同一网络。
- 优先在 App 的 `诊断与向导` 或菜单栏中点击 `修复连接`。

Mac 休眠后 ESP32 显示 offline：

- 打开 App 菜单栏 Apple 图标。
- 点击 `修复连接`。
- 如果仍离线，连接 `MacESP32-Setup` 热点，再用 App 的 `通过配置热点写入` 更新 Wi-Fi/MQTT。

Telegram 重复回复：

- v6.6 已加入单实例锁和 Telegram `update_id` 持久化。
- 如果仍出现重复，先确认系统中只有一个 `MacESP32Console` 进程。

OLED 没显示中文：

- 中文不是 ESP32 字库渲染。
- App 会把中文渲染成 128x64 bitmap，再发送给 ESP32。

App 无法控制设备：

- 确认 Node-RED endpoint 可访问：

```sh
curl http://127.0.0.1:1880/mac-esp32/console/status
```

运行完整诊断：

```sh
./tools/doctor_v6_5.sh
```

风扇不工作：

- 本项目不允许 GPIO 直接接 5V 风扇。
- 必须使用 MOSFET/三极管驱动、外部 5V、共地。

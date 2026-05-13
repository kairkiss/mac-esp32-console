# Mac-esp32 控制台 v6.5 Diagnostics & Setup

v6.5 聚焦安装、诊断和首次配置，不改变 ESP32 表情逻辑，也不做风扇硬件测试。

## 新增内容

- App 新增 `诊断与向导` 板块。
- App 首次启动自动打开配置向导。
- App 可检测：
  - Mosquitto 命令是否存在。
  - Node-RED CLI 是否存在。
  - Arduino CLI 是否存在。
  - Hammerspoon 是否运行。
  - Node-RED 是否运行。
  - MQTT broker `127.0.0.1:1883` 是否可连接。
  - Node-RED `/mac-esp32/console/status` 是否可访问。
  - `~/bin/macbrain_status_v6.sh` 是否可执行且输出合法 JSON。
  - 当前 Mac 局域网 IP。
  - App 中配置的 Mac MQTT IP 是否匹配当前 Mac IP。
  - ESP32 是否在线。
- App 可一键把检测到的 Mac IP 填入 MQTT_HOST。
- 新增终端诊断脚本：
  - `tools/doctor_v6_5.sh`
- 新增 App 打包脚本：
  - `tools/package_app_v6_5.sh`

## 首次配置向导

向导分四步：

1. Node-RED URL 和本机服务测试。
2. Wi-Fi、Mac MQTT IP、MQTT port。
3. DeepSeek API Key、Telegram Bot Token、Telegram chat_id 白名单。
4. 最终诊断。

敏感信息仍然只保存在本机：

- DeepSeek API Key -> macOS Keychain
- Telegram Bot Token -> macOS Keychain
- Wi-Fi Password -> macOS Keychain

## 命令行诊断

```sh
./tools/doctor_v6_5.sh
```

脚本会输出 PASS/WARN/FAIL，并在可能时打印 Node-RED 设备状态。

## 打包 App

```sh
./tools/package_app_v6_5.sh
```

输出：

```text
dist/Mac-esp32-console-v6.5.0-macOS.zip
```

## 限制

- App 只能诊断和软控制已供电的 ESP32。
- 如果 ESP32 物理断电，仍需要人工上电。
- 内部 MQTT topic 暂时仍保留 `bkb/desk1/...` 兼容路径。

# Mac-esp32 控制台 v6.4 Control Center

v6.4 的目标是稳定化现有系统，不扩展风扇硬件功能。

## 主要变化

- App 增加设备状态中心：显示 ESP32 online、fw、IP、RSSI、MQTT、MacLink、mood、scene、screen、fan_pct。
- App 增加软控制：唤醒屏幕、熄屏、清空临时场景、测试图、重启 ESP32、开启配网热点。
- App 增加显示队列：手动文字、DeepSeek、Telegram、Mac 状态统一排队，避免互相抢屏。
- Telegram 增加白名单 chat_id、自动启动监听开关。
- Telegram 新增命令：
  - `/show 文字`
  - `/ask 问题`
  - `/status`
  - `/device`
  - `/wake`
- Node-RED 增加状态查询 endpoint：
  - `GET /mac-esp32/console/status`
- Node-RED 订阅并缓存：
  - `bkb/desk1/pet/state`
  - `bkb/desk1/pet/telemetry`
  - `bkb/desk1/state/online`
- ESP32 增加 device action：
  - `wake`
  - `screen_on`
  - `screen_off`
  - `clear_scene`
  - `test_pattern`
  - `config_portal`
  - `reboot`

## 设备状态判断

Node-RED 会把 retained `pet/state` 和非 retained `pet/telemetry` 合并成 App 可读状态。由于 telemetry 不是每秒发布，v6.4 使用 60 秒新鲜度判断设备在线，避免状态页误判离线。

## Telegram 安全

`允许的 chat_id` 留空时保持兼容，任何 chat 都可用机器人。填写一个或多个 chat_id 后，只允许这些 chat 控制 OLED 和查询设备。

## 限制

- App 只能软唤醒 ESP32；如果 ESP32 被物理断电，App 不能远程开机。
- 风扇硬件仍未测试，v6.4 只显示现有 `fan_pct`。
- MQTT topic root 仍保留旧内部协议，避免破坏 ESP32 / Node-RED / retained payload 兼容。

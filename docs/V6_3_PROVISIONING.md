# BKB Desk Pet v6.3 Provisioning

## What Changed

ESP32 now stores Wi-Fi and MQTT settings in NVS. It also exposes a local setup portal so the device can be recovered when the Mac IP changes or MQTT is unreachable.

## Setup Portal

When enabled, ESP32 starts:

- AP SSID: `BKB-DeskPet-Setup`
- AP password: `bkbdeskpet`
- Portal URL: `http://192.168.4.1`

The same portal is also reachable from the normal LAN IP while ESP32 is online:

`http://<esp32-ip>/status`

`POST /config`

```json
{
  "ssid": "WiFi name",
  "password": "WiFi password",
  "mqtt_host": "192.168.100.xxx",
  "mqtt_port": 1883
}
```

ESP32 saves the config and restarts.

## App Controls

The macOS console now has a `设备与配网` panel:

- Wake screen.
- Start config portal.
- Reboot ESP32.
- Write Wi-Fi/MQTT config while online through Node-RED/MQTT.
- Write Wi-Fi/MQTT config directly through the setup portal.

Physical power cannot be turned on by software. The app can only wake/reboot/control ESP32 while the board is powered.

## Node-RED Endpoints

- `POST /bkb/console/device`
- `POST /bkb/console/netconfig`

MQTT topics:

- `bkb/desk1/cmd/device`
- `bkb/desk1/cmd/netconfig`

## Recovery Flow

If Mac IP changes:

1. Open the console app.
2. Go to `设备与配网`.
3. If ESP32 is still online, fill current Mac IP and click `在线写入并重启`.
4. If ESP32 is offline, connect Mac Wi-Fi to `BKB-DeskPet-Setup`, password `bkbdeskpet`.
5. Fill Wi-Fi and Mac IP, click `通过配置热点写入`.
6. ESP32 restarts and reconnects.

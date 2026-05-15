# ESP32 OTA Update

v7.0.0-alpha1 adds a conservative LAN OTA path for the ESP32 firmware.

## Endpoints

The firmware exposes these HTTP endpoints on the ESP32 IP address:

```text
GET  /ota/status
POST /ota/upload
```

`GET /ota/status` returns:

```json
{
  "ok": true,
  "fw": "v6.4-control-center",
  "fw_version": "v7.0.0-alpha1",
  "free_heap": 123456,
  "sketch_size": 900000,
  "free_sketch_space": 1200000,
  "ota_supported": true,
  "reason": "ready"
}
```

`POST /ota/upload` accepts a raw `.bin` firmware image.

## App Flow

1. Open the Device page.
2. Press `查询 OTA 状态`.
3. Choose a `.bin` file.
4. Upload only when the device is online and `ota_supported=true`.
5. The OLED shows OTA progress and the board reboots after success.

## Partition Requirement

OTA needs enough free sketch space for the uploaded firmware. Many ESP32 boards flashed through Arduino IDE with a no-OTA partition layout cannot accept OTA images safely.

If `/ota/status` reports unsupported or `free_sketch_space` is smaller than the `.bin`, do not force the upload. Reflash once by USB with an OTA-capable partition layout, then use OTA for later updates.

## Safety Rules

- Do not power off the ESP32 during OTA.
- Do not upload non-ESP32 firmware.
- Use OTA only on a trusted local network in alpha1.
- If OTA fails, the current firmware should continue running. Check the OLED and App error text, then retry or fall back to USB flashing.

## Future Work

Future releases can add token enforcement, signed firmware, dual-partition rollback, and update history.

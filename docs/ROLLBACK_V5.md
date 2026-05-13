# Rollback To BKB Desk Node v5

## Restore Live Mac Files

Use the rollback helper. Without an argument, it looks for a pristine v5 backup where the v5 tab was still enabled and the v6 tab did not exist:

```sh
cd "~/mac-esp32-console"
./tools/rollback_v5.sh
```

Or pass a specific known-good v5 backup. For this implementation run, the first pristine backup was:

`~/mac-esp32-console/backups/20260429_192340`

Command:

```sh
./tools/rollback_v5.sh "~/mac-esp32-console/backups/YYYYMMDD_HHMMSS"
```

This restores:
- `~/.node-red/flows.json`
- `~/.hammerspoon/init.lua`
- `~/bin/macbrain_status.sh`

It then reloads Hammerspoon and restarts Node-RED.

## Reflash ESP32 v5

Open and flash:

`esp32/v5_original/esp32_bkb_runtime_v5.ino`

Confirm the v5 Wi-Fi and MQTT settings before flashing.

## Clear Retained MQTT Topics

If v6 retained topics interfere with testing, clear them:

```sh
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/mac/state -r -n
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/mac/heartbeat -r -n
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/pet/config -r -n
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/pet/state -r -n
```

To clear old v5 retained desired topics:

```sh
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/desired/system -r -n
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/desired/face -r -n
mosquitto_pub -h 127.0.0.1 -p 1883 -t bkb/desk1/desired/display -r -n
```

## v5 Original Files

Reference copies are kept in:
- `esp32/v5_original/`
- `mac/v5_original/`
- `nodered/v5_original/`
- `hammerspoon/v5_original/`

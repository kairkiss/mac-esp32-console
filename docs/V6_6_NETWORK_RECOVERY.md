# Mac-esp32 控制台 v6.6 Network Recovery

v6.6 focuses on stability after Mac sleep, window reopen, and network changes.

## What Changed

- The macOS app now owns one app-wide `ConsoleStore` instead of creating a new store for every window.
- The app uses a process lock to avoid multiple running instances.
- Reopening the app or clicking the menu bar item brings the existing console forward instead of starting another Telegram polling loop.
- Telegram polling persists the last processed `update_id`, so old messages are not processed again after restart.
- A menu bar item was added with a small Apple symbol. It shows a compact overview and actions for opening the console, running diagnostics, repairing the connection, and toggling Telegram.
- The app adds a one-click connection repair path:
  - refresh ESP32 status
  - run diagnostics
  - detect current Mac LAN IP
  - update MQTT host when needed
  - refresh ESP32 network config through MQTT when online
  - fall back to the setup portal when offline
  - rerun diagnostics after ESP32 restart
- The build script now launches a real `.app` bundle with Bundle ID `com.biankai.macesp32console`.

## Why This Matters

Before v6.6, closing and reopening windows could create a new `ConsoleStore`.
If Telegram auto-start was enabled, each store could begin polling Telegram.
Multiple app processes could also poll the same bot token, causing duplicated replies.

v6.6 prevents both problems:

- one store per app process
- one process per user session
- one persisted Telegram update offset

## Menu Bar

The menu bar item provides:

- ESP32 online/offline overview
- current mood
- Mac CPU, memory, and temperature snapshot
- Open Console
- Run Diagnostics
- Repair Connection
- Start/Stop Telegram
- Quit

## Connection Repair

Use **修复连接** when:

- Mac wakes from sleep and ESP32 shows offline
- Mac IP changed
- retained MQTT state looks stale
- ESP32 is online but `mac_link` is stale
- setup portal needs a direct Wi-Fi/MQTT write

If ESP32 is online, the app uses the Node-RED/MQTT config path.
If ESP32 is offline, it attempts the direct setup portal path at `http://192.168.4.1`.

## Security

Wi-Fi passwords, DeepSeek API keys, and Telegram bot tokens remain in macOS Keychain.
They are not written to the repository.

## Limitations

- A physically powered-off ESP32 still cannot be turned on by software.
- The setup portal path requires the ESP32 setup AP to be reachable.
- The app is still a local unsigned development bundle.

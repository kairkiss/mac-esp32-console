# BKB Desk Pet v6.2 Expression Engine

## Goal

v6.2 upgrades the ESP32 pet from a small set of state faces into a priority-driven expression engine. Mac/Node-RED still publish state and commands; ESP32 owns mood choice, scene switching, animation, screen policy, fan safety, and failsafe behavior.

## Mood Priority

High to low:

1. `hot`: CPU temperature >= 78C, with cooldown before downshifting.
2. `offline`: Mac state/heartbeat unavailable.
3. `sleep`: Mac locked.
4. `thinking`, `reading`, `replying`: temporary console/AI scenes.
5. `power`, `busy`: heavy CPU/memory load.
6. `focus`: developer apps such as Codex, Terminal, Arduino, Node-RED, Xcode.
7. `sleepy`, `idle`: inactive user, with `sleepy` after about 10 minutes.
8. `happy`, `normal`: ordinary active state.

## Screen-Off Policy

`SLEEP_SCREEN_OFF_MS` defaults to 20 minutes and is configurable through `pet/config`:

```json
{
  "screen": {
    "sleep_screen_off_ms": 1200000
  }
}
```

Sleep-family moods (`sleep`, `sleepy`, `offline`) can turn OLED off after the timeout. ESP32 keeps Wi-Fi, MQTT, MacLink, FanController, and failsafe running. Hot/failsafe and active scenes wake the display.

`pet/state` and `pet/telemetry` now include:

- `current_mood`
- `current_scene`
- `mood_reason`
- `priority`
- `screen_on`
- `inactive_age_ms`
- `screen_off_reason`

## New Scene Topics

- `bkb/desk1/cmd/scene`: currently supports `thinking`.
- `bkb/desk1/cmd/bitmap/page`: page-by-page 128x64 1bpp bitmap upload. ESP32 buffers up to 8 pages and plays them automatically.

Each bitmap page should use at least 6000 ms display time for readable Chinese text.

## Test

Run:

```sh
./tools/test_v6_2_expression.sh
```

For screen-off testing, temporarily publish `sleep_screen_off_ms: 10000`, then hold locked/offline/idle state long enough to observe `screen_on:false`.

# Mac Ecosystem Display

v7.0.0-alpha1 starts moving the OLED from simple text pages toward Mac-aware scenes.

## Display Model

The macOS app now has a `DisplayKit` layer:

- `DisplaySceneID`
- `DisplayLayer`
- `DisplayScenePreset`
- `ScenePresetLibrary`
- `OLEDWidgetRenderer`

The ESP32 still owns local face animation, screen policy, failsafe behavior, MQTT link handling, and compatibility parsing. The Mac app renders richer widgets as 128x64 1bpp bitmaps and sends them through the existing bitmap/page path.

## Scene Presets

First-stage presets:

- `coding`
- `music`
- `calendar`
- `night`
- `dreamcore`
- `diagnostics`
- `ota`
- `network_error`
- `dashboard`

Each preset has an id, title, mood hint, duration, priority, source, render strategy, and preview string.

## Widget Renderers

The app can render:

- Mac metric dashboard: CPU, memory, temperature, fan, foreground app
- Now Playing: title, artist, progress
- Calendar next event placeholder
- Network error page
- OTA progress page
- Dreamcore short text page

## Mac Context

First-stage providers:

- Foreground app and window title via NSWorkspace and best-effort AppleScript.
- Apple Music / Spotify now-playing via best-effort AppleScript.
- Calendar provider placeholder, without forcing EventKit permission yet.

Failures return nil or short diagnostics. They should not block the control console.

## Design Boundary

The Mac app may render high-level scenes and bitmap widgets. It should not go back to the old model of remote-controlling every face frame. ESP32 remains the pet runtime.

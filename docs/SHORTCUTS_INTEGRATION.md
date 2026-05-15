# Shortcuts Integration

Apple Shortcuts can call the local Node-RED HTTP endpoints to control the OLED.

## Display Text

Use `Get Contents of URL`:

```text
POST http://127.0.0.1:1880/bkb/console/text
Content-Type: application/json
```

Body:

```json
{
  "v": 1,
  "text": "hello",
  "duration_ms": 6000,
  "style": "bubble",
  "source": "shortcuts"
}
```

## Display Bitmap

For Chinese or rich layout, render a 128x64 1bpp base64 bitmap first, then:

```text
POST http://127.0.0.1:1880/bkb/console/bitmap
```

## Wake OLED

```text
POST http://127.0.0.1:1880/bkb/console/device
```

Body:

```json
{ "v": 1, "command": "wake", "source": "shortcuts" }
```

## Screen Off

```json
{ "v": 1, "command": "screen_off", "source": "shortcuts" }
```

## Repair Connection

Shortcuts can open the Mac app or call existing local endpoints, but full repair is better triggered from the app because it may update ESP32 network config and run diagnostics.

Future versions may add App Intents for native Shortcuts actions.

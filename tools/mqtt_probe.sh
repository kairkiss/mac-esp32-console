#!/bin/zsh
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-1883}"

if ! command -v mosquitto_sub >/dev/null 2>&1; then
  echo "mosquitto_sub not found; cannot probe MQTT."
  exit 0
fi

echo "[mqtt] retained v6/v5 snapshot from $HOST:$PORT"
for topic in \
  "bkb/desk1/mac/state" \
  "bkb/desk1/mac/heartbeat" \
  "bkb/desk1/pet/config" \
  "bkb/desk1/pet/state" \
  "bkb/desk1/desired/system" \
  "bkb/desk1/desired/face" \
  "bkb/desk1/desired/display"; do
  printf "%s => " "$topic"
  mosquitto_sub -h "$HOST" -p "$PORT" -t "$topic" -C 1 -W 1 2>/dev/null || true
done

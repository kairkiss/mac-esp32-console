#!/usr/bin/env bash
set -euo pipefail

HOST="${MQTT_HOST:-127.0.0.1}"
TOPIC_STATE="bkb/desk1/pet/state"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "$1 not found"; exit 1; }
}

pub_state() {
  local json="$1"
  for _ in 1 2 3 4; do
    mosquitto_pub -h "$HOST" -t bkb/desk1/mac/state -r -m "$json"
    sleep 0.6
  done
}

show_state() {
  mosquitto_sub -h "$HOST" -R -t "$TOPIC_STATE" -C 1 -W 12 -v || true
}

ts() { date +%s; }

need mosquitto_pub
need mosquitto_sub

echo "== focus/dev app =="
pub_state "{\"v\":1,\"ts\":$(ts),\"online\":true,\"locked\":false,\"idle_s\":5,\"app\":\"Codex\",\"cpu_pct\":35,\"mem_pct\":55,\"temp_c\":55,\"time\":\"12:00\",\"mode_hint\":\"focus\"}"
sleep 3
show_state

echo "== busy =="
pub_state "{\"v\":1,\"ts\":$(ts),\"online\":true,\"locked\":false,\"idle_s\":5,\"app\":\"Codex\",\"cpu_pct\":72,\"mem_pct\":80,\"temp_c\":60,\"time\":\"12:00\",\"mode_hint\":\"busy\"}"
sleep 3
show_state

echo "== hot priority =="
pub_state "{\"v\":1,\"ts\":$(ts),\"online\":true,\"locked\":false,\"idle_s\":5,\"app\":\"Codex\",\"cpu_pct\":40,\"mem_pct\":60,\"temp_c\":80,\"time\":\"12:00\",\"mode_hint\":\"hot\"}"
sleep 3
show_state

echo "== idle 10m sleepy =="
pub_state "{\"v\":1,\"ts\":$(ts),\"online\":true,\"locked\":false,\"idle_s\":650,\"app\":\"Finder\",\"cpu_pct\":15,\"mem_pct\":50,\"temp_c\":55,\"time\":\"12:00\",\"mode_hint\":\"idle\"}"
sleep 3
show_state

echo "== locked sleep =="
pub_state "{\"v\":1,\"ts\":$(ts),\"online\":true,\"locked\":true,\"idle_s\":10,\"app\":\"Finder\",\"cpu_pct\":15,\"mem_pct\":50,\"temp_c\":55,\"time\":\"12:00\",\"mode_hint\":\"locked\"}"
sleep 3
show_state

echo "== thinking scene =="
mosquitto_pub -h "$HOST" -t bkb/desk1/cmd/scene -m '{"v":1,"scene":"thinking","duration_ms":5000,"source":"test"}'
sleep 2
show_state

echo "Done. For screen-off timeout testing, publish pet/config with screen.sleep_screen_off_ms=10000 and repeat locked/offline/idle cases."

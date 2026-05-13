#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
FAIL=0

pass() { echo "[PASS] $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[FAIL] $1"; FAIL=1; }

SCRIPT="$HOME/bin/macbrain_status_v6.sh"
[[ -x "$SCRIPT" ]] || SCRIPT="$ROOT/mac/macbrain_status_v6.sh"

echo "[test] macbrain_status_v6"
STATUS_JSON="$($SCRIPT 2>/tmp/bkb_v6_status_err.$$)"
echo "$STATUS_JSON"
if echo "$STATUS_JSON" | node -e '
let s=""; process.stdin.on("data", d=>s+=d); process.stdin.on("end", ()=>{
  try {
    const j=JSON.parse(s);
    if (j.temp_c !== null && typeof j.temp_c !== "number") process.exit(3);
    if (typeof j.cpu_pct !== "number" || typeof j.mem_pct !== "number") process.exit(4);
  } catch(e) { process.exit(2); }
});'; then pass "status JSON valid"; else fail "status JSON invalid"; fi
rm -f /tmp/bkb_v6_status_err.$$

echo "[test] Node-RED HTTP"
if curl -fsS http://127.0.0.1:1880/ >/dev/null 2>&1; then pass "Node-RED 1880 reachable"; else fail "Node-RED 1880 not reachable"; fi

for payload in '{"event":"locked"}' '{"event":"unlocked"}' '{"event":"app","app":"Codex Test"}'; do
  if curl -fsS -H 'Content-Type: application/json' -d "$payload" http://127.0.0.1:1880/bkb/mac/event >/tmp/bkb_v6_http.$$ 2>/dev/null; then
    pass "POST $payload -> $(cat /tmp/bkb_v6_http.$$)"
  else
    fail "POST $payload failed"
  fi
done
rm -f /tmp/bkb_v6_http.$$

if ! command -v mosquitto_sub >/dev/null 2>&1 || ! command -v mosquitto_pub >/dev/null 2>&1; then
  warn "mosquitto_pub/sub missing; MQTT tests skipped without installing dependencies"
  exit $FAIL
fi

echo "[test] MQTT retained topics"
for topic in "bkb/desk1/mac/state" "bkb/desk1/mac/heartbeat" "bkb/desk1/pet/config"; do
  out="$(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -C 1 -W 3 2>&1)"
  if echo "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{JSON.parse(s);process.exit(0)}catch(e){process.exit(1)}});'; then
    pass "$topic => $out"
  else
    fail "$topic missing or invalid: $out"
  fi
done

echo "[test] simulate mac/state cases"
for temp in 50 70 90; do
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/mac/state" -r -m "{\"v\":1,\"ts\":$(date +%s),\"online\":true,\"locked\":false,\"idle_s\":5,\"app\":\"Codex Test\",\"cpu_pct\":30,\"mem_pct\":50,\"temp_c\":$temp,\"thermal_source\":\"test\",\"time\":\"12:00\",\"mode_hint\":\"active\"}"
  sleep 1
  state="$(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/pet/state" -C 1 -W 3 2>&1)"
  echo "temp=$temp pet/state: $state"
done

mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/mac/state" -r -m "{\"v\":1,\"ts\":$(date +%s),\"online\":true,\"locked\":false,\"idle_s\":5,\"app\":\"Load Test\",\"cpu_pct\":95,\"mem_pct\":70,\"temp_c\":null,\"thermal_source\":\"unavailable\",\"time\":\"12:00\",\"mode_hint\":\"busy\"}"
sleep 1
echo "cpu high pet/state: $(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/pet/state" -C 1 -W 3 2>&1)"

mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/mac/state" -r -m "{\"v\":1,\"ts\":$(date +%s),\"online\":true,\"locked\":false,\"idle_s\":300,\"app\":\"Finder\",\"cpu_pct\":10,\"mem_pct\":40,\"temp_c\":45,\"thermal_source\":\"test\",\"time\":\"12:00\",\"mode_hint\":\"idle\"}"
sleep 1
echo "idle high pet/state: $(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/pet/state" -C 1 -W 3 2>&1)"

mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "bkb/desk1/mac/heartbeat" -r -m "{\"v\":1,\"ts\":$(date +%s),\"seq\":999,\"online\":false}"
warn "offline timeout is time-based on ESP32; observe pet/state after >60s if device is connected."

exit $FAIL

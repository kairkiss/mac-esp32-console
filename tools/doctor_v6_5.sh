#!/bin/zsh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

pass() { print "[PASS] $1"; }
warn() { print "[WARN] $1"; }
fail() { print "[FAIL] $1"; FAIL=1; }

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1: $(command -v "$1")"
  else
    warn "$1 not found"
  fi
}

print "[doctor] Mac-esp32 控制台 v6.5"

need_cmd node
need_cmd node-red
need_cmd mosquitto
need_cmd mosquitto_pub
need_cmd mosquitto_sub
need_cmd swift

if command -v arduino-cli >/dev/null 2>&1; then
  pass "arduino-cli: $(command -v arduino-cli)"
elif [[ -x "/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli" ]]; then
  pass "arduino-cli: /Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"
else
  warn "arduino-cli not found"
fi

if pgrep -fl node-red >/dev/null 2>&1; then
  pass "Node-RED process running"
else
  fail "Node-RED process not running"
fi

if pgrep -fl Hammerspoon >/dev/null 2>&1; then
  pass "Hammerspoon process running"
else
  fail "Hammerspoon process not running"
fi

if nc -z -G 2 127.0.0.1 1883 >/dev/null 2>&1; then
  pass "MQTT broker reachable at 127.0.0.1:1883"
else
  fail "MQTT broker not reachable at 127.0.0.1:1883"
fi

if curl -fsS "http://127.0.0.1:1880/mac-esp32/console/status" >/tmp/mac_esp32_status.$$ 2>/dev/null; then
  pass "Node-RED /mac-esp32/console/status reachable"
  cat /tmp/mac_esp32_status.$$
  print
else
  fail "Node-RED status endpoint not reachable"
fi
rm -f /tmp/mac_esp32_status.$$

SCRIPT="$HOME/bin/macbrain_status_v6.sh"
if [[ ! -x "$SCRIPT" ]]; then
  SCRIPT="$ROOT/mac/macbrain_status_v6.sh"
fi
if [[ -x "$SCRIPT" ]]; then
  if "$SCRIPT" | python3 -m json.tool >/dev/null 2>&1; then
    pass "macbrain_status_v6.sh JSON valid"
  else
    fail "macbrain_status_v6.sh JSON invalid"
  fi
else
  fail "macbrain_status_v6.sh not executable"
fi

print "[doctor] Local IP candidates"
ifconfig | grep -E 'inet (192\.168|10\.|172\.)' || warn "No LAN IP candidate found"

exit $FAIL

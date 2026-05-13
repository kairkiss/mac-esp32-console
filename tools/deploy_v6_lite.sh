#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$ROOT/backups/$STAMP"
mkdir -p "$BACKUP"

echo "[deploy] backup: $BACKUP"
cp -p "$HOME/.node-red/flows.json" "$BACKUP/flows.json"
cp -p "$HOME/.hammerspoon/init.lua" "$BACKUP/init.lua"
cp -p "$HOME/bin/macbrain_status.sh" "$BACKUP/macbrain_status.sh" 2>/dev/null || true
cp -p "$HOME/bin/macbrain_status_v6.sh" "$BACKUP/macbrain_status_v6.sh" 2>/dev/null || true

echo "[deploy] macbrain_status_v6.sh"
mkdir -p "$HOME/bin"
cp -p "$ROOT/mac/macbrain_status_v6.sh" "$HOME/bin/macbrain_status_v6.sh"
chmod +x "$HOME/bin/macbrain_status_v6.sh"

echo "[deploy] Hammerspoon bridge"
awk '
  /^-- BKB Desk Node v[0-9]/ { exit }
  /^-- BKB Desk Pet v6 Lite bridge/ { exit }
  /^-- BKB v6 Lite bridge begin/ { exit }
  { print }
' "$BACKUP/init.lua" > "$BACKUP/init.lua.base"
{
  cat "$BACKUP/init.lua.base"
  printf "\n-- BKB v6 Lite bridge begin\n"
  cat "$ROOT/hammerspoon/hammerspoon_bkb_bridge_v6_lite.lua"
  printf "\n-- BKB v6 Lite bridge end\n"
} > "$HOME/.hammerspoon/init.lua"

echo "[deploy] Node-RED flow merge"
"$ROOT/nodered/make_flow_v6_lite.py" >/dev/null
node "$ROOT/tools/merge_v6_flow.js" \
  "$HOME/.node-red/flows.json" \
  "$ROOT/nodered/bkb_desk_pet_v6_lite_flow.json" \
  "$HOME/.node-red/flows.json"

echo "[deploy] reload Hammerspoon"
open -g "hammerspoon://reload" || true

echo "[deploy] restart Node-RED"
if pgrep -f "node-red" >/dev/null; then
  pkill -f "node-red" || true
  sleep 2
fi
nohup node-red > "$HOME/.node-red/logs/v6_lite_node_red.log" 2>&1 &
sleep 4

echo "[deploy] done"
echo "$BACKUP"

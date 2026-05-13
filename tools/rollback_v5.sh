#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP="${1:-}"

if [[ -z "$BACKUP" ]]; then
  for candidate in "$ROOT"/backups/*; do
    [[ -d "$candidate" && -f "$candidate/flows.json" ]] || continue
    if node -e '
      const f=require(process.argv[1]);
      const tabs=f.filter(n=>n.type==="tab");
      const hasV6=tabs.some(t=>t.label==="BKB Desk Pet v6 Lite");
      const v5=tabs.find(t=>t.label==="BKB Desk Node v5");
      process.exit(!hasV6 && v5 && !v5.disabled ? 0 : 1);
    ' "$candidate/flows.json" >/dev/null 2>&1; then
      BACKUP="$candidate"
      break
    fi
  done
fi

if [[ -z "$BACKUP" || ! -d "$BACKUP" ]]; then
  echo "No backup directory found. Pass one explicitly." >&2
  exit 1
fi

echo "[rollback] using $BACKUP"
cp -p "$BACKUP/flows.json" "$HOME/.node-red/flows.json"
cp -p "$BACKUP/init.lua" "$HOME/.hammerspoon/init.lua"
if [[ -f "$BACKUP/macbrain_status.sh" ]]; then
  cp -p "$BACKUP/macbrain_status.sh" "$HOME/bin/macbrain_status.sh"
  chmod +x "$HOME/bin/macbrain_status.sh"
fi

open -g "hammerspoon://reload" || true
if pgrep -f "node-red" >/dev/null; then
  pkill -f "node-red" || true
  sleep 2
fi
nohup node-red > "$HOME/.node-red/logs/rollback_node_red.log" 2>&1 &

echo "[rollback] restored live files. Reflash esp32/v5_original/esp32_bkb_runtime_v5.ino manually if ESP32 was flashed to v6."

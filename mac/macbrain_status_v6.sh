#!/bin/zsh

# BKB Desk Pet v6 Lite Mac Brain status publisher.
# stdout must be exactly one JSON object. Any partial failure degrades to null/defaults.

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'
}

run_timeout() {
  local seconds="$1"
  shift
  /usr/bin/perl -e '$SIG{ALRM}=sub{exit 124}; alarm shift @ARGV; exec @ARGV' "$seconds" "$@"
}

num_or_zero() {
  local v="$1"
  if [[ "$v" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
    printf '%.0f' "$v"
  else
    printf '0'
  fi
}

ts=$(date +%s 2>/dev/null)
[[ -z "$ts" ]] && ts=0

cpu=$(ps -A -o %cpu 2>/dev/null | awk -v c="$(sysctl -n hw.logicalcpu 2>/dev/null)" '
NR>1 { s += $1 }
END {
  if (c < 1) c = 1;
  if (s < 0) s = 0;
  printf "%.0f", s / c;
}')
cpu=$(num_or_zero "$cpu")
(( cpu > 100 )) && cpu=100

vm=$(vm_stat 2>/dev/null)
free=$(printf '%s\n' "$vm" | awk '/Pages free/ {gsub("\\.","",$3); print $3+0}')
spec=$(printf '%s\n' "$vm" | awk '/Pages speculative/ {gsub("\\.","",$3); print $3+0}')
active=$(printf '%s\n' "$vm" | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
inactive=$(printf '%s\n' "$vm" | awk '/Pages inactive/ {gsub("\\.","",$3); print $3+0}')
wired=$(printf '%s\n' "$vm" | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')
compressed=$(printf '%s\n' "$vm" | awk '/Pages occupied by compressor/ {gsub("\\.","",$5); print $5+0}')
mem=$(awk -v free="$free" -v spec="$spec" -v active="$active" -v inactive="$inactive" -v wired="$wired" -v compressed="$compressed" '
BEGIN {
  total = free + spec + active + inactive + wired + compressed;
  used = active + wired + compressed;
  if (total <= 0) print 0;
  else printf "%.0f", used / total * 100;
}')
mem=$(num_or_zero "$mem")
(( mem > 100 )) && mem=100

idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {printf "%.0f", $NF / 1000000000; exit}')
idle=$(num_or_zero "$idle")

time_now=$(date +"%H:%M" 2>/dev/null)
[[ -z "$time_now" ]] && time_now="--:--"

locked_raw=$(ioreg -n Root -d1 2>/dev/null | grep CGSSessionScreenIsLocked)
if printf '%s' "$locked_raw" | grep -q Yes; then
  locked=true
else
  locked=false
fi

app=$(run_timeout 2 /usr/bin/osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
[[ -z "$app" ]] && app="Unknown"
app=$(json_escape "$app")

temp_c="null"
thermal_source="unavailable"
smc_tool="/Applications/Stats.app/Contents/Resources/smc"
if [[ -x "$smc_tool" ]]; then
  temp_raw=$(run_timeout 2 "$smc_tool" list -t 2>/dev/null | awk '
    /^\[TC/ {
      v = $2 + 0;
      if (v >= 10 && v <= 110 && v > max) max = v;
    }
    END {
      if (max > 0) printf "%.0f", max;
    }')
  if [[ "$temp_raw" =~ '^[0-9]+$' ]]; then
    temp_c="$temp_raw"
    thermal_source="stats_smc"
  fi
fi

printf '{"v":1,"ts":%s,"online":true,"locked":%s,"cpu_pct":%s,"mem_pct":%s,"temp_c":%s,"thermal_source":"%s","time":"%s","idle_s":%s,"app":"%s"}\n' \
  "$ts" "$locked" "$cpu" "$mem" "$temp_c" "$thermal_source" "$time_now" "$idle" "$app"

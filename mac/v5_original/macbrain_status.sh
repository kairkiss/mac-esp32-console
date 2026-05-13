#!/bin/zsh
cpu=$(ps -A -o %cpu | awk -v c=$(sysctl -n hw.logicalcpu) 'NR>1{s+=$1} END{if(c<1)c=1; printf "%.0f", s/c}')
vm=$(vm_stat)
free=$(echo "$vm" | awk '/Pages free/ {gsub("\\.","",$3); print $3+0}')
spec=$(echo "$vm" | awk '/Pages speculative/ {gsub("\\.","",$3); print $3+0}')
active=$(echo "$vm" | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
inactive=$(echo "$vm" | awk '/Pages inactive/ {gsub("\\.","",$3); print $3+0}')
wired=$(echo "$vm" | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')
compressed=$(echo "$vm" | awk '/Pages occupied by compressor/ {gsub("\\.","",$5); print $5+0}')
mem=$(awk -v free="$free" -v spec="$spec" -v active="$active" -v inactive="$inactive" -v wired="$wired" -v compressed="$compressed" 'BEGIN{total=free+spec+active+inactive+wired+compressed; used=active+wired+compressed; if(total<=0)print 0; else printf "%.0f", used/total*100}')
idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {printf "%.0f", $NF/1000000000; exit}')
[ -z "$idle" ] && idle=0
time_now=$(date +"%H:%M")
app=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
[ -z "$app" ] && app="Unknown"
app=$(echo "$app" | sed 's/\\/\\\\/g; s/"/\\"/g')
[ -z "$cpu" ] && cpu=0
[ -z "$mem" ] && mem=0
echo "{\"cpu\":$cpu,\"mem\":$mem,\"time\":\"$time_now\",\"idle\":$idle,\"app\":\"$app\"}"

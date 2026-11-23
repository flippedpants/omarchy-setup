#!/bin/bash
# Resume heartbeat: tells "machine hung" apart from "machine alive but screen black".
# Run as your user in a terminal before a test:  ~/work/kernel-investigation/tools/heartbeat.sh &
# It appends a line every 2 s and forces it to disk. After a forced power-off, the last line
# shows whether the system was running after resume (and for how long).
F=/home/dakshgupta/work/kernel-investigation/runs/heartbeat-$(cat /proc/sys/kernel/random/boot_id).log
mkdir -p "$(dirname "$F")"
while :; do
  printf '%s mono=%s\n' "$(date -Is)" "$(cut -d' ' -f1 /proc/uptime)" >> "$F"
  sync -d "$F" 2>/dev/null || sync "$F"
  sleep 2
done

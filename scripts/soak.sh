#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Overnight soak test (M6 6.5): samples Notched every few minutes into a CSV so
# CPU, memory and leaks over hours can be read in the morning.
#
# Usage: scripts/soak.sh [hours=8] [interval_seconds=600]
#
# Leave Notched running with the modules you use, then start this in a Terminal
# window and leave the Mac awake and plugged in (the script runs `caffeinate`
# so the system doesn't idle-sleep; a closed lid still sleeps it, and the CSV
# will show the gap). Each row:
#   time, cpu_percent (over the interval, Notched + children, from cumulative
#   CPU time like cpu.sh), rss_mb, footprint_mb, threads, open_files,
#   children, shells (stray terminal shells: should be 0 unless you opened one)
# A summary prints at the end, with how much memory, threads and files grew.
set -uo pipefail
hours="${1:-8}"
interval="${2:-600}"
pid=$(pgrep -x Notched | head -1) || { echo "Notched is not running"; exit 1; }

out_dir="$HOME/Library/Logs/Notched"
mkdir -p "$out_dir"
csv="$out_dir/soak-$(date +%Y%m%d-%H%M).csv"
echo "time,cpu_percent,rss_mb,footprint_mb,threads,open_files,children,shells" > "$csv"

caffeinate -i -w $$ &

cpu_seconds() {
  ps -o time= -p "$1" 2>/dev/null | awk '{
    n = split($1, part, /[-:]/); total = 0; weight = 1
    for (i = n; i >= 1; i--) {
      total += part[i] * weight
      weight = (i == n - 2) ? 24 * 3600 : weight * 60
    }
    printf "%.2f\n", total }'
}

# Notched's CPU seconds plus its direct children's, as of now.
total_cpu() {
  local sum
  sum=$(cpu_seconds "$pid")
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    sum=$(awk -v a="$sum" -v b="$(cpu_seconds "$child")" 'BEGIN { printf "%.2f", a + b }')
  done
  echo "$sum"
}

samples=$(( hours * 3600 / interval ))
echo "Soaking Notched (PID $pid) for ${hours} h: $samples samples every ${interval} s → $csv"
last=$(total_cpu)
for ((i = 1; i <= samples; i++)); do
  sleep "$interval"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "$(date +%H:%M:%S),Notched exited,,,,,," >> "$csv"
    echo "Notched exited at sample $i. See the crash report in ~/Library/Logs/DiagnosticReports."
    break
  fi
  now=$(total_cpu)
  cpu=$(awk -v a="$now" -v b="$last" -v s="$interval" 'BEGIN { printf "%.3f", (a - b) / s * 100 }')
  last=$now
  rss=$(ps -o rss= -p "$pid" | awk '{ printf "%.1f", $1 / 1024 }')
  foot=$(footprint -p "$pid" 2>/dev/null | awk '/phys_footprint:|Footprint:/ { v=$2; u=$3; if (u ~ /GB/) v*=1024; else if (u ~ /KB/) v/=1024; printf "%.1f", v; exit }')
  threads=$(ps -M -p "$pid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  files=$(lsof -p "$pid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  children=$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')
  shells=$(pgrep -P "$pid" -x -f '(zsh|bash|sh|fish)' 2>/dev/null | wc -l | tr -d ' ')
  echo "$(date +%H:%M:%S),$cpu,$rss,${foot:-},$threads,$files,$children,$shells" >> "$csv"
done

echo
echo "Summary (from $csv):"
awk -F, 'NR > 1 && $2 ~ /^[0-9.]+$/ {
  n++; cpu += $2; if ($2 > maxcpu) maxcpu = $2
  if (n == 1) { r0 = $3; t0 = $5; f0 = $6 }
  r1 = $3; t1 = $5; f1 = $6
  if ($3 > maxrss) maxrss = $3
} END {
  if (n == 0) { print "  no samples"; exit }
  printf "  %d samples, CPU average %.3f %%, peak %.3f %%\n", n, cpu / n, maxcpu
  printf "  resident memory first %.1f MB → last %.1f MB (peak %.1f MB, change %+.1f MB)\n", r0, r1, maxrss, r1 - r0
  printf "  threads %d → %d, open files %d → %d\n", t0, t1, f0, f1
  print "  Budget: CPU average < 0.5 %, memory < 150 MB, and no steady growth in memory, threads or open files."
}' "$csv"

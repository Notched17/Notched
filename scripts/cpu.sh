#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Precise CPU and memory for Notched (CLAUDE.md budget; ADR-0010 method).
#
# Reads each process's cumulative CPU time (`ps -o time`, 0.01 s steps) at
# the start and end of a window, so a 60 s window resolves 0.02 % of one
# core, far finer than `top`'s samples. Child processes (the media
# adapter's perl helper) are measured too and added to the total.
#
# Usage: scripts/cpu.sh [seconds=60] [label]
#   scripts/cpu.sh 60 "timer running, compact"
set -euo pipefail
seconds="${1:-60}"
label="${2:-}"
pid=$(pgrep -x Notched | head -1) || { echo "Notched is not running"; exit 1; }

# ps prints [[dd-]hh:]mm:ss.cc; print it as seconds.
cpu_seconds() {
  ps -o time= -p "$1" 2>/dev/null | awk '{
    n = split($1, part, /[-:]/); total = 0; weight = 1
    for (i = n; i >= 1; i--) {
      total += part[i] * weight
      weight = (i == n - 2) ? 24 * 3600 : weight * 60
    }
    printf "%.2f\n", total }'
}

name_of() { ps -o comm= -p "$1" 2>/dev/null | xargs basename 2>/dev/null || echo "?"; }

pids=("$pid")
while read -r child; do [[ -n "$child" ]] && pids+=("$child"); done < <(pgrep -P "$pid" || true)

declare -a before
for i in "${!pids[@]}"; do before[$i]=$(cpu_seconds "${pids[$i]}"); done
echo "Measuring Notched (PID $pid) and ${#pids[@]} process(es) for ${seconds}s${label:+ — $label}…"
sleep "$seconds"

total=0
for i in "${!pids[@]}"; do
  p=${pids[$i]}
  after=$(cpu_seconds "$p")
  if [[ -z "$after" || -z "${before[$i]}" ]]; then
    printf "  %-24s exited during the window\n" "$(name_of "$p") ($p)"
    continue
  fi
  used=$(awk -v a="$after" -v b="${before[$i]}" 'BEGIN { printf "%.2f", a - b }')
  percent=$(awk -v u="$used" -v s="$seconds" 'BEGIN { printf "%.3f", u / s * 100 }')
  total=$(awk -v t="$total" -v u="$used" 'BEGIN { printf "%.2f", t + u }')
  printf "  %-24s %7s %%  (%s s CPU)\n" "$(name_of "$p") ($p)" "$percent" "$used"
done
printf "  %-24s %7s %%\n" "Total" "$(awk -v t="$total" -v s="$seconds" 'BEGIN { printf "%.3f", t / s * 100 }')"

footprint -p "$pid" 2>/dev/null | grep -E "^\s*(Footprint|phys_footprint):" | head -1 | sed 's/^ */  /' || true
ps -o rss= -p "$pid" | awk '{ printf "  Resident set %.1f MB\n", $1 / 1024 }'

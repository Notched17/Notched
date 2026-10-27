#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Measures Notched's idle CPU and memory (CLAUDE.md budget: CPU < 0.5%,
# memory < 120 MB). Samples `top` every 2 s for the given duration.
# Usage: scripts/perf.sh [seconds=60]
set -euo pipefail
seconds="${1:-60}"
pid=$(pgrep -x Notched | head -1) || { echo "Notched is not running"; exit 1; }
samples=$(( seconds / 2 + 1 ))
echo "Sampling PID $pid for ${seconds}s ($samples samples)…"
top -l "$samples" -s 2 -pid "$pid" -stats pid,cpu,mem 2>/dev/null \
  | awk -v pid="$pid" '$1 == pid { n++; if (n > 1) { cpu += $2; if ($2 > max) max = $2 }; mem = $3 }
      END { printf "CPU mean %.2f%%  max %.2f%%  (%d samples)\nMemory (top) %s\n", cpu / (n - 1), max, n - 1, mem }'
footprint -p "$pid" 2>/dev/null | grep -E "Footprint|phys_footprint" | head -2 || true
ps -o rss= -p "$pid" | awk '{ printf "Resident set %.1f MB\n", $1 / 1024 }'

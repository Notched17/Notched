#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# The per-module performance table (M6 6.5): idle CPU and memory with each
# module on by itself, then with all of them on. Needs a Debug build, because
# it uses the notched://debug/ URLs, and the installed app at
# ~/Applications/Notched.app. Active-state rows (playing media, a running timer,
# a download) can't be scripted safely; the script prints what to do for them
# and waits for you.
#
# Usage: scripts/perf-table.sh [seconds=30]
# Output: a Markdown table on screen and in ~/Library/Logs/Notched/perf-table.md
set -uo pipefail
cd "$(dirname "$0")/.."
seconds="${1:-30}"
here=$(pwd)
modules=(media timers keepawake battery bluetooth network capslock sensors calls downloads hud activityapi claudecode colorpicker clipboard calendar reminders weather terminal)
out="$HOME/Library/Logs/Notched/perf-table.md"
mkdir -p "$(dirname "$out")"

pgrep -x Notched >/dev/null || { echo "Start Notched first (scripts/install.sh)"; exit 1; }
url() { open -g "notched://debug/$1"; }

set_modules() { # $1 = on|off, rest = ids
  local state="$1"; shift
  for m in "$@"; do url "module?id=$m&on=$([[ $state == on ]] && echo 1 || echo 0)"; done
  sleep 3
}

measure() { # prints "cpu% | rss MB"
  local result cpu rss
  result=$("$here/scripts/cpu.sh" "$seconds" "$1" 2>&1)
  cpu=$(echo "$result" | awk '/ Total /{print $2}')
  rss=$(echo "$result" | awk '/Resident set/{print $3}')
  echo "${cpu:-?} | ${rss:-?}"
}

url "close-windows"; url "collapse"
echo "Turning every module off first…"
set_modules off "${modules[@]}"
sleep 5

{
  echo "# Notched performance, $(date '+%Y-%m-%d'), $(sysctl -n hw.model), macOS $(sw_vers -productVersion)"
  echo
  echo "Idle, island collapsed, ${seconds} s windows, Notched and its child processes (scripts/cpu.sh)."
  echo
  echo "| Module | CPU % | Memory MB |"
  echo "|---|---|---|"
  echo "| (none on) | $(measure 'no modules') |"
} | tee "$out"

for m in "${modules[@]}"; do
  set_modules on "$m"
  row="| $m | $(measure "$m only") |"
  echo "$row" | tee -a "$out"
  set_modules off "$m"
done

echo "Now every module on at once…"
set_modules on "${modules[@]}"
echo "| **all on** | $(measure 'all modules') |" | tee -a "$out"

cat <<'TXT' | tee -a "$out"

Active states to measure by hand (leave all modules on; run `scripts/cpu.sh 60 "<label>"` for each):
- Now Playing: `scripts/test-player` playing, island compact, then expanded.
- Timer running (`open "notched://timer?minutes=10&label=soak"`).
- Keep Awake on.
- A download in progress.
- Clipboard: copy ten things, then idle.
- Terminal tab open with `top` running.
- Claude Code hooks sending events.
TXT
echo
echo "Saved to $out"

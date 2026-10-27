#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Opens a Settings pane, brings the app forward and captures the window.
# Usage: scripts/settings-shot.sh <pane> <output.png>
set -euo pipefail
cd "$(dirname "$0")/.."
open -g "notched://debug/settings?pane=$1"
sleep 0.4
open "$HOME/Applications/Notched.app"
sleep 1.2
window=$(swift scripts/window-shot.swift "")
screencapture -x -o -l"$window" "$2"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Notched's CPU and memory against the CLAUDE.md budget (idle CPU < 0.5%,
# memory < 150 MB with every module on). A thin wrapper around cpu.sh, which
# measures from cumulative CPU time (precise to ~0.02 % over 60 s) and
# includes child processes such as the media adapter.
# Usage: scripts/perf.sh [seconds=60] [label]
#   For a Now Playing measurement, start `scripts/test-player` first.
set -euo pipefail
exec "$(dirname "$0")/cpu.sh" "${1:-60}" "${2:-}"

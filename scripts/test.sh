#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerate the project and run the unit tests. Full log: build/test.log
#
# Watchdog: with Xcode 27.1, a run with failing Swift Testing tests can leave
# the test host waiting forever inside XCTWaiter after the summary is printed,
# so xcodebuild never returns. Once the summary appears, give the host 30 s to
# exit, then stop it so the failures are reported.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --quiet
xcodebuild -project Notched.xcodeproj -scheme Notched -derivedDataPath build test > build/test.log 2>&1 &
build_pid=$!
host="build/Build/Products/Debug/Notched.app/Contents/MacOS/Notched"
summary_seen=""
while kill -0 "$build_pid" 2>/dev/null; do
  if [[ -z "$summary_seen" ]] && grep -qE "^(✔|✘) Test run with" build/test.log 2>/dev/null; then
    summary_seen=$SECONDS
  fi
  if [[ -n "$summary_seen" ]] && (( SECONDS - summary_seen > 30 )); then
    echo "Test host didn't exit after the run; stopping it."
    pkill -f "$host" 2>/dev/null
    summary_seen=$SECONDS
  fi
  sleep 1
done
wait "$build_pid"
status=$?
grep -E "error:|warning:|✘|recorded an issue" build/test.log | grep -v -E "iOSSimulator|appintentsmetadataprocessor" | sort -u | head -40
grep -E "^✔ Test run|^✘ Test run|\*\* TEST" build/test.log | tail -2
exit $status

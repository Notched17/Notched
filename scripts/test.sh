#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerate the project and run the unit tests. Full log: build/test.log
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --quiet
xcodebuild -project Notched.xcodeproj -scheme Notched -derivedDataPath build test > build/test.log 2>&1
status=$?
grep -E "error:|warning:|✘|recorded an issue" build/test.log | grep -v -E "iOSSimulator|appintentsmetadataprocessor" | sort -u | head -40
grep -E "^✔ Test run|^✘ Test run|\*\* TEST" build/test.log | tail -2
exit $status

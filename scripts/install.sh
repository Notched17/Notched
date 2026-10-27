#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build DynamicNotch, install it to ~/Applications (a stable location, so macOS
# keeps its permission grants), and relaunch it.
# Usage: scripts/install.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-Debug}"
app_name="DynamicNotch.app"
dest="$HOME/Applications/$app_name"

xcodegen generate --quiet
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration "$config" \
  -derivedDataPath build build -quiet

pkill -x DynamicNotch 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$dest"
ditto "build/Build/Products/$config/$app_name" "$dest"
open "$dest"
echo "Installed and launched $dest ($config)"

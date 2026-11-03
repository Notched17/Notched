#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a Release Notched.app and packs it for a GitHub Release:
#   build/release/Notched.zip          the app, and nothing else
#   build/release/Notched.zip.sha256   its checksum (install-from-release.sh checks it)
#
# Usage: scripts/package-release.sh
# Nothing is uploaded; you attach the two files to a GitHub Release yourself
# (see docs/RELEASING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Notched.xcodeproj -scheme Notched -configuration Release \
  -derivedDataPath build build -quiet

app="build/Build/Products/Release/Notched.app"
[[ -d "$app" ]] || { echo "error: $app was not built" >&2; exit 1; }

echo "→ Checking the signature"
codesign --verify --deep --strict "$app"

echo "→ Checking the bundle holds only the app"
# THIRD_PARTY_NOTICES.md is meant to ship: the licences require the attributions.
extras="$(find "$app" \( -iname '*.md' -o -iname 'docs' -o -iname 'private' -o -iname '*Tests*' -o -iname '.git*' \) ! -name THIRD_PARTY_NOTICES.md | head -5)"
if [[ -n "$extras" ]]; then
  echo "error: unexpected files inside the app:" >&2
  echo "$extras" >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"

out="build/release"
rm -rf "$out"
mkdir -p "$out"
ditto -c -k --keepParent "$app" "$out/Notched.zip"
(cd "$out" && shasum -a 256 Notched.zip > Notched.zip.sha256)

echo
echo "Notched $version packed:"
ls -lh "$out/Notched.zip" "$out/Notched.zip.sha256" | awk '{print "  " $5 "  " $9}'
echo "Attach both files to the GitHub Release (docs/RELEASING.md)."

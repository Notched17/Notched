#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs the latest Notched release from GitHub into ~/Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/Notched17/Notched/main/scripts/install-from-release.sh | bash
#
# Why a script: a file downloaded with curl does not get macOS's "quarantine"
# flag, so Gatekeeper does not block it (Notched is not notarised yet). Read the
# script before you run it: it only downloads Notched.zip from this project's
# GitHub Releases, checks it against the published SHA-256, unzips it into
# ~/Applications and opens it. It never uses sudo.
#
# Optional environment variables (for testing):
#   NOTCHED_URL      the zip to download (default: the latest GitHub release)
#   NOTCHED_SHA_URL  its .sha256 file (default: NOTCHED_URL + ".sha256"; "skip" to skip)
#   NOTCHED_DEST     install folder (default: ~/Applications)
#   NOTCHED_NO_OPEN  set to 1 to install without opening the app
set -euo pipefail

repo="Notched17/Notched"
url="${NOTCHED_URL:-https://github.com/$repo/releases/latest/download/Notched.zip}"
sha_url="${NOTCHED_SHA_URL:-$url.sha256}"
dest_dir="${NOTCHED_DEST:-$HOME/Applications}"
app="$dest_dir/Notched.app"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Notched only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 26 )) || fail "Notched needs macOS 26 or later (this Mac has $(sw_vers -productVersion))."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "→ Downloading Notched…"
curl -fL --progress-bar -o "$work/Notched.zip" "$url" \
  || fail "could not download $url (is there a release yet?)"

if [[ "$sha_url" != "skip" ]]; then
  echo "→ Checking the download…"
  curl -fsSL -o "$work/Notched.zip.sha256" "$sha_url" \
    || fail "could not download the checksum from $sha_url"
  expected="$(awk '{print $1}' "$work/Notched.zip.sha256")"
  actual="$(shasum -a 256 "$work/Notched.zip" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] \
    || fail "the download does not match its checksum; not installing."
fi

echo "→ Unpacking…"
ditto -x -k "$work/Notched.zip" "$work/unpacked"
[[ -d "$work/unpacked/Notched.app" ]] || fail "the zip does not contain Notched.app."

# Quit a running copy so it can be replaced.
if pgrep -x Notched >/dev/null 2>&1; then
  echo "→ Quitting the running Notched…"
  osascript -e 'tell application "Notched" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Notched 2>/dev/null || true
fi

echo "→ Installing to $dest_dir…"
mkdir -p "$dest_dir"
rm -rf "$app"
ditto "$work/unpacked/Notched.app" "$app"
# Belt and braces: make sure nothing marks it as quarantined.
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

echo "Installed $app"
if [[ "${NOTCHED_NO_OPEN:-0}" != "1" ]]; then
  open "$app"
  echo "Notched is open. Look for its icon in the menu bar; macOS will ask for permissions when you turn features on."
fi

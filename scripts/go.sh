#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# The whole routine in one command: pull, regenerate the project, run the
# tests, and (if they pass) build, install to ~/Applications and relaunch.
#
# Usage: scripts/go.sh [--no-pull] [--no-install] [--release]
#   --no-pull     don't `git pull`
#   --no-install  stop after the tests
#   --release     install a Release build
# Compile errors and failing tests are printed at the end; the full log is
# build/test.log.
set -uo pipefail
cd "$(dirname "$0")/.."

pull=1; install=1; config=Debug
for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=0 ;;
    --no-install) install=0 ;;
    --release) config=Release ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

# Regenerate the Xcode project automatically after any later pull or checkout.
git config core.hooksPath .githooks

if (( pull )); then
  echo "→ git pull"
  git pull --ff-only || { echo "Pull failed (local changes or diverged branch). Fix that, or use --no-pull."; exit 1; }
fi

echo "→ tests (xcodegen generate, then xcodebuild test)"
scripts/test.sh
status=$?
if (( status != 0 )); then
  echo
  echo "✘ Build or tests failed. Paste the lines above to Claude. Not installing."
  exit "$status"
fi

if (( install )); then
  echo "→ install"
  scripts/install.sh "$config" || exit $?
fi
echo "✔ Done"

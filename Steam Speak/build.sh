#!/bin/sh
# Build Steam Speak, install it to /Applications, and relaunch it.
# Read ~/Library/Application\ Support/Steam\ Speak/logs/ afterwards — the app narrates its startup.
set -e
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"

# Where to build.
#
# This project lives under ~/Desktop, which iCloud Drive syncs. The file provider stamps
# extended attributes on directories it touches, and codesign refuses to sign a bundle
# carrying those ("resource fork, Finder information, or similar detritus not allowed").
# ~/Library is not synced, so build there. Override with STEAMSPEAK_DERIVED.
DERIVED="${STEAMSPEAK_DERIVED:-$HOME/Library/Developer/SteamSpeak}"

# xcode-select may be pointing at the Command Line Tools, which has no xcodebuild.
if ! xcodebuild -version >/dev/null 2>&1; then
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if [ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]; then
      DEVELOPER_DIR="$candidate/Contents/Developer"
      export DEVELOPER_DIR
      echo "Using $candidate"
      break
    fi
  done
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "No usable Xcode found. Install Xcode, or set DEVELOPER_DIR."
  exit 1
fi

mkdir -p "$DERIVED"
LOG="$DERIVED/last-build.log"

echo "Building Steam Speak ($CONFIG)…"
set +e
# The shared scheme was cloned from Muteny's; -derivedDataPath needs one.
xcodebuild -project "Steam Speak.xcodeproj" -scheme "Steam Speak" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" build > "$LOG" 2>&1
STATUS=$?
set -e

grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)|failed with a nonzero" "$LOG" || true

APP="$DERIVED/Build/Products/$CONFIG/Steam Speak.app"
if [ $STATUS -ne 0 ] || [ ! -d "$APP" ]; then
  echo "Build failed. Full log: $LOG"
  exit 1
fi

pkill -x "Steam Speak" 2>/dev/null || true
sleep 0.5
/usr/bin/ditto "$APP" "/Applications/Steam Speak.app"
open "/Applications/Steam Speak.app"
echo "Installed to /Applications/Steam Speak.app and launched."
echo "Build log: $LOG"
echo "Latest app log:"
ls -t "$HOME/Library/Application Support/Steam Speak/logs" 2>/dev/null | head -1

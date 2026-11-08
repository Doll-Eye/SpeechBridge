#!/bin/sh
# One line to fetch SpeechBridge and run its setup (setup.sh, for TurnOver and NotProton):
#   curl -fsSL https://raw.githubusercontent.com/Doll-Eye/SpeechBridge/main/get.sh | sh
set -e
DEST="$HOME/SpeechBridge"
echo "Fetching SpeechBridge into $DEST…"
mkdir -p "$DEST"; curl -fsSL https://github.com/Doll-Eye/SpeechBridge/archive/refs/heads/main.tar.gz | tar -xz -C "$DEST" --strip-components=1
cd "$DEST" && sh install.sh "$@"

#!/bin/sh
# SpeechBridge — the one-shot installer. Builds the two Mac apps, installs the stand-ins into
# the CrossOver bottle, and does the registrations inside it. Safe to run again any time.
#
#   sh install.sh [bottle-name]        default bottle: Steam
#
# Needs: an Apple-silicon Mac, CrossOver with a bottle holding Windows Steam, and Apple's
# Command Line Tools (this script offers to install them). No Xcode, no Homebrew.
set -e
cd "$(dirname "$0")"; HERE="$(pwd)"
BOTTLE="${1:-Steam}"
B="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/cxstart"
say() { printf '\n== %s\n' "$*"; }

say "Checking this Mac"
[ "$(uname -m)" = "arm64" ] || { echo "This needs an Apple-silicon Mac."; exit 1; }
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null; then
    echo "Apple's Command Line Tools are needed (they hold the Swift compiler). Requesting them now;"
    echo "accept the dialog, wait for it to finish, then run this installer again."
    xcode-select --install 2>/dev/null || true; exit 1
fi
[ -x "$CX" ] || { echo "CrossOver is not installed at /Applications/CrossOver.app. Install it first."; exit 1; }
[ -d "$B/drive_c" ] || { echo "No CrossOver bottle called '$BOTTLE'. Create one (Windows 10), install Steam into it, then run this again — or pass the bottle's name."; exit 1; }
[ -f "$B/drive_c/Program Files (x86)/Steam/steam.exe" ] || echo "Note: no Windows Steam in the '$BOTTLE' bottle yet; the speech pieces install anyway."

say "Listener (the Mac app that speaks)"
sh SpeechBridge/listener/build.sh
sh SpeechBridge/listener/login-item.sh install

say "Steam Speak (reads Big Picture)"
sh "Steam Speak/build-lite.sh"

say "Helper apps"
mkdir -p "$HOME/Library/Application Support/SpeechBridge/run-in-bottle"
osacompile -o "$HOME/Library/Application Support/SpeechBridge/run-in-bottle/RunInBottle.app" SpeechBridge/tools/run-in-bottle.applescript
osacompile -o "/Applications/Steam.app" SpeechBridge/tools/steam-launcher.applescript
sh SpeechBridge/setup-app/build.sh
echo "Built /Applications/Steam.app (starts the bottle's Steam) and /Applications/SpeechBridge Setup.app (run after installing a game)."

say "Stand-ins into the bottle"
sh SpeechBridge/install.sh "$BOTTLE"

say "Registrations inside the bottle (one-off, harmless to repeat)"
inb() {   # run one Windows command in the bottle, giving up after 90 s
    "$CX" --bottle "$BOTTLE" --no-update --wait "$@" >/dev/null 2>&1 &
    pid=$!; i=0; while kill -0 $pid 2>/dev/null && [ $i -lt 90 ]; do sleep 1; i=$((i+1)); done
    kill -0 $pid 2>/dev/null && { kill $pid 2>/dev/null; echo "  (timed out: $*)"; return 1; }; wait $pid 2>/dev/null || true
}
inb regsvr32 /s 'C:\windows\system32\SapiBridge64.dll'                              && echo "  SAPI voice, 64-bit"
inb 'C:\windows\syswow64\regsvr32.exe' /s 'C:\windows\syswow64\SapiBridge32.dll'    && echo "  SAPI voice, 32-bit"
inb regsvr32 /s 'C:\windows\system32\SpVoiceBridge64.dll'                           && echo "  SpVoice stand-in, 64-bit"
inb 'C:\windows\syswow64\regsvr32.exe' /s 'C:\windows\syswow64\SpVoiceBridge32.dll' && echo "  SpVoice stand-in, 32-bit"
inb reg add 'HKLM\SOFTWARE\WOW6432Node\zhiduo\zdsr' /v Path /t REG_SZ /d 'C:\SpeechBridge' /f && echo "  ZDSR key (for games built on Prism)"
inb reg add 'HKCU\Software\Wine\AppDefaults\steam.exe\DllOverrides' /v cfgmgr32 /t REG_SZ /d native,builtin /f && echo "  Bluetooth rumble shim for Steam"
inb reg import 'C:\SpeechBridge\renpy.reg'                                          && echo "  Ren'Py self-voicing"

say "Done"
cat <<'TXT'
Next:
  1. Open "SpeechBridge Listener" once from Applications; when macOS asks whether it may
     control VoiceOver, allow it. That is the only permission.
  2. Open "Steam Speak" from Applications and choose "Restart Steam so it can be read".
  3. Start Steam with the "Steam" app in Applications. Install a game, then open
     "SpeechBridge Setup" once. Any game that speaks through SAPI, Tolk, NVDA's controller
     client, Prism, the UAP plugin or Ren'Py should now talk through VoiceOver.
Game-specific notes (Diablo IV, Fallout 4, Hades II, Cyberpunk 2077…) are in README.md.
TXT

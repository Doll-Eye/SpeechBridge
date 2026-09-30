#!/bin/sh
# Builds Steam Speak with the plain Swift compiler — no Xcode, only the Command Line Tools —
# and installs it to /Applications. The Xcode project (build.sh) remains for development.
# Set STEAMSPEAK_APP to install somewhere else (used for tests).
set -e; cd "$(dirname "$0")"
APP="${STEAMSPEAK_APP:-/Applications/Steam Speak.app}"
BUILD="${STEAMSPEAK_DERIVED:-$HOME/Library/Developer/SteamSpeak/lite}"
rm -rf "$BUILD"; mkdir -p "$BUILD/Steam Speak.app/Contents/MacOS" "$BUILD/Steam Speak.app/Contents/Resources"
echo "Compiling Steam Speak…"
swiftc -O -target arm64-apple-macos14.0 -parse-as-library -o "$BUILD/Steam Speak.app/Contents/MacOS/Steam Speak" SteamSpeak/*.swift
cat > "$BUILD/Steam Speak.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Steam Speak</string>
    <key>CFBundleDisplayName</key><string>Steam Speak</string>
    <key>CFBundleIdentifier</key><string>com.doll-eye.SteamSpeak</string>
    <key>CFBundleExecutable</key><string>Steam Speak</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key><string>Steam Speak speaks through VoiceOver when VoiceOver is on, so you hear one voice.</string>
</dict></plist>
PLIST
codesign --force --sign - "$BUILD/Steam Speak.app" >/dev/null 2>&1 || true
rm -rf "$APP"; /usr/bin/ditto "$BUILD/Steam Speak.app" "$APP"
echo "Installed $APP"
if [ "$APP" = "/Applications/Steam Speak.app" ]; then pkill -x "Steam Speak" 2>/dev/null || true; sleep 0.5; open "$APP"; fi

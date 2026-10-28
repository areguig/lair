#!/bin/sh
# Builds the menu-bar app and installs it in ~/Applications. The app's name lives here only.
set -eu
name="Lair"
bundle_id="dev.lair.app"
repo=$(cd "$(dirname "$0")/.." && pwd)
app="$HOME/Applications/$name.app"

swift build -c release --package-path "$repo" --product Lair
bin=$(swift build -c release --package-path "$repo" --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Lair" "$app/Contents/MacOS/$name"
# SwiftPM resource bundles are looked up in Contents/Resources.
cp -R "$bin"/*.bundle "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>$name listens while you hold the talk key, to hear what you say to your agents.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
echo "Installed $app"

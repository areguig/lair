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
# The app draws its own icon: render it, then scale it into an iconset.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$bin/Lair" --icon "$work/icon.png"
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2)); [ $double -le 512 ] && sips -z $double $double "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$work/icon.png" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>$name listens while you hold the talk key, to hear what you say to your agents.</string>
</dict></plist>
PLIST
# A stable identity keeps macOS permissions (microphone) across rebuilds; LAIR_SIGN_IDENTITY overrides the pick.
identity=${LAIR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')}
codesign --force --deep --sign "${identity:--}" "$app"
echo "Installed $app"

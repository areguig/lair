#!/bin/sh
# Builds the menu-bar app into the given folder, ~/Applications by default. The app's name lives here only.
set -eu
name="Lair"
bundle_id="dev.lair.app"
repo=$(cd "$(dirname "$0")/.." && pwd)
app="${1:-$HOME/Applications}/$name.app"

swift build -c release --package-path "$repo" --product Lair
bin=$(swift build -c release --package-path "$repo" --show-bin-path)
# SwiftPM in Swift 6.3 and older looks for resource bundles beside the .app or in this build folder, never in
# Contents/Resources, so the app would crash on any other Mac.
if strings "$bin/Lair" | grep -q "$bin/.*\.bundle"; then
  echo "error: this Swift finds resources only in $bin; bundle the app with Swift 6.4 (Xcode 27) or later" >&2
  exit 1
fi

# Kyutai's Pocket TTS speaks for the agents. Pinned to a release and its SHA-256 (from the release's SHA256SUMS);
# the download is kept in .build so rebuilds don't fetch it again.
pocket_release="v4.0.1"
pocket_archive="pocket-tts-3.3.0-aarch64-apple-darwin.tar.gz"
pocket_sha256="ee9ca6c7c000ee72c5846e3a8ba01d08f56636d94a614d2259c3f12b8fd69afa"
pocket_download="$repo/.build/pocket-tts-download"
pocket_matches() { [ -f "$pocket_download/$pocket_archive" ] && [ "$(shasum -a 256 "$pocket_download/$pocket_archive" | cut -d' ' -f1)" = "$pocket_sha256" ]; }
if ! pocket_matches; then
  mkdir -p "$pocket_download"
  curl -fsSL -o "$pocket_download/$pocket_archive" \
    "https://github.com/kyutai-labs/pocket-tts/releases/download/$pocket_release/$pocket_archive"
  pocket_matches || { rm -f "$pocket_download/$pocket_archive"; echo "error: $pocket_archive does not match its pinned SHA-256" >&2; exit 1; }
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$bin/Lair" "$app/Contents/MacOS/$name"
tar -xzf "$pocket_download/$pocket_archive" -C "$app/Contents/Helpers" --strip-components=1 --include='*/pocket-tts'
# Sparkle's XPC services are only for sandboxed apps.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$bin/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
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
  <key>CFBundleShortVersionString</key><string>${LAIR_VERSION:-0.1}</string>
  <key>CFBundleVersion</key><string>$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>https://github.com/areguig/lair/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>dxNFdjuJmZE7FSoBXtKgfw6xZoTFfoCEeleM5WLloVk=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>$name listens while you hold the talk key or after you click the orb, to hear what you say to your agents.</string>
</dict></plist>
PLIST
# A stable identity keeps macOS permissions (microphone) across rebuilds: Developer ID (to share) before Apple Development
# (this Mac only), else ad hoc. LAIR_SIGN_IDENTITY overrides the pick; "-" signs ad hoc.
identities=$(security find-identity -v -p codesigning)
identity=${LAIR_SIGN_IDENTITY:-$(printf '%s\n' "$identities" | awk '/Developer ID Application/ { print $2; exit }')}
identity=${identity:-$(printf '%s\n' "$identities" | awk '/Apple Development/ { print $2; exit }')}
identity=${identity:--}
# The hardened runtime and a secure timestamp are what notarization asks for; ad hoc signatures can't be timestamped.
timestamp=--timestamp
[ "$identity" = - ] && timestamp=--timestamp=none
# Inside out, without --deep, as Sparkle's docs ask; the voice engine is signed like the app.
for part in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
  codesign --force --options runtime "$timestamp" --sign "$identity" "$part"
done
codesign --force --options runtime "$timestamp" --sign "$identity" "$app/Contents/Helpers/pocket-tts"
codesign --force --options runtime "$timestamp" --entitlements "$repo/scripts/Lair.entitlements" --sign "$identity" "$app"
echo "Built $app"

#!/bin/sh
# Builds the app and wraps it in a disk image with an Applications link, for dragging in.
# With notary credentials, the image is signed, notarized and stapled, so it opens without a warning:
#   LAIR_NOTARY_PROFILE  a profile saved by `xcrun notarytool store-credentials` (on your Mac), or
#   LAIR_NOTARY_KEY, LAIR_NOTARY_KEY_ID, LAIR_NOTARY_ISSUER  an App Store Connect API key (.p8 path), as in CI.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
dmg="${1:-$repo/.build/Lair.dmg}"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
"$repo/scripts/build-app.sh" "$stage"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname Lair -srcfolder "$stage" -format UDZO -fs HFS+ "$dmg"
if [ -n "${LAIR_NOTARY_PROFILE:-}" ]; then
  set -- --keychain-profile "$LAIR_NOTARY_PROFILE"
elif [ -n "${LAIR_NOTARY_KEY:-}" ]; then
  set -- --key "$LAIR_NOTARY_KEY" --key-id "$LAIR_NOTARY_KEY_ID" --issuer "$LAIR_NOTARY_ISSUER"
else
  echo "Made $dmg (not notarized: no notary credentials)"
  exit 0
fi
identity=$(codesign -dvv "$stage/Lair.app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p' | head -1)
[ -n "$identity" ] || { echo "error: notarizing needs the app signed with a Developer ID Application certificate" >&2; exit 1; }
codesign --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --wait "$@"
xcrun stapler staple "$dmg"
echo "Made $dmg, notarized"

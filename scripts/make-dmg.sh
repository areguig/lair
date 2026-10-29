#!/bin/sh
# Builds the app and wraps it in a disk image with an Applications link, for dragging in. Unsigned for now.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
dmg="${1:-$repo/.build/Lair.dmg}"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
"$repo/scripts/build-app.sh" "$stage"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname Lair -srcfolder "$stage" -format UDZO -fs HFS+ "$dmg"
echo "Made $dmg"

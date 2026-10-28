#!/bin/sh
# Renders the demo video from a scripted call (demo agents, real on-device voices) into docs/demo.mp4.
# Needs ffmpeg to join picture and sound.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift build -c release --package-path "$repo" --product Lair
"$(swift build -c release --package-path "$repo" --show-bin-path)/Lair" --demo "$work"
mkdir -p "$repo/docs"
ffmpeg -loglevel error -y -i "$work/demo.mov" -i "$work/demo.wav" \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -ar 48000 -movflags +faststart -shortest \
  "$repo/docs/demo.mp4"
echo "Wrote $repo/docs/demo.mp4"

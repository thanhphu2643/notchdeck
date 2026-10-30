#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift scripts/make-icon.swift "$WORK/icon.png"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$WORK/icon.png" docs/icon.png
echo "Wrote Resources/AppIcon.icns"

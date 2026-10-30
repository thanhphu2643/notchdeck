#!/usr/bin/env bash
# Packages dist/NotchDeck.app into dist/NotchDeck-<version>.dmg with an
# Applications shortcut for drag-to-install.
# Usage: VERSION=0.1.0 scripts/dmg.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
export VERSION
scripts/bundle.sh "$@"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/NotchDeck.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/NotchDeck-${VERSION}.dmg"
RW="$STAGE.rw.dmg"
rm -f "$DMG"
hdiutil create -volname "NotchDeck" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null

# Give the mounted volume the app icon (needs a writable image, then compress).
MOUNT=$(hdiutil attach "$RW" -nobrowse -noautoopen | awk -F'\t' '/\/Volumes\// {print $NF}')
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null
rm -f "$RW"
echo "Built $DMG"

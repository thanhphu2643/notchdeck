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
rm -f "$DMG"
hdiutil create -volname "NotchDeck" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"

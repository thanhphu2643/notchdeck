#!/usr/bin/env bash
# Builds the Rust core + Swift app and assembles dist/NotchDeck.app.
# Usage: scripts/bundle.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP=dist/NotchDeck.app
export MACOSX_DEPLOYMENT_TARGET=14.0

if [[ "${1:-}" == "--universal" ]]; then
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
  for t in aarch64-apple-darwin x86_64-apple-darwin; do
    ${CARGO:-cargo} build --release --manifest-path core/Cargo.toml --target "$t"
  done
  mkdir -p core/target/release
  lipo -create -output core/target/release/libnotchdeck_core.a \
    core/target/{aarch64,x86_64}-apple-darwin/release/libnotchdeck_core.a
  swift build -c release --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/NotchDeck
else
  ${CARGO:-cargo} build --release --manifest-path core/Cargo.toml
  swift build -c release
  BIN=.build/release/NotchDeck
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotchDeck"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchDeck</string>
  <key>CFBundleIdentifier</key><string>io.github.thanhphu2643.notchdeck</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Nguyễn Thanh Phú. MIT License.</string>
  <key>CFBundleExecutable</key><string>NotchDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

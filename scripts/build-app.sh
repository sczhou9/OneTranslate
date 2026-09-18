#!/bin/sh
set -eu

VERSION="${ONETRANSLATE_VERSION:-0.0.1}"
ARM_SCRATCH=".build-arm64"
INTEL_SCRATCH=".build-x86_64"

swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_SCRATCH"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_SCRATCH"

APP_DIR="$(pwd)/build/OneTranslate.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
ARM_BIN="$(swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)/OneTranslate"
INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_SCRATCH" --show-bin-path)/OneTranslate"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP_DIR/Contents/MacOS/OneTranslate"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign "${ONETRANSLATE_SIGNING_IDENTITY:--}" "$APP_DIR" >/dev/null

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$(pwd)/dist/OneTranslate-macOS-universal.zip"

DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/OneTranslate-dmg.XXXXXX")"
cleanup() {
	rm -rf "$DMG_STAGING"
}
trap cleanup EXIT INT TERM

ditto "$APP_DIR" "$DMG_STAGING/OneTranslate.app"
hdiutil create \
	-volname "OneTranslate ${VERSION}" \
	-srcfolder "$DMG_STAGING" \
	-ov \
	-format UDZO \
	"$(pwd)/dist/OneTranslate-macOS-universal-${VERSION}.dmg" >/dev/null

echo "Built $APP_DIR"
echo "Packaged $(pwd)/dist/OneTranslate-macOS-universal.zip"
echo "Packaged $(pwd)/dist/OneTranslate-macOS-universal-${VERSION}.dmg"

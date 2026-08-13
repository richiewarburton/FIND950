#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR=${1:-dist}
INFO_PLIST="$PROJECT_DIR/Resources/FIND950-Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
PACKAGE_NAME="FIND950-$VERSION-macOS-universal"
STAGE_DIR=$(mktemp -d /tmp/find950-release.XXXXXX)
PACKAGE_DIR="$STAGE_DIR/$PACKAGE_NAME"
APP_DIR="$PACKAGE_DIR/FIND950.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cleanup() {
    rm -rf "$STAGE_DIR"
}
trap cleanup EXIT HUP INT TERM

cd "$PROJECT_DIR"
xcrun swift test
xcrun swift build -c release --product FIND950 \
    --triple arm64-apple-macosx14.0 \
    --scratch-path .build/release-arm64
xcrun swift build -c release --product FIND950 \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path .build/release-x86_64

ARM64_BIN_DIR=$(xcrun swift build -c release --product FIND950 \
    --triple arm64-apple-macosx14.0 \
    --scratch-path .build/release-arm64 --show-bin-path)
X86_64_BIN_DIR=$(xcrun swift build -c release --product FIND950 \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path .build/release-x86_64 --show-bin-path)

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/BrandAssets" \
    "$RESOURCES_DIR/Fonts" "$RESOURCES_DIR/Licenses"
/usr/bin/lipo -create \
    "$ARM64_BIN_DIR/FIND950" \
    "$X86_64_BIN_DIR/FIND950" \
    -output "$MACOS_DIR/FIND950"
chmod 755 "$MACOS_DIR/FIND950"

cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp Resources/BrandAssets/FIND950.icns "$RESOURCES_DIR/FIND950.icns"
cp Resources/BrandAssets/FIND950-brand-mark.png "$RESOURCES_DIR/BrandAssets/"
cp Resources/BrandAssets/launcher-EDIT950.png "$RESOURCES_DIR/BrandAssets/"
cp Resources/BrandAssets/launcher-PLAY950.png "$RESOURCES_DIR/BrandAssets/"
cp Resources/Fonts/JetBrainsMono-Regular.ttf "$RESOURCES_DIR/Fonts/"
cp Resources/Fonts/JetBrainsMono-Medium.ttf "$RESOURCES_DIR/Fonts/"
cp Resources/Fonts/JetBrainsMono-Bold.ttf "$RESOURCES_DIR/Fonts/"
cp Resources/Fonts/fonts.sha256 "$RESOURCES_DIR/Fonts/"
cp Resources/Licenses/JetBrainsMono-OFL-1.1.txt "$RESOURCES_DIR/Licenses/"

codesign --force --deep --sign - "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$CONTENTS_DIR/Info.plist")" = "FIND950"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$CONTENTS_DIR/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$CONTENTS_DIR/Info.plist")" = "14.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :ATSApplicationFontsPath' \
    "$CONTENTS_DIR/Info.plist")" = "Fonts/"
(cd "$RESOURCES_DIR/Fonts" && shasum -a 256 -c fonts.sha256)
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

APP_ARCHS=$(/usr/bin/lipo -archs "$MACOS_DIR/FIND950")
case " $APP_ARCHS " in
    *" arm64 "*) ;;
    *) echo "FIND950 is missing arm64" >&2; exit 1 ;;
esac
case " $APP_ARCHS " in
    *" x86_64 "*) ;;
    *) echo "FIND950 is missing x86_64" >&2; exit 1 ;;
esac
if strings "$MACOS_DIR/FIND950" | grep -Fq '/Users/'; then
    echo "release binary contains a developer-machine user path" >&2
    exit 1
fi

cp README.md "$PACKAGE_DIR/README.md"
cp LICENSE "$PACKAGE_DIR/LICENSE"
(
    cd "$PACKAGE_DIR"
    shasum -a 256 \
        FIND950.app/Contents/MacOS/FIND950 \
        FIND950.app/Contents/Info.plist \
        README.md LICENSE > SHA256SUMS.txt
)

mkdir -p "$OUTPUT_DIR"
ZIP_PATH="$OUTPUT_DIR/$PACKAGE_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
unzip -t "$ZIP_PATH" >/dev/null
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$PACKAGE_NAME.zip" > "$PACKAGE_NAME.zip.sha256"
)

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"

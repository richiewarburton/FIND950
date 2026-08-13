#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application_dir="/Applications/FIND950.app"
contents_dir="$application_dir/Contents"

cd "$project_dir"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --product "FIND950"
binary_path=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --show-bin-path)

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/BrandAssets" "$contents_dir/Resources/Fonts" "$contents_dir/Resources/Licenses"
cp "$binary_path/FIND950" "$contents_dir/MacOS/FIND950"
chmod 755 "$contents_dir/MacOS/FIND950"

cp "Resources/FIND950-Info.plist" "$contents_dir/Info.plist"
cp "Resources/BrandAssets/FIND950.icns" "$contents_dir/Resources/FIND950.icns"
cp Resources/BrandAssets/FIND950-brand-mark.png "$contents_dir/Resources/BrandAssets/"
cp Resources/BrandAssets/launcher-EDIT950.png "$contents_dir/Resources/BrandAssets/"
cp Resources/BrandAssets/launcher-PLAY950.png "$contents_dir/Resources/BrandAssets/"
cp Resources/Fonts/JetBrainsMono-Regular.ttf "$contents_dir/Resources/Fonts/"
cp Resources/Fonts/JetBrainsMono-Medium.ttf "$contents_dir/Resources/Fonts/"
cp Resources/Fonts/JetBrainsMono-Bold.ttf "$contents_dir/Resources/Fonts/"
cp Resources/Fonts/fonts.sha256 "$contents_dir/Resources/Fonts/"
cp Resources/Licenses/JetBrainsMono-OFL-1.1.txt "$contents_dir/Resources/Licenses/"
codesign --force --sign - "$application_dir"
touch "$application_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$application_dir"
open -R "$application_dir"

test "$(/usr/libexec/PlistBuddy -c 'Print :ATSApplicationFontsPath' "$contents_dir/Info.plist")" = "Fonts/"
(cd "$contents_dir/Resources/Fonts" && shasum -a 256 -c fonts.sha256)

echo "Installed $application_dir"

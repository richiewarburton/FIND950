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
rm -f "$contents_dir/Resources/akaiutil-arm64" \
    "$contents_dir/Resources/akaiutil-x86_64"
"$project_dir/Scripts/build-akaiutil-universal.sh" \
    "$contents_dir/Resources/akaiutil"

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
cp ThirdParty/akaiutil-4.6.7/README.txt \
    "$contents_dir/Resources/Licenses/AKAI-Util-NOTICE.txt"
cp ThirdParty/akaiutil-4.6.7/gpl-2.0.txt \
    "$contents_dir/Resources/Licenses/AKAI-Util-GPL-2.0.txt"
cp ThirdParty/akaiutil-4.6.7/PROVENANCE.md \
    "$contents_dir/Resources/Licenses/AKAI-Util-SOURCE.txt"

helper_archs=$(/usr/bin/lipo -archs "$contents_dir/Resources/akaiutil")
case " $helper_archs " in *" arm64 "*) ;; *) echo "Bundled AKAI Util is missing arm64" >&2; exit 1 ;; esac
case " $helper_archs " in *" x86_64 "*) ;; *) echo "Bundled AKAI Util is missing x86_64" >&2; exit 1 ;; esac
"$contents_dir/Resources/akaiutil" -h >/dev/null 2>&1

codesign --force --sign - "$contents_dir/Resources/akaiutil"
codesign --force --sign - "$application_dir"
touch "$application_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$application_dir"
open -R "$application_dir"

test "$(/usr/libexec/PlistBuddy -c 'Print :ATSApplicationFontsPath' "$contents_dir/Info.plist")" = "Fonts/"
(cd "$contents_dir/Resources/Fonts" && shasum -a 256 -c fonts.sha256)
codesign --verify --deep --strict --verbose=2 "$application_dir"

echo "Installed $application_dir"

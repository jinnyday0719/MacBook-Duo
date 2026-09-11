#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

app_path="Build/MacBook Duo.app"
dmg_path="Build/MacBook Duo.dmg"
staging_path="Build/MacBook Duo-dmg-staging"
identity="${MACBOOKDUO_SIGNING_IDENTITY:-}"
notary_profile="${MACBOOKDUO_NOTARY_PROFILE:-}"

if [[ -z "$identity" ]]; then
    echo "Set MACBOOKDUO_SIGNING_IDENTITY to a Developer ID Application identity." >&2
    exit 1
fi

swift build -c release --product MacBookDuo

rm -rf "$app_path" "$staging_path" "$dmg_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp .build/release/MacBookDuo "$app_path/Contents/MacOS/MacBookDuo"
cp Resources/MacBookDuo-Info.plist "$app_path/Contents/Info.plist"

iconset_parent="$(mktemp -d)"
iconset_path="$iconset_parent/AppIcon.iconset"
mkdir -p "$iconset_path"
trap 'rm -rf "$iconset_parent"' EXIT
source_icon="Resources/AppIconSource.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_icon" --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256 512; do
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$source_icon" --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/AppIcon.icns"

plutil -lint "$app_path/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$identity" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$staging_path"
cp -R "$app_path" "$staging_path/MacBook Duo.app"
ln -s /Applications "$staging_path/Applications"
hdiutil create -volname "MacBook Duo" -srcfolder "$staging_path" -ov -format UDZO "$dmg_path" >/dev/null
codesign --force --timestamp --sign "$identity" "$dmg_path"
codesign --verify --strict "$dmg_path"

if [[ -z "$notary_profile" ]]; then
    echo "Signed DMG created: $dmg_path"
    echo "Set MACBOOKDUO_NOTARY_PROFILE to submit it for notarization."
    exit 2
fi

xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
echo "Notarized DMG created: $dmg_path"

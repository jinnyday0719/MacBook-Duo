#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product MacBookDuo
mkdir -p "Build/MacBook Duo.app/Contents/MacOS"
cp .build/release/MacBookDuo "Build/MacBook Duo.app/Contents/MacOS/MacBookDuo"
cp Resources/MacBookDuo-Info.plist "Build/MacBook Duo.app/Contents/Info.plist"
codesign --force --sign - "Build/MacBook Duo.app"
plutil -lint "Build/MacBook Duo.app/Contents/Info.plist"
codesign --verify --strict "Build/MacBook Duo.app"

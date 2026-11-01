#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./scripts/swift.sh build -c release
APP="$PWD/dist/Trackpad Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TrackpadStudio "$APP/Contents/MacOS/TrackpadStudio.new"
mv -f "$APP/Contents/MacOS/TrackpadStudio.new" "$APP/Contents/MacOS/TrackpadStudio"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
echo "$APP"

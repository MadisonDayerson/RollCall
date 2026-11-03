#!/bin/zsh
# Builds RollCall.app.
#   ./build.sh            build only
#   ./build.sh --install  build, install in ~/Applications and open it
#   ./build.sh --share    build for Apple silicon and Intel Macs and make build/RollCall.dmg to send to people
set -euo pipefail
cd "$(dirname "$0")"
APP=build/RollCall.app
rm -rf "$APP" build/MotoRides.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${1:-}" == "--share" ]]; then
  swiftc -O -target arm64-apple-macos14 Sources/*.swift -o build/RollCall-arm64
  swiftc -O -target x86_64-apple-macos14 Sources/*.swift -o build/RollCall-x86_64
  lipo -create build/RollCall-arm64 build/RollCall-x86_64 -output "$APP/Contents/MacOS/RollCall"
  rm build/RollCall-arm64 build/RollCall-x86_64
else
  swiftc -O -target arm64-apple-macos14 Sources/*.swift -o "$APP/Contents/MacOS/RollCall"
fi
cp Info.plist "$APP/Contents/Info.plist"

# App icon from the logo (Design/make_icon.swift draws Design/RollCall.png).
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Design/RollCall.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Design/RollCall.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Design/MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"
# The "Roll Call" wordmark at the foot of the sidebar (Design/make_wordmark.swift draws it).
cp Design/Wordmark.png "$APP/Contents/Resources/Wordmark.png"

codesign --force --sign - "$APP"

case "${1:-}" in
  --install)
    mkdir -p ~/Applications
    pkill -x RollCall 2>/dev/null || true
    pkill -x MotoRides 2>/dev/null || true
    rm -rf ~/Applications/RollCall.app ~/Applications/MotoRides.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/RollCall.app
    echo "Installed and opened ~/Applications/RollCall.app"
    ;;
  --share)
    STAGE=build/dmg
    rm -rf "$STAGE" build/RollCall.dmg
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp "Share/How to open RollCall.txt" "$STAGE/"
    hdiutil create -volname RollCall -srcfolder "$STAGE" -format UDZO -quiet build/RollCall.dmg
    rm -rf "$STAGE"
    echo "Made build/RollCall.dmg"
    ;;
  *)
    echo "Built $APP (run ./build.sh --install to install and open it)"
    ;;
esac

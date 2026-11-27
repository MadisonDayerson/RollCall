#!/bin/zsh
# Builds and runs the tests: the shared code (Sources/Shared) and a little of each app's, then checks the iPhone app
# still builds with the shared code (when Xcode is installed).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc Sources/Shared/*.swift Sources/Mac/Updater.swift Sources/Mac/Poster.swift iOS/RollCall/Fire.swift iOS/RollCall/FireShaders.swift \
  Tests/main.swift -o build/tests
build/tests

# The iPhone and iPad app uses the same shared code, so a change for the Mac mustn't break it.
if [[ -d /Applications/Xcode.app ]]; then
  if ! xcodebuild -quiet -project iOS/RollCall.xcodeproj -scheme RollCall -destination "generic/platform=iOS Simulator" \
      -derivedDataPath build/ios build > build/ios.log 2>&1; then
    grep -E "error:" build/ios.log | head -20
    echo "The iPhone app doesn't build"
    exit 1
  fi
  echo "iPhone app builds"
fi

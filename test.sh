#!/bin/zsh
# Builds and runs the tests: every source file except the app's windows, menus and startup.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc Sources/ICS.swift Sources/Model.swift Sources/Sources.swift Sources/Web.swift Sources/TextDetect.swift Sources/Refresh.swift \
  Sources/Beeper.swift Sources/RidePlan.swift Sources/Plans.swift Sources/AppleModel.swift Sources/RideDetails.swift \
  Sources/CrossPost.swift Sources/Crew.swift Sources/Route.swift Sources/RouteWeather.swift Sources/Brief.swift Sources/Updater.swift \
  Tests/main.swift -o build/tests
build/tests

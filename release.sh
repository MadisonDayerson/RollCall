#!/bin/zsh
# Publishes a new version of RollCall on GitHub, where everyone's RollCall finds it within a day.
#   ./release.sh 1.1 "Ride tags now include the date"
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:?Usage: ./release.sh <version, e.g. 1.1> "what's new"}
NOTES=${2:-}
REPO=MadisonDayerson/rollcall

# Tests first, so a broken build never reaches anyone.
swiftc Sources/ICS.swift Sources/Model.swift Sources/Sources.swift Sources/Web.swift Sources/Refresh.swift \
  Sources/Beeper.swift Sources/RidePlan.swift Sources/Plans.swift Sources/Crew.swift Sources/Updater.swift \
  Tests/main.swift -o build/tests
./build/tests | tail -1 | grep -q "All tests passed" || { echo "Tests failed; not releasing."; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Info.plist
./build.sh --share

git add -A
git commit -q -m "RollCall $VERSION" || true
git tag -a "v$VERSION" -m "RollCall $VERSION"
git push -q origin HEAD --follow-tags

# RollCall's own GitHub token, saved by git on the first push (stored per repository: credential.useHttpPath).
TOKEN=$(printf 'protocol=https\nhost=github.com\npath=MadisonDayerson/rollcall.git\n\n' | git credential fill | sed -n 's/^password=//p')
BODY=$(python3 -I -c 'import json,sys; print(json.dumps({"tag_name": "v"+sys.argv[1], "name": "RollCall "+sys.argv[1], "body": sys.argv[2]}))' "$VERSION" "$NOTES")
RELEASE=$(curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases" -d "$BODY")
ID=$(print -r -- "$RELEASE" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
curl -fsS -o /dev/null -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/x-apple-diskimage" \
  --data-binary @build/RollCall.dmg "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=RollCall.dmg"
echo "Released RollCall $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"

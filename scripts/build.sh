#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
    ""|--install) ;;
    *) printf 'Usage: %s [--install]\n' "$0" >&2; exit 64 ;;
esac

swift build -c release
mkdir -p dist .build/room-icon
task_stage=$(mktemp -d "$PWD/dist/.room-build.XXXXXXXX")
trap 'rm -rf "$task_stage"' EXIT
task_app="$task_stage/Room.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp .build/release/Room .build/release/room-scan "$task_app/Contents/MacOS/"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
if [[ ! -f .build/room-icon/Room.icns || scripts/icon.swift -nt .build/room-icon/Room.icns ]]; then
    swift scripts/icon.swift "$PWD/.build/room-icon"
fi
cp .build/room-icon/Room.icns "$task_app/Contents/Resources/"
strip -x "$task_app/Contents/MacOS/Room" "$task_app/Contents/MacOS/room-scan"
task_identity=$(scripts/signing-identity.sh --resolve)
task_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)
codesign --force --timestamp=none --sign "$task_identity" --identifier "$task_identifier.scanner" "$task_app/Contents/MacOS/room-scan"
codesign --force --timestamp=none --sign "$task_identity" --identifier "$task_identifier" "$task_app"
codesign --verify --deep --strict "$task_app"
rm -rf dist/Room.app
mv "$task_app" dist/Room.app
if [[ "$task_identity" == "-" ]]; then
    printf 'Built dist/Room.app (ad-hoc signing). Run make signing-identity for a stable local identity.\n'
else
    printf 'Built dist/Room.app with stable local signing.\n'
fi
if [[ "${1:-}" == "--install" ]]; then
    scripts/install.sh
fi

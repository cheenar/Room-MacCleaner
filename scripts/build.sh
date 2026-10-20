#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
mkdir -p dist/Room.app/Contents/MacOS dist/Room.app/Contents/Resources
cp .build/release/Room dist/Room.app/Contents/MacOS/Room
cp Resources/Info.plist dist/Room.app/Contents/Info.plist
swift scripts/icon.swift dist/Room.app/Contents/Resources
codesign --force --sign - dist/Room.app
codesign --verify --deep --strict dist/Room.app
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    ditto dist/Room.app "$HOME/Applications/Room.app"
    print "Installed: $HOME/Applications/Room.app"
fi

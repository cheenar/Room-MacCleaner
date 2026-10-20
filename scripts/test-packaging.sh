#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/room-packaging-tests.XXXXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
export INSTALL_DIR="$task_tmp/Applications with spaces"
export PREFIX="$task_tmp/Local tools"
export ROOM_SKIP_LSREGISTER=1

[[ "$(SIGN_ID=- scripts/signing-identity.sh --resolve)" == - ]]
if SIGN_ID='Room missing test identity 88752' scripts/signing-identity.sh --resolve 2>/dev/null; then
    printf 'Missing signing identity was accepted.\n' >&2; exit 1
fi
scripts/install.sh
[[ "$(readlink "$PREFIX/bin/room-scan")" == "$INSTALL_DIR/Room.app/Contents/MacOS/room-scan" ]]
"$PREFIX/bin/room-scan" --help | grep -q 'read-only'
"$PREFIX/bin/room-scan" --version | grep -q 'Room'
if "$PREFIX/bin/room-scan" --not-a-room-option >/dev/null 2>&1; then
    printf 'Unknown CLI option was accepted.\n' >&2; exit 1
fi
codesign --verify --deep --strict "$INSTALL_DIR/Room.app"
task_requirement=$(codesign -d -r- "$INSTALL_DIR/Room.app" 2>&1 | grep '^designated =>')
if [[ "$(scripts/signing-identity.sh --resolve)" != - ]]; then
    [[ "$task_requirement" == *'identifier "local.peter.room"'* && "$task_requirement" != *cdhash* ]]
fi
scripts/install.sh
[[ "$task_requirement" == "$(codesign -d -r- "$INSTALL_DIR/Room.app" 2>&1 | grep '^designated =>')" ]]
printf 'keep\n' > "$PREFIX/bin/unrelated"
scripts/install.sh --uninstall
[[ ! -e "$INSTALL_DIR/Room.app" && ! -L "$PREFIX/bin/room-scan" && -f "$PREFIX/bin/unrelated" ]]

printf 'unrelated executable\n' > "$PREFIX/bin/room-scan"
if scripts/install.sh >/dev/null 2>&1; then printf 'Unrelated CLI was replaced.\n' >&2; exit 1; fi
grep -q 'unrelated executable' "$PREFIX/bin/room-scan"
[[ ! -e "$INSTALL_DIR/Room.app" ]]
rm "$PREFIX/bin/room-scan"
mkdir -p "$INSTALL_DIR/Room.app/Contents"
cat > "$INSTALL_DIR/Room.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>example.unrelated</string></dict></plist>
PLIST
if scripts/install.sh >/dev/null 2>&1; then printf 'Unrelated app was replaced.\n' >&2; exit 1; fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_DIR/Room.app/Contents/Info.plist")" == example.unrelated ]]
printf 'Packaging checks passed: signing selection, CLI, stable requirement, reinstall, uninstall, spaces and conflict protection.\n'

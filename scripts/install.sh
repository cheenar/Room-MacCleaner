#!/bin/bash
# User-local app and CLI installation, following iridium-wm's make install flow.
set -euo pipefail
cd "$(dirname "$0")/.."

task_install_dir="${INSTALL_DIR:-$HOME/Applications}"
task_prefix="${PREFIX:-$HOME/.local}"
case "$task_install_dir" in /*) ;; *) task_install_dir="$PWD/$task_install_dir" ;; esac
case "$task_prefix" in /*) ;; *) task_prefix="$PWD/$task_prefix" ;; esac
task_destination="$task_install_dir/Room.app"
task_link="$task_prefix/bin/room-scan"
task_cli="$task_destination/Contents/MacOS/room-scan"
task_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)

check_destination() {
    if [[ -L "$task_destination" ]]; then
        printf 'Refusing to replace a symlink at %s\n' "$task_destination" >&2; return 1
    fi
    if [[ -e "$task_destination" ]]; then
        local installed_id
        installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_destination/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$installed_id" != "$task_identifier" ]]; then
            printf 'Refusing to replace an unrelated app at %s\n' "$task_destination" >&2; return 1
        fi
    fi
}
check_link() {
    if [[ -e "$task_link" || -L "$task_link" ]]; then
        if [[ ! -L "$task_link" || "$(readlink "$task_link")" != "$task_cli" ]]; then
            printf 'Refusing to replace an unrelated command at %s\n' "$task_link" >&2; return 1
        fi
    fi
}

check_destination
check_link
case "${1:-}" in
    --uninstall)
        if [[ -L "$task_link" ]]; then rm "$task_link"; fi
        if [[ -d "$task_destination" ]]; then rm -rf "$task_destination"; fi
        printf 'Removed Room.app and its CLI. Scan history and signing identities were kept.\n'
        exit ;;
    "") ;;
    *) printf 'Usage: %s [--uninstall]\n' "$0" >&2; exit 64 ;;
esac

codesign --verify --deep --strict dist/Room.app
mkdir -p "$task_install_dir" "$task_prefix/bin"
task_stage=$(mktemp -d "$task_install_dir/.room-install.XXXXXXXX")
task_complete=0
task_installed=0
task_link_created=0
cleanup() {
    if [[ "$task_complete" == 0 ]]; then
        if [[ "$task_link_created" == 1 && -L "$task_link" && "$(readlink "$task_link")" == "$task_cli" ]]; then rm "$task_link"; fi
        if [[ "$task_installed" == 1 ]]; then rm -rf "$task_destination"; fi
        if [[ -d "$task_stage/Previous-Room.app" ]]; then mv "$task_stage/Previous-Room.app" "$task_destination"; fi
    fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
ditto dist/Room.app "$task_stage/Room.app"
codesign --verify --deep --strict "$task_stage/Room.app"
if [[ -d "$task_destination" ]]; then mv "$task_destination" "$task_stage/Previous-Room.app"; fi
mv "$task_stage/Room.app" "$task_destination"
task_installed=1
if [[ ! -L "$task_link" ]]; then ln -s "$task_cli" "$task_link"; task_link_created=1; fi
codesign --verify --deep --strict "$task_destination"
task_complete=1
if [[ "${ROOM_SKIP_LSREGISTER:-0}" != 1 ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$task_destination" 2>/dev/null || true
fi
printf 'Installed %s\nCLI: %s\n' "$task_destination" "$task_link"

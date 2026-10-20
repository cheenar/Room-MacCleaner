#!/bin/bash
# Adapted from iridium-wm/scripts/signing-identity.sh.
# --resolve is read-only. --create adds a local signing identity to the login
# keychain and asks macOS to trust it for this user's code signing only.
set -euo pipefail

NAME="${SIGNING_NAME:-Room Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

identities() { /usr/bin/security find-identity -v -p codesigning 2>/dev/null || true; }
find_identity() {
    identities | /usr/bin/awk -v name="$1" '$2 == name || index($0, "\"" name "\"") { print $2; exit }'
}

resolve() {
    local requested="${SIGN_ID:-auto}" identity
    if [[ "$requested" == "-" ]]; then printf '%s\n' -; return; fi
    if [[ "$requested" != "auto" ]]; then
        identity=$(find_identity "$requested")
        if [[ -z "$identity" ]]; then
            printf 'Signing identity not found: %s\n' "$requested" >&2
            return 1
        fi
    else
        identity=$(find_identity "$NAME")
        if [[ -z "$identity" ]]; then identity=$(find_identity "Iridium Local Signing"); fi
    fi
    printf '%s\n' "${identity:--}"
}

case "${1:---create}" in
    --resolve) resolve; exit ;;
    --create) ;;
    *) printf 'Usage: %s [--create|--resolve]\n' "$0" >&2; exit 64 ;;
esac

if [[ -n "$(find_identity "$NAME")" ]]; then
    printf 'Ready: %s\n' "$NAME"
    exit 0
fi
if /usr/bin/security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    printf 'A certificate named "%s" exists but is not trusted for code signing.\n' "$NAME" >&2
    printf 'In Keychain Access, open it → Trust → Code Signing: Always Trust, or delete it and rerun.\n' >&2
    exit 1
fi

umask 077
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/room-signing.XXXXXXXX")
cleanup() {
    rm -f "$task_tmp/key.pem" "$task_tmp/cert.pem" "$task_tmp/identity.p12"
    rmdir "$task_tmp" 2>/dev/null || true
}
trap cleanup EXIT
task_pass=$(/usr/bin/openssl rand -hex 16)

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$task_tmp/key.pem" -out "$task_tmp/cert.pem" -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$task_tmp/key.pem" -in "$task_tmp/cert.pem" \
    -out "$task_tmp/identity.p12" -passout "pass:$task_pass" 2>/dev/null

# The private key is non-exportable; codesign is its only pre-authorized client.
/usr/bin/security import "$task_tmp/identity.p12" -k "$KEYCHAIN" -P "$task_pass" -x -T /usr/bin/codesign >/dev/null
printf 'Imported "%s" into your login keychain.\n' "$NAME"
printf 'Trusting it for code signing; macOS may ask for your password…\n'
if ! /usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$task_tmp/cert.pem"; then
    printf 'In Keychain Access, open "%s" → Trust → Code Signing: Always Trust, then run make install.\n' "$NAME" >&2
    exit 1
fi
if [[ -z "$(find_identity "$NAME")" ]]; then
    printf 'The identity was created but is not yet valid for code signing. Check its trust in Keychain Access.\n' >&2
    exit 1
fi
printf 'Ready: %s. Future builds use the same signing identity.\n' "$NAME"
# Undo in Keychain Access → login → My Certificates → delete Room Local Signing.

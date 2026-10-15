#!/bin/bash
# Import the pinned NIKO self-signed identity into a throwaway keychain (CI only).
#
#   NIKO_SIGNING_P12_BASE64=… NIKO_SIGNING_P12_PASSWORD=… scripts/import-signing.sh
#
# Appends NIKO_SIGN_IDENTITY (and NIKO_SIGN_KEYCHAIN, for clean-up) to $GITHUB_ENV.
# Exits 0 without doing anything when the secret is absent (forks, pull requests);
# a tag build then fails in make-release.sh, which insists on the NIKO identity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GITHUB_ENV:?import-signing.sh writes its result to GITHUB_ENV}"
if [ -z "${NIKO_SIGNING_P12_BASE64:-}" ]; then
    echo "import-signing.sh: no NIKO signing secret; packages will be ad-hoc signed"
    exit 0
fi

DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/niko-signing.XXXXXX")"
KEYCHAIN="$DIR/signing.keychain-db"
PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$PASSWORD"
printf '%s' "$NIKO_SIGNING_P12_BASE64" | base64 -D > "$DIR/certificate.p12"
chmod 600 "$DIR/certificate.p12"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$DIR/certificate.p12" -P "${NIKO_SIGNING_P12_PASSWORD:-}" -f pkcs12 \
    -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
rm "$DIR/certificate.p12"

IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/"NIKO Code Signing"/ { print $2; exit }')"
PINNED="$(tr -d ' \n' < "$ROOT/scripts/signing-identity.sha1")"
if [ "$IDENTITY" != "$PINNED" ]; then
    echo "import-signing.sh: the secret holds certificate '$IDENTITY', not the pinned $PINNED" >&2
    exit 1
fi
printf 'NIKO_SIGN_IDENTITY=%s\nNIKO_SIGN_KEYCHAIN=%s\n' "$IDENTITY" "$KEYCHAIN" >> "$GITHUB_ENV"
echo "import-signing.sh: signing with the NIKO identity $IDENTITY"

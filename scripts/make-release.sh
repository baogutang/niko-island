#!/bin/bash
# Build and check what a release ships: one package per architecture.
# There is deliberately no universal build — people pick the download that
# matches their Mac and get an app half the size.
#
#   scripts/make-release.sh                 build both, then verify
#   scripts/make-release.sh --out <dir>     output directory (default: dist)
#   scripts/make-release.sh --verify-only   check packages that are already there
#
# Leaves behind:
#   <dir>/apple-silicon/Niko Island.app     arm64
#   <dir>/intel/Niko Island.app             x86_64
#   <dir>/release/Niko-Island-<version>-apple-silicon.dmg  .zip
#   <dir>/release/Niko-Island-<version>-intel.dmg          .zip
#   <dir>/release/SHA256SUMS                all four files
#
# The Intel build is run under Rosetta when this Mac has it; without Rosetta
# (or on an Intel Mac, for the arm64 build) the "does it start" checks for the
# foreign architecture are skipped and said so.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist"
BUILD=1

while [ $# -gt 0 ]; do
    case "$1" in
        --out) shift; OUT="${1:?--out needs a directory}" ;;
        --verify-only) BUILD=0 ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "make-release.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
    shift
done

cd "$ROOT"
RELEASE="$OUT/release"
APP_NAME="Niko Island"
HOST_ARCH="$(uname -m)"

# label:architecture, in the order the downloads are listed.
FLAVOURS=("apple-silicon:arm64" "intel:x86_64")

if [ "$BUILD" -eq 1 ]; then
    rm -rf "$RELEASE"
    mkdir -p "$RELEASE"
    for flavour in "${FLAVOURS[@]}"; do
        label="${flavour%%:*}"
        arch="${flavour##*:}"
        rm -rf "${OUT:?}/$label"
        "$ROOT/scripts/make-app.sh" --arch "$arch" --zip --dmg --out "$OUT/$label"
        mv "$OUT/$label"/Niko-Island-*-"$label".zip "$OUT/$label"/Niko-Island-*-"$label".dmg "$RELEASE/"
        rm -f "$OUT/$label/SHA256SUMS"
    done
    (cd "$RELEASE" && shasum -a 256 Niko-Island-*.dmg Niko-Island-*.zip > SHA256SUMS)
fi

# Can this Mac run a binary of the given architecture?
runs() {
    [ "$1" = "$HOST_ARCH" ] && return 0
    [ "$1" = "x86_64" ] && [ "$HOST_ARCH" = "arm64" ] && arch -x86_64 /usr/bin/true 2>/dev/null
}

check_bundle() {
    local app="$1" arch="$2"
    local product
    for product in MacOS/niko-island Helpers/niko-bridge; do
        [ "$(lipo -archs "$app/Contents/$product")" = "$arch" ] || {
            echo "make-release.sh: $app/Contents/$product is not $arch only" >&2
            return 1
        }
    done
    codesign --verify --deep --strict "$app"
    # Read the whole description first: a pipe into `grep -q` would close early.
    local signature
    signature="$(codesign -dv "$app" 2>&1)"
    case "$signature" in
        *"Signature=adhoc"*) ;;
        *) echo "make-release.sh: $app is not ad-hoc signed" >&2; return 1 ;;
    esac
}

MOUNT=""
WORK="$(mktemp -d "${TMPDIR:-/tmp}/niko-release.XXXXXX")"
cleanup() {
    if [ -n "$MOUNT" ]; then hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

for flavour in "${FLAVOURS[@]}"; do
    label="${flavour%%:*}"
    arch="${flavour##*:}"
    app="$OUT/$label/$APP_NAME.app"
    echo "==> verifying $label ($arch)"

    [ -d "$app" ] || { echo "make-release.sh: $app is missing" >&2; exit 1; }
    check_bundle "$app" "$arch"
    if runs "$arch"; then
        "$app/Contents/Helpers/niko-bridge" --integrity-check "$app"
        "$app/Contents/MacOS/niko-island" --version
        "$app/Contents/Helpers/niko-bridge" --version
    else
        echo "    (this Mac cannot run $arch: start-up checks skipped)"
    fi

    zips=("$RELEASE"/Niko-Island-*-"$label".zip)
    dmgs=("$RELEASE"/Niko-Island-*-"$label".dmg)
    if [ "${#zips[@]}" -ne 1 ] || [ ! -f "${zips[0]}" ]; then
        echo "make-release.sh: expected one $label zip" >&2
        exit 1
    fi
    if [ "${#dmgs[@]}" -ne 1 ] || [ ! -f "${dmgs[0]}" ]; then
        echo "make-release.sh: expected one $label dmg" >&2
        exit 1
    fi

    # The zip unpacks to the same, still-valid bundle.
    mkdir -p "$WORK/$label"
    ditto -x -k "${zips[0]}" "$WORK/$label"
    check_bundle "$WORK/$label/$APP_NAME.app" "$arch"

    # The disk image mounts and holds the bundle next to an Applications shortcut.
    hdiutil verify -quiet "${dmgs[0]}"
    MOUNT="$WORK/mount-$label"
    mkdir -p "$MOUNT"
    hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MOUNT" "${dmgs[0]}"
    check_bundle "$MOUNT/$APP_NAME.app" "$arch"
    [ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || { echo "make-release.sh: no Applications shortcut in the $label image" >&2; exit 1; }
    [ -s "$MOUNT/Read me first.txt" ] || { echo "make-release.sh: no read-me in the $label image" >&2; exit 1; }
    hdiutil detach -quiet "$MOUNT"
    MOUNT=""
done

# Nothing universal, nothing extra: four packages and their checksums.
count="$(find "$RELEASE" -type f | wc -l | tr -d ' ')"
[ "$count" = "5" ] || { echo "make-release.sh: expected 5 files in $RELEASE, found $count" >&2; ls -l "$RELEASE" >&2; exit 1; }
[ "$(wc -l < "$RELEASE/SHA256SUMS" | tr -d ' ')" = "4" ] || { echo "make-release.sh: SHA256SUMS should list 4 files" >&2; exit 1; }
(cd "$RELEASE" && shasum -a 256 -c SHA256SUMS)

echo "==> release packages in $RELEASE"
ls -lh "$RELEASE"

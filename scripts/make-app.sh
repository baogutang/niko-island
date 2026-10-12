#!/bin/bash
# Assemble "Niko Island.app" from SwiftPM build products and ad-hoc sign it.
#
#   scripts/make-app.sh                 release build for the host architecture
#   scripts/make-app.sh --universal     arm64 + x86_64, merged with lipo
#   scripts/make-app.sh --debug         debug configuration
#   scripts/make-app.sh --zip           also write dist/Niko-Island-<version>-<arch>.zip + SHA256SUMS
#   scripts/make-app.sh --out <dir>     output directory (default: dist)
#   scripts/make-app.sh --skip-build    reuse existing .build products
#
# No Apple Developer account is involved: the bundle is signed ad hoc
# (`codesign -s -`), which is enough for it to run once the user has cleared
# the download quarantine (`xattr -cr`; right-click → Open on macOS 14;
# System Settings → Privacy & Security → Open Anyway on macOS 15+).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="release"
UNIVERSAL=0
MAKE_ZIP=0
SKIP_BUILD=0
OUT="$ROOT/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --universal) UNIVERSAL=1 ;;
        --debug) CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        --zip) MAKE_ZIP=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --out) shift; OUT="${1:?--out needs a directory}" ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "make-app.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
    shift
done

cd "$ROOT"

APP_NAME="Niko Island"
BUNDLE_ID="app.nikoisland.macos"
VERSION="${NIKO_VERSION:-$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/NikoCore/Version.swift | head -n 1)}"
BUILD_NUMBER="${NIKO_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
[ -n "$VERSION" ] || { echo "make-app.sh: could not determine version" >&2; exit 1; }

if [ "$UNIVERSAL" -eq 1 ]; then
    ARCHS=(arm64 x86_64)
    ARCH_LABEL="universal"
else
    ARCHS=("$(uname -m)")
    ARCH_LABEL="${ARCHS[0]}"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/niko-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for arch in "${ARCHS[@]}"; do
    if [ "$SKIP_BUILD" -eq 0 ]; then
        echo "==> swift build ($CONFIG, $arch)"
        swift build -c "$CONFIG" --arch "$arch" --product niko-island
        swift build -c "$CONFIG" --arch "$arch" --product niko-bridge
    fi
    BIN_DIR="$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)"
    for product in niko-island niko-bridge; do
        [ -x "$BIN_DIR/$product" ] || { echo "make-app.sh: missing $BIN_DIR/$product" >&2; exit 1; }
        cp "$BIN_DIR/$product" "$STAGE/$product.$arch"
    done
done

for product in niko-island niko-bridge; do
    if [ "$UNIVERSAL" -eq 1 ]; then
        lipo -create "$STAGE/$product.arm64" "$STAGE/$product.x86_64" -output "$STAGE/$product"
    else
        cp "$STAGE/$product.${ARCHS[0]}" "$STAGE/$product"
    fi
done

APP="$OUT/$APP_NAME.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$STAGE/niko-island" "$APP/Contents/MacOS/niko-island"
cp "$STAGE/niko-bridge" "$APP/Contents/Helpers/niko-bridge"
chmod 755 "$APP/Contents/MacOS/niko-island" "$APP/Contents/Helpers/niko-bridge"

ICON_KEY=""
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

for resource in pricing.json LITELLM-NOTICE.txt; do
    if [ -f "$ROOT/Assets/$resource" ]; then
        cp "$ROOT/Assets/$resource" "$APP/Contents/Resources/$resource"
    fi
done

# String catalog → per-language .strings (SwiftPM does not compile .xcstrings itself).
if [ -f "$ROOT/Assets/Localizable.xcstrings" ]; then
    if xcrun --find xcstringstool >/dev/null 2>&1; then
        xcrun xcstringstool compile "$ROOT/Assets/Localizable.xcstrings" \
            --output-directory "$APP/Contents/Resources"
    else
        echo "make-app.sh: xcstringstool not found, shipping English only" >&2
    fi
fi
# English is the key itself. An (empty) en.lproj makes "en" a real localization
# so English systems do not fall through to the only other table.
mkdir -p "$APP/Contents/Resources/en.lproj"
if [ ! -f "$APP/Contents/Resources/en.lproj/Localizable.strings" ]; then
    printf '/* English strings are the lookup keys. */\n' > "$APP/Contents/Resources/en.lproj/Localizable.strings"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>niko-island</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
$ICON_KEY
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Niko Island uses Apple Events only to bring the terminal tab that is waiting for you to the front.</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License. Not affiliated with any AI vendor.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID.bridge" "$APP/Contents/Helpers/niko-bridge"
codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> $APP ($VERSION build $BUILD_NUMBER, $ARCH_LABEL)"
lipo -archs "$APP/Contents/MacOS/niko-island"

if [ "$MAKE_ZIP" -eq 1 ]; then
    ZIP_NAME="Niko-Island-$VERSION-$ARCH_LABEL.zip"
    rm -f "$OUT/$ZIP_NAME"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP_NAME"
    (cd "$OUT" && shasum -a 256 ./*.zip | sed 's|\./||' > SHA256SUMS)
    echo "==> $OUT/$ZIP_NAME"
    cat "$OUT/SHA256SUMS"
fi

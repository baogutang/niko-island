#!/bin/bash
# Assemble "Niko Island.app" from SwiftPM build products and ad-hoc sign it.
#
#   scripts/make-app.sh                 release build for the host architecture
#   scripts/make-app.sh --arch arm64    build for one architecture (arm64 or x86_64);
#                                       releases ship one package per architecture
#                                       (scripts/make-release.sh builds both)
#   scripts/make-app.sh --debug         debug configuration
#   scripts/make-app.sh --zip           also write dist/Niko-Island-<version>-<arch>.zip
#   scripts/make-app.sh --dmg           also write dist/Niko-Island-<version>-<arch>.dmg
#                                       (--zip and --dmg write SHA256SUMS for what they made)
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
ONE_ARCH=""
MAKE_ZIP=0
MAKE_DMG=0
SKIP_BUILD=0
OUT="$ROOT/dist"

while [ $# -gt 0 ]; do
    case "$1" in
        --arch) shift; ONE_ARCH="${1:?--arch needs arm64 or x86_64}" ;;
        --debug) CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        --zip) MAKE_ZIP=1 ;;
        --dmg) MAKE_DMG=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --out) shift; OUT="${1:?--out needs a directory}" ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

ARCH="${ONE_ARCH:-$(uname -m)}"
# File names say what people look for when they choose a download.
case "$ARCH" in
    arm64) ARCH_LABEL="apple-silicon" ;;
    x86_64) ARCH_LABEL="intel" ;;
    *) echo "make-app.sh: --arch must be arm64 or x86_64" >&2; exit 64 ;;
esac

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/niko-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "==> swift build ($CONFIG, $ARCH)"
    swift build -c "$CONFIG" --arch "$ARCH" --product niko-island
    swift build -c "$CONFIG" --arch "$ARCH" --product niko-bridge
fi
BIN_DIR="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
for product in niko-island niko-bridge; do
    [ -x "$BIN_DIR/$product" ] || { echo "make-app.sh: missing $BIN_DIR/$product" >&2; exit 1; }
    cp "$BIN_DIR/$product" "$STAGE/$product"
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>nikoisland</string>
            </array>
        </dict>
    </array>
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

ARTIFACTS=()

if [ "$MAKE_ZIP" -eq 1 ]; then
    ZIP_NAME="Niko-Island-$VERSION-$ARCH_LABEL.zip"
    rm -f "$OUT/$ZIP_NAME"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP_NAME"
    ARTIFACTS+=("$ZIP_NAME")
    echo "==> $OUT/$ZIP_NAME"
fi

if [ "$MAKE_DMG" -eq 1 ]; then
    # A plain disk image: the app, a shortcut to /Applications to drag it onto,
    # and a note about the one step an ad-hoc signed app needs.
    DMG_NAME="Niko-Island-$VERSION-$ARCH_LABEL.dmg"
    DMG_ROOT="$STAGE/dmg"
    mkdir -p "$DMG_ROOT"
    ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
    ln -s /Applications "$DMG_ROOT/Applications"
    cat > "$DMG_ROOT/Read me first.txt" <<'NOTE'
Niko Island

1. Drag "Niko Island" onto "Applications".
2. The app is ad-hoc signed (this project has no Apple Developer account),
   so macOS will not open a downloaded copy straight away. Clear the
   download flag once, in Terminal:

       xattr -cr "/Applications/Niko Island.app"

   Without Terminal: on macOS 14, right-click the app and choose Open.
   On macOS 15 or later, try to open it once, then go to
   System Settings > Privacy & Security and click "Open Anyway".
3. Open it from Applications, not from this window.

------------------------------------------------------------

1. 把 "Niko Island" 拖到 "Applications"（应用程序）上。
2. 应用采用 ad-hoc 签名（本项目没有 Apple 开发者账号），所以 macOS
   不会直接打开下载来的副本。在“终端”里执行一次：

       xattr -cr "/Applications/Niko Island.app"

   不用终端的话：在 macOS 14 上右键点击应用并选择“打开”；在 macOS 15
   及更新版本上，先尝试打开一次，再到“系统设置 > 隐私与安全性”里点击
   “仍要打开”。
3. 请从“应用程序”里打开它，不要在这个窗口里直接运行。

https://github.com/baogutang/niko-island
NOTE
    rm -f "$OUT/$DMG_NAME"
    # hdiutil now and then answers "Resource busy" on shared runners; trying again clears it.
    attempt=1
    until hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO \
            -imagekey zlib-level=9 -ov -quiet "$OUT/$DMG_NAME"; do
        if [ "$attempt" -ge 4 ]; then
            echo "make-app.sh: hdiutil could not create the disk image" >&2
            exit 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    ARTIFACTS+=("$DMG_NAME")
    echo "==> $OUT/$DMG_NAME"
fi

if [ "${#ARTIFACTS[@]}" -gt 0 ]; then
    (cd "$OUT" && shasum -a 256 "${ARTIFACTS[@]}" > SHA256SUMS)
    cat "$OUT/SHA256SUMS"
fi

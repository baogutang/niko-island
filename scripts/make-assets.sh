#!/bin/bash
# Regenerates the committed artwork from code:
#   Assets/AppIcon.icns          the app icon (drawn in IconRenderer)
#   docs/images/panel-*.png      README/website images, rendered from the real
#                                panel views with sample sessions
# Needs a debug build; run it after changing the icon or the panel layout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
swift build --product niko-island
BIN="$(swift build --show-bin-path)/niko-island"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/niko-assets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

"$BIN" internal render-icon "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Assets/AppIcon.icns"
cp "$WORK/AppIcon.iconset/icon_256x256.png" "$ROOT/docs/images/icon.png"
mkdir -p "$ROOT/website"
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/website/icon.png"

mkdir -p "$ROOT/docs/images"
"$BIN" internal render-preview "$ROOT/docs/images" -AppleLanguages "(en)"
for scene in sessions question usage; do
    cp "$ROOT/docs/images/panel-$scene.png" "$ROOT/website/panel-$scene.png"
done
ls -la "$ROOT/Assets/AppIcon.icns" "$ROOT/docs/images"

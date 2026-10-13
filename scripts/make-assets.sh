#!/bin/bash
# Regenerates the committed artwork from code. Nothing here is drawn by hand
# or taken from anywhere else:
#   Assets/AppIcon.icns            the app icon (IconRenderer)
#   docs/images/island-*.png       the island's states, rendered from the real
#                                  views with sample sessions (PreviewRenderer)
#   docs/images/island-demo.gif    a short walk through those states
#   docs/images/mascots/           one creature per agent (PNG + two-frame GIF)
#   website/                       the subset the website uses
# Needs a debug build; run it after changing the icon, the creatures or the layout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
swift build --product niko-island
BIN="$(swift build --show-bin-path)/niko-island"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/niko-assets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

"$BIN" internal render-icon "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Assets/AppIcon.icns"

rm -rf "$ROOT/docs/images"
mkdir -p "$ROOT/docs/images"
cp "$WORK/AppIcon.iconset/icon_256x256.png" "$ROOT/docs/images/icon.png"
"$BIN" internal render-preview "$ROOT/docs/images" -AppleLanguages "(en)" >/dev/null

mkdir -p "$ROOT/website/mascots"
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/website/icon.png"
for image in island-sessions island-question island-usage island-settings-sounds island-settings-island island-onboarding island-onboarding-agents; do
    cp "$ROOT/docs/images/$image.png" "$ROOT/website/$image.png"
done
cp "$ROOT/docs/images/island-demo.gif" "$ROOT/website/island-demo.gif"
cp "$ROOT"/docs/images/mascots/*.gif "$ROOT/website/mascots/"
find "$ROOT/docs/images" "$ROOT/website" -type f \( -name '*.png' -o -name '*.gif' \) -exec stat -f '%8z  %N' {} + | sed "s|$ROOT/||"

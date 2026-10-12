#!/bin/bash
# Launch the assembled app against a throwaway runtime dir, check it stays up, then quit it.
#   scripts/smoke-launch.sh [path/to/Niko Island.app]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/Niko Island.app}"
BIN="$APP/Contents/MacOS/niko-island"
[ -x "$BIN" ] || { echo "smoke: $BIN not found (run scripts/make-app.sh first)" >&2; exit 1; }

HOME_DIR="$(mktemp -d /private/tmp/nk-smoke.XXXXXX)"
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$HOME_DIR"' EXIT
NIKO_ISLAND_HOME="$HOME_DIR/ni" "$BIN" -NikoNotificationsDisabled YES >"$HOME_DIR/out.log" 2>&1 &
PID=$!

for _ in $(seq 1 30); do
    kill -0 "$PID" 2>/dev/null || { echo "smoke: app exited early" >&2; cat "$HOME_DIR/out.log" >&2; exit 1; }
    sleep 0.1
done
echo "smoke: app alive after 3s (pid $PID)"
if [ -S "$HOME_DIR/ni/run/niko-island.sock" ]; then
    echo "smoke: ingress socket present"
fi

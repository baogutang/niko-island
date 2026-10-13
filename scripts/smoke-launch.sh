#!/bin/bash
# End-to-end smoke test of the assembled app bundle, against a throwaway runtime
# directory (your real ~/.niko-island and agent configs are never touched).
#
#   scripts/smoke-launch.sh [path/to/Niko Island.app]
#
# Checks: the app starts, the ingress socket answers, the bundled bridge can
# deliver an event, the island window lays out collapsed and opens for a
# request, a pending approval is released when the app quits, and how long a
# cold start takes until the first event is accepted.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/Niko Island.app}"
BIN="$APP/Contents/MacOS/niko-island"
BRIDGE="$APP/Contents/Helpers/niko-bridge"
[ -x "$BIN" ] || { echo "smoke: $BIN not found (run scripts/make-app.sh first)" >&2; exit 1; }
[ -x "$BRIDGE" ] || { echo "smoke: $BRIDGE not found" >&2; exit 1; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'; }

WORK="$(mktemp -d /private/tmp/nk-smoke.XXXXXX)"
export NIKO_ISLAND_HOME="$WORK/ni"
PID=""
cleanup() {
    if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

EVENT='{"hook_event_name":"SessionStart","session_id":"smoke","cwd":"'"$ROOT"'"}'

START="$(now_ms)"
NIKO_ISLAND_DEBUG=1 "$BIN" -NikoNotificationsDisabled YES -NikoOnboardingDisabled YES >"$WORK/out.log" 2>&1 &
PID=$!

# Cold start: keep offering an event until the app has accepted one.
READY=""
for _ in $(seq 1 200); do
    kill -0 "$PID" 2>/dev/null || { echo "smoke: app exited early" >&2; cat "$WORK/out.log" >&2; exit 1; }
    if "$BIN" status 2>/dev/null | grep -q "app: running"; then
        printf '%s' "$EVENT" | "$BRIDGE" --source claude
        READY="$(now_ms)"
        break
    fi
    sleep 0.02
done
[ -n "$READY" ] || { echo "smoke: ingress never came up" >&2; cat "$WORK/out.log" >&2; exit 1; }
echo "smoke: cold start to first accepted event: $((READY - START)) ms"

[ -S "$NIKO_ISLAND_HOME/run/niko-island.sock" ] || { echo "smoke: socket missing" >&2; exit 1; }
MODE="$(stat -f '%Lp' "$NIKO_ISLAND_HOME/run")"
[ "$MODE" = "700" ] || { echo "smoke: run dir mode is $MODE, expected 700" >&2; exit 1; }
echo "smoke: socket present, run dir 0700"

# The island window: collapsed it is a small tab at the top of its canvas.
wait_for() {
    for _ in $(seq 1 60); do
        if grep -q "$1" "$WORK/out.log"; then return 0; fi
        sleep 0.05
    done
    return 1
}
wait_for "island frame .*expanded=false" || { echo "smoke: the island never laid itself out" >&2; cat "$WORK/out.log" >&2; exit 1; }
COLLAPSED="$(grep "island frame .*expanded=false" "$WORK/out.log" | tail -n 1 | sed 's/.*island frame //')"
case "$COLLAPSED" in
    *" y=0 "*) ;;
    *) echo "smoke: collapsed island is not flush with the top: $COLLAPSED" >&2; exit 1 ;;
esac
echo "smoke: island collapsed  ($COLLAPSED)"

# A pending approval opens the island, and must be released (exit 0, no output)
# when the app goes away.
REQUEST='{"hook_event_name":"PermissionRequest","session_id":"smoke","cwd":"'"$ROOT"'","tool_name":"Bash","tool_input":{"command":"true"}}'
(printf '%s' "$REQUEST" | "$BRIDGE" --source claude >"$WORK/reply.txt" 2>&1; echo $? >"$WORK/reply.status") &
BRIDGE_JOB=$!
wait_for "island frame .* w=640 .*expanded=true" || { echo "smoke: the island did not open for a permission request" >&2; cat "$WORK/out.log" >&2; exit 1; }
echo "smoke: island expanded   ($(grep "expanded=true" "$WORK/out.log" | tail -n 1 | sed 's/.*island frame //'))"
sleep 0.3
kill "$PID"
wait "$PID" 2>/dev/null || true
PID=""
wait "$BRIDGE_JOB" || true
STATUS="$(cat "$WORK/reply.status" 2>/dev/null || echo missing)"
[ "$STATUS" = "0" ] || { echo "smoke: bridge exited $STATUS after app quit" >&2; exit 1; }
[ ! -s "$WORK/reply.txt" ] || { echo "smoke: bridge printed output without a decision:" >&2; cat "$WORK/reply.txt" >&2; exit 1; }
echo "smoke: pending approval released cleanly on app quit"

# With the app gone, hooks are no-ops.
printf '%s' "$EVENT" | "$BRIDGE" --source claude
echo "smoke: bridge is a silent no-op without the app"
echo "smoke: OK"

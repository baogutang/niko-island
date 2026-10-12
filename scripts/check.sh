#!/bin/bash
# Build and run the whole test suite; non-zero exit if anything fails.
# Prints only the summary (and the failures, if any).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
LOG="$(mktemp "${TMPDIR:-/tmp}/niko-check.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
if swift test "$@" >"$LOG" 2>&1; then
    grep -E "Executed [0-9]+ tests" "$LOG" | tail -n 1
    echo "check: OK"
else
    grep -E "error:|' failed|Executed [0-9]+ tests|skipped" "$LOG" | tail -n 40
    echo "check: FAILED" >&2
    exit 1
fi

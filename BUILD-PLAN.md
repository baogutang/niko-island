# niko-island — Overnight Build Plan

Execution order is strict. Each milestone ends with: code committed
(conventional message), `PROGRESS.md` updated, build green.

## Environment
Swift 6 + AppKit/SwiftUI, SwiftPM (`swift build -c release`), no Xcode project
file needed. App bundle assembled by `scripts/make-app.sh` (creates
`Niko Island.app/Contents/{MacOS,Resources}`, Info.plist, ad-hoc
`codesign -s -`). CI: GitHub Actions `macos-14`/`macos-15` runners.

## M0 — Skeleton (30 min)
SwiftPM executable target `niko-island`; AppKit app with `LSUIElement`,
menu-bar `NSStatusItem`, empty SwiftUI panel; runs via `swift run`.
`scripts/make-app.sh` produces a launchable unsigned .app. Commit.

## M1 — Ingress server (1 h)
Unix socket server (POSIX socket or Network.framework), newline-JSON framing,
probe handling, uid/dir permission hardening (0700, symlink reject),
ring buffer (1024 events) + per-session admission evidence (cwd, peer uid).
Unit tests with a real socket client. Commit.

## M2 — Bridge + statusline (1 h)
`niko-bridge` CLI target (reads stdin JSON, forwards, blocking reply for
PermissionRequest with behavior mapping approve/deny/block → stdout JSON /
exit codes; failure ⇒ exit 0 always). Shim generator writing
`~/.niko-island/bin/niko-bridge` (locating binary: fixed paths → cache file →
mdfind fallback → silent exit 0). `niko-statusline` bash script with preserved
user section. Integration test: fake agent → bridge → socket → fake decision →
bridge stdout. Commit.

## M3 — Installer + scan (1.5 h)
`<<<NI:section>>>` scan probe (POSIX sh, size-capped base64 reads);
settings-JSON merge logic (foreign entries preserved, ours tagged `niko-bridge`);
atomic writes + `.niko-backup-<ts>`; rollback + uninstall (marker-based).
Claude Code full wiring incl. statusLine + timeouts (PermissionRequest 86400).
Dry-run mode mandatory. Tests: mutate/rollback on fixture configs. Commit.

## M4 — Panel UI (2 h)
Notch/menu-bar panel; session cards (agent SF Symbol, project, activity verb
per PROTOCOLS §1.2, elapsed); permission cards with Allow once / Allow always /
Deny / Allow-all / open-in-terminal; question wizard (multi-Q, single/multi
select) replying `updatedInput.answers`; local notifications + AppleScript
jump-back (iTerm2 by ITERM_SESSION_ID incl. tmux, Terminal.app by tty).
Manual test checklist in `docs/TESTPLAN.md`. Commit.

## M5 — Usage engine (1.5 h)
SQLite (WAL) schema per PROTOCOLS §6.1; JSONL tailer with
committed_offset/tail_hash resume + identity dedupe; Claude/Codex/OpenCode
parsers; LiteLLM pricing snapshot vendored (`Assets/pricing.json`, keep
license notice) + estimator; usage panel (today/7d per agent/model, cost).
Statusline rl.json cache read for Claude rate-limits. Tests with fixture JSONL.
Commit.

## M6 — Release engineering (1 h)
`scripts/make-app.sh` robust; `.github/workflows/release.yml`: on tag →
`swift build -c release --arch arm64 --arch x86_64` (or matrix), assemble
universal .app, zip, `gh release create` with SHA256SUMS; workflow_dispatch
nightly. README.md + README.zh-CN.md (see below). `website/` GitHub Pages
source (see below). First local git tag `v0.1.0`. Commit.

## M7 — Adversarial review (required gate)
Execute REVIEW.md checklist; file issues for findings; fix blockers before
push. Then: `gh repo create niko-island --public --source=. --push`,
push tag, verify Actions run green and release artifact downloadable, enable
GitHub Pages (deploy from `website/` via config or `gh api`), verify site live.

## README quality bar (must meet all)
- Hero: one-line value prop + panel screenshot placeholder (`docs/` path,
  add real screenshot later) + badges (release, license, platform)
- 30-second quickstart (download → xattr -cr → run → `niko-island install`)
- Feature grid with icons (SF-Symbols-style emoji ok)
- Supported-agents table (from INTEGRATIONS.md)
- Privacy section: "no telemetry, no accounts, all local" with concrete list
- Comparison vs closed alternatives: free & open source, no license/activation,
  no tracking, community-driven
- FAQ: Gatekeeper (right-click Open), uninstall (`niko-island uninstall`
  leaves agents functional), Roadmap link
- Bilingual: English primary, 简体中文 full translation

## Website (`website/index.html`, GitHub Pages)
Single static page, no build step, inline CSS (system font stack, dark hero
matching app aesthetic): sticky nav; hero with tagline + CTA buttons (Download
latest release via releases/latest link, GitHub); feature grid; agents strip;
privacy blurb; install snippet; footer (MIT, not affiliated with any AI
vendor). Original copy only. `CNAME` not needed.

## Quota-window resume protocol (critical)
Maintain `PROGRESS.md` (git-ignored? no — commit it) at repo root:
```
# PROGRESS
updated: <iso-ts>
milestone: M4
done: [M0,M1,M2,M3]
next: "M4 question wizard — PROTOCOLS §2.2 updatedInput.answers"
notes: ["panel renders sessions", "approvals e2e green"]
```
At session start: read PROGRESS.md → `git log --oneline -5` → verify build →
continue at `next`. Never restart completed milestones; if uncertain, run
tests to rediscover state. Update the file after every task, not just
milestones. When a quota/API window interrupts, the next session continues
from the file — that is the whole point.

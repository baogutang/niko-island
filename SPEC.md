# niko-island — Product Specification

A free, open-source macOS menu-bar companion for AI coding agents.
niko-island watches every AI coding agent running in your terminals, shows live
status in a notch/menu-bar panel, lets you approve permission requests and answer
questions without switching windows, and tracks token usage & cost locally.

Design pillars (in priority order):

1. **Local-first & private** — no telemetry, no accounts, no license keys. All data
   stays in `~/.niko-island/`. The app never proxies your credentials anywhere.
2. **Zero-configuration resilience** — hook registration must be defensive: if the
   app is uninstalled, agents keep working (shims exit 0 silently).
3. **One event dialect** — all agents are normalized into the Claude Code hook
   JSON dialect internally (publicly documented schema), translated by per-agent
   adapters.
4. **No Apple Developer Account required** — ad-hoc signed, distributed via GitHub
   Releases; users bypass Gatekeeper with right-click → Open (documented).

## 1. App identity

- Bundle id: `app.nikoisland.macos`, display name "Niko Island"
- `LSUIElement = true` (menu-bar only, no Dock icon)
- min macOS 14.0, Swift 6 + SwiftUI + AppKit hybrid
- Universal binary not required for v1 (arm64 release build + x86_64 in CI matrix)

## 2. Runtime layout (all under `~/.niko-island/`)

```
~/.niko-island/
├── bin/        niko-bridge, niko-statusline (shims, auto-generated)
├── run/        niko-island.sock   (0700 dir, owned by user, no symlinks)
├── cache/      rl.json (rate-limit cache), usage-persist-*.json
├── data/usage/ usage.sqlite (+wal/shm)
└── logs/       rotated diagnostics
```

## 3. Feature set (v1 = MVP through v3)

### v1 — Core loop (must ship tonight)
- Menu-bar icon + expandable notch-style panel (hover/click), SwiftUI
- Live per-session status: thinking / reading / editing / running tool X
- Unix-socket ingress server (see PROTOCOLS.md) with newline-delimited JSON
- Session store keyed by (source, session_id); transcript path & cwd attached
- Permission-request cards: Allow once / Allow always (session) / Deny /
  Allow all (session) / open-in-terminal
- Question wizard (multi-question, single/multi-select) answering back through
  the same reply channel
- macOS local notifications on: agent idle/stop waiting for input, permission
  request, question; click → AppleScript jump to the originating iTerm2 /
  Terminal.app tab (`ITERM_SESSION_ID` aware, tmux-aware)
- Claude Code integration end-to-end (hooks + statusline) — see INTEGRATIONS.md
- Hook installer with dry-run scan + rollback (only removes entries it owns)

### v2 — Usage & more agents
- Token usage from local transcripts (see PROTOCOLS.md §Usage), SQLite storage
- Cost estimation from embedded LiteLLM pricing snapshot + runtime refresh
- Claude rate-limits from statusline payload cache (`cache/rl.json`)
- Codex, Cursor, Gemini CLI, OpenCode integrations

### v3 — Polish & remote
- Custom sound packs + per-event sound gates, focus-mode-aware suppression
- SSH remote monitoring (reverse tunnel + remote hook binary, own Ed25519 key)
- Session auto-naming (heuristic: repo name + first user prompt keywords)
- Onboarding window, diagnostics export (redacted), self-updater (check +
  open Releases page; no auto-install while unsigned)

## 4. UI requirements

- Panel anchored to top-center (notch) when available, else menu-bar dropdown
- Each session card: agent icon (SF Symbols per agent), project name, elapsed
  time, current activity line, approval controls when pending
- Approvals never auto-dismiss; decisions are explicit user actions
- Sound: none by default; user opts in per event type
- All copy original, English primary; `zh-Hans` secondary via String catalogs

## 5. Privacy guarantees (must be enforced & documented)

- No network calls except: LiteLLM pricing refresh (opt-in), user-configured
  push (Bark-style, off), usage APIs the user explicitly enables (their own
  credentials, direct to vendor)
- Diagnostics export must redact api keys, tokens, license-like strings
- Socket directory permissions 0700; ingress validates event evidence

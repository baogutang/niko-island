# Changelog

## [0.1.0] - 2026-10-12

First public release.

### What works
- Menu-bar app with a floating panel: one card per running agent session,
  showing what it is doing right now.
- Claude Code integration end to end: hooks for every lifecycle event, a
  status-line wrapper that keeps your existing status line, permission
  requests and questions answered from the panel.
- Approvals: allow once, always allow a tool for the session, allow all for
  the session, deny, or hand the decision back to the terminal. A pending
  request stays until you decide or the agent withdraws it.
- Local notifications with click-to-jump back to the terminal tab
  (Terminal.app, iTerm2, tmux aware).
- Installer that scans first, backs up, verifies and rolls back; `uninstall`
  removes only its own entries.
- Usage tab: tokens and estimated cost per model for today and the last seven
  days, read from transcripts on your Mac; Claude rate limits from the status
  line.
- English and Simplified Chinese.

### Experimental (opt-in, not validated against live agents)
- Adapters for Codex CLI, Cursor CLI, Copilot CLI, Gemini CLI, Grok CLI, Trae,
  Windsurf, Qwen, Kiro, Factory and the OpenCode family. They register status
  events only; approvals from the panel are Claude Code only in this release.

### Known limitations
- Ad-hoc signed, not notarized: clear the quarantine flag once with
  `xattr -cr "/Applications/Niko Island.app"` (on macOS 15+ the alternative is
  System Settings → Privacy & Security → Open Anyway).
- The end-to-end tests drive the app with a simulated agent that follows
  Claude Code's documented hook contract. A live session, notification
  click-through and the notch layout still need hands-on confirmation.
- The Intel slice is verified under Rosetta, not on Intel hardware.
- See the README section "What was and was not verified" and `docs/ROADMAP.md`.

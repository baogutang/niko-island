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
  request never resolves on its own.
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
- Ad-hoc signed, not notarized: macOS asks you to confirm the first launch.
- The notch layout has not been checked on a notched display yet.
- The Intel slice is verified under Rosetta, not on Intel hardware.
- See `HANDOFF.md` and `docs/ROADMAP.md` for the full list.

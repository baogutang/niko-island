# Roadmap

What is in 0.1.0, what is deliberately left out, and what comes next.
"Planned" means not implemented: nothing below the first section ships today.

## In 0.1.0

| Area | State |
|---|---|
| Claude Code hooks, status line, approvals, questions | Works, covered by end-to-end tests |
| Panel, notifications, jump back to Terminal.app / iTerm2 / tmux | Works; jump-back and the notch layout need hands-on checks (see `TESTPLAN.md`) |
| Installer with scan, backup, verify, rollback, uninstall | Works, covered by fixture tests |
| Usage from local transcripts, cost estimates, Claude rate limits | Works for Claude Code and Codex; OpenCode-family parsing is best effort |
| Other agents (Codex, Cursor, Copilot, Gemini, Grok, Trae, Windsurf, Qwen, Kiro, Factory, OpenCode, MiMoCode) | Experimental, opt-in, status events only |

## Next

1. **Validate the experimental adapters against live agents**, one at a time,
   and promote the ones that hold up to the default install. Until an agent's
   hook format is confirmed, its adapter stays opt-in.
2. **Approvals for more agents.** Each agent has its own decision contract;
   they are added only after being verified.
3. **Notarized builds** if the project gets a signing identity. Until then
   releases stay ad-hoc signed.
4. **Notch polish**: hover-to-open and a compact idle state on notched displays.
5. **Onboarding window** for first launch (today the empty state and the
   Settings tab do this job).

## Planned, not started

- Adapters for Kimi Code, DeepSeek CLI, Droid, Pi / OhMyPi, OpenClaw, Amp.
- Usage numbers from vendors' own APIs, with the user's own credentials, sent
  directly to the vendor and only when switched on.
- Push to a phone through a user-configured relay (off by default).
- Monitoring agents on remote machines over SSH.
- Sound packs, and sounds that respect Focus modes.
- Opening a new terminal window to re-attach a detached tmux session.
- An in-app "new version available" check. It needs a network request that is
  not on the privacy allow-list today, so for now there is only a menu item
  that opens the Releases page.

## Not planned

- Accounts, license keys, analytics, crash reporting to a server.
- Anything that proxies or stores your agent credentials.

# Roadmap

What is in the code today, what is deliberately left out, and what comes next.
"Planned" means not implemented: nothing below the first two sections ships
today.

## Released: 0.1.0

| Area | State |
|---|---|
| Claude Code hooks, status line, approvals, questions | Works, covered by end-to-end tests |
| Menu-bar panel, notifications, jump back to Terminal.app / iTerm2 / tmux | Works; jump-back needs hands-on checks (see `TESTPLAN.md`) |
| Installer with scan, backup, verify, rollback, uninstall | Works, covered by fixture tests |
| Usage from local transcripts, cost estimates, Claude rate limits | Works for Claude Code and Codex; OpenCode-family parsing is best effort |
| Other agents (Codex, Cursor, Copilot, Gemini, Grok, Trae, Windsurf, Qwen, Kiro, Factory, OpenCode, MiMoCode) | Experimental, opt-in, status events only |

## Released: 0.2.0

| Area | State |
|---|---|
| The island: a tab at the top centre of the screen that opens on hover, on click and for a decision | Built and covered by model and layout tests; the window was launched and measured by script. Hover, click-outside and the animations have not been tried by hand |
| Flat session rows, pixel creatures per agent, chips for time, agent and terminal | Built; judged from rendered images |
| Permission and question forms on the island | Built; same decision logic and tests as 0.1.0 |
| Settings window (General, Island, Agents, Sounds, Usage, About) | Built; judged from rendered images |
| Sounds: five moments, two generated sets, macOS sounds, user files, sound packs | Built and tested for format, selection and fallback. Nobody has listened to the generated sets yet |
| Claude Code `StopFailure` hook | Wired; covered by installer and store tests |
| Disk image (`.dmg`) next to the zip | Built and checked by the release workflow: it mounts, and the app inside passes the signature check |

0.2.0 went out before sections 1 to 5 of `TESTPLAN.md` had been worked through
by a person. That is the first item below.

## Next

1. **Try the island by hand** (`TESTPLAN.md`), tune the timings and the sounds
   by ear, and replace the rendered pictures in the README with real captures.
2. **Check the layout on a display with a camera housing.** It has only been
   rendered, never seen on hardware.
3. **Validate the experimental adapters against live agents**, one at a time,
   and promote the ones that hold up to the default install. Until an agent's
   hook format is confirmed, its adapter stays opt-in.
4. **Approvals for more agents.** Each agent has its own decision contract;
   they are added only after being verified.
5. **Notarized builds** if the project gets a signing identity. Until then
   releases stay ad-hoc signed.
6. **Onboarding window** for first launch (today the empty state and
   Settings → Agents do this job).

## Planned, not started

- Adapters for Kimi Code, DeepSeek CLI, Droid, Pi / OhMyPi, OpenClaw, Amp.
- Choosing which display the island lives on.
- Sounds that respect Focus modes.
- Usage numbers from vendors' own APIs, with the user's own credentials, sent
  directly to the vendor and only when switched on.
- Push to a phone through a user-configured relay (off by default).
- Monitoring agents on remote machines over SSH.
- Opening a new terminal window to re-attach a detached tmux session.
- An in-app "new version available" check. It needs a network request that is
  not on the privacy allow-list today, so for now there is only a menu item
  that opens the Releases page.

## Not planned

- Accounts, license keys, analytics, crash reporting to a server.
- Anything that proxies or stores your agent credentials.

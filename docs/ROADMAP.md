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

0.2.0 went out before anyone had tried the island by hand. 0.3.0 is the answer
to what turned up when somebody did.

## Released: 0.3.0

| Area | State |
|---|---|
| Following the menu bar across desktops and full-screen apps | Built as two windows plus placement rules that are covered by tests. Checked by hand, frame by frame, on macOS 15 with one external display without a camera housing. Not tried: a MacBook's own display, two displays, a menu bar that hides on the desktop |
| Sessions from the agents' own session logs (Claude Code, Codex) | Built and covered by parser, scout and merge tests; seen working with the Claude and Codex desktop apps |
| Welcome on first launch, with agent detection and one-click connect | Built; looked at in the running app. Connecting from it uses the same installer as the command line |
| Adapters per agent format: Codex, ZCode, Cursor, Windsurf, Gemini CLI, Trae, Qwen Code, CodeBuddy, Factory, Grok CLI | Beta: each writes what the agent's own hook reference describes and is covered by installer and bridge tests. None has been driven against the live agent by us |
| Approvals for Codex and ZCode | Beta, same caveat |
| Usage per agent: five hours, today, seven days, a resettable counter; Codex limits; ZCode usage | Built and covered by tests; the view was looked at in the running app |
| Settings: look, timing, display, full-screen policy, session retention, language, global shortcut, creature per agent | Built; the pages were looked at in the running app, not every switch was flipped by hand |
| One package per architecture (Apple silicon, Intel) | Built and verified by `scripts/make-release.sh`; the Intel app has only run under Rosetta |

## Released: 0.4.0

| Area | State |
|---|---|
| ZCode sessions from its own database | Built and covered by tests on a database with the real tables; seen working with the ZCode desktop app, including a session that was open before ZCode was connected |
| Limits from local sources: Codex session files, Claude Code's status line, Claude Code's "limit reached" transcript entries | Built and covered by tests. The transcript entries were read from real files; the usage view was looked at in the running app |
| Asking the provider for limits (opt-in): Anthropic with Claude Code's sign-in, BigModel / Z.ai with a key the user pastes | Built and covered by tests with a stand-in for the network. Anthropic: the sign-in was found and correctly recognised as run out on the one machine tried, so no live answer has been read. BigModel / Z.ai: never run against the live service |
| "Reset in ZCode…" instead of a local counter | Built; the button was seen, not pressed |
| The welcome, laid out at the display's size, with a new entrance | Built; captured at the display's own resolution and recorded on one large display. Sharp there. Not every effect was watched (the confetti, creatures crossing) |
| Lighter, smaller type; text size; faster closing; motion speed | Built; looked at in the running app |

## Released: 0.5.0

| Area | State |
|---|---|
| A card when an agent finishes, with its last reply | Built and covered by tests of when it shows and when it does not. Driven through the real bridge on a real desktop and captured from the island's own window. No live agent was watched finishing a turn into it |
| Task progress on a row | Built and covered by tests. ZCode's todo table was checked against its real schema; Claude Code's and Codex's lists follow documented shapes and have not been seen from a live session |
| Git branch on a row, a chip for the model, one to three lines of the last reply | Built and covered by tests; branches of real repositories and worktrees were seen on the running island |
| Allow and deny from the keyboard (off by default) | Built and covered by tests; a request was allowed with ⌃⌥A and another denied with ⌃⌥D in the running app, through the real bridge |
| A reminder for a request left waiting; quiet while the screen is locked or asleep | Built and covered by tests with a stand-in clock. Not watched across a real lock or a real five minutes |
| A Codex desktop session opens on its own conversation | Built; the link has the form the Codex app itself uses. The click was not watched in Codex's window |
| Asking OpenAI for Codex limits and saved resets (opt-in) | Built, covered by tests, and answered live on the one machine tried |
| Asking Anthropic: per-model weekly windows, extra usage, a sign-in past its date offered once | Built and covered by tests with a stand-in for the network. Still no live answer read: the one sign-in tried was turned down |

## Next

1. **A live answer for the two remaining provider lookups.** Anthropic's with
   a current Claude Code sign-in, BigModel / Z.ai's with a real key. Until
   then both are written against documented formats only.
2. **Claude limits for people who only use the desktop app.** Today that needs
   a sign-in Claude Code has renewed in a terminal. Renewing it ourselves
   would mean acting as Claude Code and rewriting its Keychain entry, which
   can sign it out; that is a decision for the owner of the Mac, not a
   default. (The open-source tools that read this sign-in do not renew it
   either.)
3. **Watch a live agent through the new parts**: a turn finishing into a card
   with its own words, a real task list filling its bar, a real approval
   given from the keyboard.
4. **Drive the beta adapters against their live agents**, Codex and ZCode
   first (they can approve), and move the ones that hold up to stable.
   `TESTPLAN.md` section 10.
5. **Try the island on a MacBook's own display** and with two displays. The
   camera-housing layout has only been rendered, never seen on hardware.
6. **Listen to the built-in sounds** and tune them by ear.
7. **Group sessions** by project or by agent once there are many, and a
   shortcut that jumps to the session that needs you.
8. **Quiet hours** for sounds, beyond "quiet while the screen is locked".
9. **Answer from the card**: type a follow-up to a finished turn without
   leaving what you are doing. It needs a way into each agent's input that
   does not exist for most of them yet.
10. **Notarized builds** if the project gets a signing identity. Until then
    releases stay ad-hoc signed.

## Planned, not started

- Adapters for Kimi Code, Devin, Mistral Vibe, DeepSeek CLI, Pi / OhMyPi,
  OpenClaw, Amp. Several of these configure hooks in TOML, which the installer
  does not write yet.
- Themes beyond the accent colour.
- Sounds that respect Focus modes.
- Plan limits for more providers (Gemini, Kimi, MiniMax and others), asked
  the same way as the three there are: opt-in, the user's own sign-in or key,
  one host each.
- Push to a phone through a user-configured relay (off by default).
- Monitoring agents on remote machines over SSH.
- Opening a new terminal window to re-attach a detached tmux session.
- An in-app "new version available" check. It needs a network request that is
  not on the privacy allow-list today, so for now there is only a menu item
  that opens the Releases page.

## Not planned

- Accounts, license keys, analytics, crash reporting to a server.
- Anything that proxies or stores your agent credentials.

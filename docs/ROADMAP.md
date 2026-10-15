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

## Released: 0.6.0

| Area | State |
|---|---|
| The recap on return from a locked screen | Built and covered by tests; seen in the running app with a stand-in for the lock. A real lock was not tried |
| A line to a phone through Bark or ntfy (opt-in) | Built and covered by tests; both formats reached a stand-in server on the same Mac. Not sent through the real services |
| Quiet hours | Built and covered by tests with fixed times. Not watched across a real evening |
| The list by project or by agent | Built, covered by tests, seen in the running app |
| Reply from the island (experimental, opt-in) | Built with guards that are covered by tests. Never run against a real tmux, iTerm2 or Terminal |
| Claude Code's own cached limits as a source; parser fixes from the real answer shape | Built and covered by tests; the parser was run on the real cached answer of one machine |
| A real Claude Code turn through the card and the task bar | Done once, headless, with Claude Code 2.1.295 |

## Released: 0.7.0

| Area | State |
|---|---|
| Claude limits by letting Claude Code look (`claude -p /usage`, opt-in) | Built and covered by tests with a stand-in program; seen working in the running app on one Mac whose Claude Code is otherwise used through the desktop app |
| What an edit would change, shown in the request | Built and covered by tests for the shapes agents use (whole file, one replacement, several, a patch); seen in renders, and the path of a real request was seen on the island |
| Allow once / Deny on the notification banner | Built; the decision behind the buttons is tested, the banner was not clicked |
| ⌃⌥J to what needs you; a waiting request escalated to the phone | Built and covered by tests |
| How full the context is | Built and covered by tests; Codex's record was checked against a real file |
| A real approval from the island | Done once: interactive Claude Code 2.1.295 in a terminal of its own, answered with ⌃⌥A |

## Released: 0.8.0

| Area | State |
|---|---|
| A notice when a used-up limit resets | Built and covered by tests with a stand-in clock; a real window was not waited out |
| What a session has used, on its row | Built and covered by tests against the usage store |
| A line through the real ntfy service | Done once, on a random throwaway topic, read back from the service |
| ZCode limits without a key | Looked into: not possible with what ZCode offers today (no usage command in its CLI, nothing on disk) |

## Released: 0.9.0

| Area | State |
|---|---|
| Copilot CLI and Kiro in their own formats; Qoder, Qoder CN, QoderWork, Kimi Code (TOML), MiniMax Code (plugin pack), Devin (approvals), Amp (plugin) | Built against each agent's hook reference and the registrations CodeIsland ships; covered by tests, the Amp plugin run under Node against the real loopback ingress; not run against any of the live agents |
| Hooks that Devin and Copilot CLI borrow from Claude Code's settings | Told apart by the bridge's process ancestry; covered by tests with stand-in chains |
| Plan limits from Kimi, MiniMax and Google (Gemini CLI) | Built and covered by tests with recorded shapes and a stand-in network; never answered live (no keys or Gemini sign-in on the test Mac) |
| Themes: Classic, Glass, Pixel, Midnight | Built; seen in renders and in the running app |
| "There is a new version", and installing it | Built and covered by tests (parsing, checksums, a signed stand-in package, replacing into a scratch folder); the check and the download were run against the real GitHub release; replacing the app in /Applications was not |
| The first count of a large transcript collection | Peak memory of the counting process from 91 MB to 48 MB (resident 211 MB to 125 MB) and 30 s to 18 s on a few gigabytes of real transcripts |
| When each connected agent was last heard from | Built; shown in Settings → Agents |

## Released: 0.10.0

| Area | State |
|---|---|
| Pace, outlook and warnings for plan limits (ideas from agent-hud-open) | Built and covered by tests with stand-in readings; the outlook appears once the app has an hour of readings, the warnings were not waited for on a real plan |
| An unanswered request goes back to the agent after a while; one answered in the agent's own window leaves | Built and covered by tests with the real bridge binary |
| The last 24 hours, four weeks by weekday and hour, cache hits | Built; seen with real transcripts in a development build |
| Copilot's allowances | Built and covered by tests with a recorded shape; the endpoint was checked through `gh` (field names only), the app's own lookup was not run (it would read gh's Keychain item) |

## Released: 0.12.0

| Area | State |
|---|---|
| One signing certificate for every release, so macOS keeps granted permissions across updates | Built; the release workflow checks the designated requirement of both architectures against the pinned certificate. A real update on a Mac that had granted Automation has not been watched yet |
| Pinyin in quick search (whole and initials) | Built and covered by tests |

## Released: 0.11.0

| Area | State |
|---|---|
| Quick search, quiet-now links, hidden sessions and unread/context reminders | Built; parser/model coverage plus native field focus and IME/Return smoke |
| Restore hooks removed by another tool | Private-file installer/repair/backoff checks; standard runtime guard verified; actual agent configs untouched during acceptance |
| Configurable warning threshold, six monthly totals, self-hosted push authentication, WezTerm/kitty and custom links | Built and fixture-tested; live phone delivery and those terminal emulators remain unverified |
| Metal welcome and shared motion | Live 5120×2880 / 2× / 75 Hz presentation measured at 75.0 FPS; close releases the Metal view. 120 Hz and notch hardware still need a separate check |

## Next

Everything below needs something only the owner of a Mac can give, or hardware
that was not there.

1. **Run the reply against real terminals** (tmux, iTerm2, Terminal): it needs
   tmux installed, or the owner's consent for the app to control a terminal.
   Then take the "experimental" off, or take the feature out.
2. **A line arriving on a real phone** through Bark (the owner's device key).
3. **Click the banner's buttons**, and approve a request with Terminal.app,
   iTerm2 and the Claude desktop app in front.
4. **A live answer for the BigModel / Z.ai lookup** (the owner's key).
5. **Drive the beta adapters against their live agents.** `TESTPLAN.md`
   section 10.
6. **Try the island on a MacBook's own display** and with two displays.
7. **Listen to the built-in sounds** and tune them by ear.
8. **Notarized builds** if the project gets a signing identity.

## Planned, not started

- Adapters for Mistral Vibe, DeepSeek CLI, Pi / OhMyPi and OpenClaw.
- Kimi Code's older home (`~/.kimi`), for installations that have not moved.
- Automatic system Focus integration. Quiet-now URLs for owner-created Shortcuts automations ship in 0.11.0.
- Monitoring agents on remote machines over SSH.
- Opening a new terminal window to re-attach a detached tmux session.

## Not planned

- Accounts, license keys, analytics, crash reporting to a server.
- Anything that proxies or stores your agent credentials.

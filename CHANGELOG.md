# Changelog

## [0.15.2] - 2026-10-17

### Fixed
- **The island no longer keeps the processor busy following the menu bar.** It watched the menu bar at display rate (120 times a second, listing every window on screen each time) for as long as it rode a shown bar that might hide: in a full-screen app on a notched display, where the bar never hides, and on any desktop after one passing slide of the bar had been taken for "automatically hide". A 0.15.0 that had run for two hours used 15-20 % CPU, a fifth of its main thread's time in that one call. A bar at rest is now watched closely only while the pointer is near it, just after it leaves, and after a click.
- **The open island stays inside its window.** A request above seven or more sessions, or the 12-row setting, made it taller than its window (up to 1,265 of 760 points): 0.15.0 grew the window upwards, which is another way the island vanished, and 0.15.1 cut its bottom off. The request and the list now share the room there is; each scrolls inside beyond that.
- **Usage no longer flashes the island to full height as it opens.** 0.15.1 measured the page after laying it out, so its first frame was the whole window's height; it is now sized in the same pass.
- **Pets use far less memory.** Every frame of every mood was an image of its own, and Core Animation keeps a buffer per image: about 2,700 of them and 135 MB after a day. Each mood is now one strip of frames that the layer steps along, one image per loop.
- **Sessions found on disk are not parsed again while nothing changes.** Every 1.5 seconds the last 256 KB of each recent transcript was parsed again, and Claude Code's task files read again, changed or not. A reading now stands until the file changes or a moment passes that changes what it says (a quiet turn stops counting as running, a refused window reopens).

### Verification
- 455 local automated tests, 5 environment-dependent skips, no failures. New tests: the island laid out in a window of its real size with a request and the most rows (it used to end at 882-1,282 points, now within the window); Usage's first frame; a pet loop as one strip of drawn, moving frames; the menu-bar watch rule; a transcript not parsed again until it changes or a turning point passes.
- Release builds of 0.15.1 and of this code, side by side against throwaway homes with notifications on: 20 agents cycling through moods with the island open went from 195 MB to 147 MB (Core Animation 63 MB in 2,811 regions to 24 MB in 291; 2,749 images held to 229); CPU at rest the same (5.3 %); a full-screen window in front 5.7 % to 2.1 %. On the real island the pets move through their strips with clean edges, and the banner arrives.
- The signed nightly of this code (apple-silicon, 0.15.2-nightly.8666cb2), run with notifications on: a turn finished and its notification was posted; the app kept running, no crash report, 4.0 % CPU and 65 MB afterwards, both windows 780 × 760. The screen was locked during this run, so the banner itself was not seen. CI on `main` green.
- A test of Kiro's credits expected a turn from ten minutes ago under "today" and failed in the ten minutes after midnight (the first nightly ran at 00:06 UTC); it now runs at noon on a fixed calendar.

## [0.15.1] - 2026-10-16

### Fixed
- **The island no longer vanishes after the usage page has been open.** Since 0.14.0 the usage page (activity, then the top sessions) could be taller than the island's window. SwiftUI then grew the window to fit, upwards; the island hangs from the top of its window, so it went off the top of the screen and stayed there after the page was closed. The app was still running, but nothing of it could be seen, so it looked as if it had quit. The island's windows are now never resized by their content, and a page taller than the island scrolls inside it.

### Verification
- On the owner's Mac, the running 0.15.0 was found with its desktop window 856 points tall instead of 760, the island 96 points above the screen, the process healthy. A 0.15.1 build opened on the usage page with the same data keeps both windows at 780 × 760 and the island on screen, the page scrolling inside it.
- 450 local automated tests, 5 environment-dependent skips, no failures; CI on `main` green. The signed nightly of this code (apple-silicon): run with notifications on, banner delivered, no crash report; opened on the usage page with the owner's data, both windows 780 × 760, 0.8-2 % CPU.

## [0.15.0] - 2026-10-16

### Changed
- **Every agent's own pet.** The creatures drawn for 0.14.0 are gone: each agent now appears as its own mascot or mark, in pixels. Clawd for Claude Code is built from the glyph tables Claude Code draws him with (body rgb(215,119,87), terminal cells two pixels by four), and acts out moods with his own poses: walking at work, looking left and right while waiting, arms up when he needs you or a turn ends, eyes shut asleep. The others were pixelated from each vendor's official icon or logo: Kiro's ghost, the Codex cloud, the Cursor cube, ZCode's Z, OpenCode, Gemini's sparkle, Copilot's face, Qwen, Trae, Windsurf, the xAI mark for Grok, Factory, Devin, Amp, Kimi, MiniMax, Qoder, CodeBuddy's cat and MiMo. They hop, blink, and show a pixel "!", "…", sparkles, a drop of sweat or a "z". The marks belong to their owners and identify which agent a session is.
- **No grey halo around the open island.** Its wide soft shadow (34 pt, 32 %) is now a thin contact shadow.

### Added
- **Kiro's permission prompts reach the island.** Kiro asks in its own window and has no hook for it; it writes the prompt (`pending_interaction`, `tool_approval`) and the answer (`interaction_resolved`) to its session files, which the island now reads: the session shows "needs permission" with the tool, the island glows amber and opens (unless Kiro is in front), a banner and the attention sound follow, and it clears once answered in Kiro. Any agent whose request is read from disk now counts as needing you on the closed island.
- **Kiro's credits.** What each turn spent, from Kiro's own `usage_summary` records, as 5 hours, today, 7 and 30 days in Kiro's usage tab. With *Ask Kiro* on (off by default), this month's allowance, free-trial and bonus credits and the renewal date, asked of `management.<region>.kiro.dev` with the sign-in Kiro keeps (`~/.aws/sso/cache/kiro-auth-token.json`), only while it is still good, never renewed.
- **Top sessions of the week** in the usage view.
- Codex readings name their limit bucket in newer versions: the plan's own (`limit_id` "codex") is preferred.

### Fixed
- **The open island no longer keeps the processor busy.** The pulsing ring of a working row's status dot was a SwiftUI animation that never ended, and the verb of a working row shimmered every frame: SwiftUI drew the whole island again on every display frame while it was open (35 % CPU with three sessions at work). The ring is now a Core Animation layer and the shimmer is gone: 2.6-4.9 %.

### Verification
- 449 local automated tests, 5 environment-dependent skips, no failures; CI on `main` green.
- The signed nightly of this code (apple-silicon) run with notifications on against a throwaway home: three Claude Code turns, a Codex turn and a SessionEnd, banner delivered, still running, no crash report; 1.6-2.8 % CPU with an agent at work and the island closed.
- On this Mac: a real Kiro permission prompt (Kiro 1.3, open from 15:16:37 to 15:18:48) showed on the island as Kiro's ghost with the amber bell and glow, and went back to work when answered in Kiro. A live *Ask Kiro* lookup answered from `management.us-east-1.kiro.dev` (plan, 2 % of the month's credits). The open island's lower edge has no halo. The pets of real Claude Code, Kiro and ZCode sessions shown in the island.

## [0.14.0] - 2026-10-16

### Fixed
- **Claude Code on a Mac without it.** Cursor runs the hooks in `~/.claude/settings.json` by default ("third-party hooks"), so on a Mac where Claude Code had been connected but is not installed, Cursor's sessions appeared as Claude Code's. The bridge now tells who ran a Claude-format hook: the payload (`cursor_version`), the app bundle up the process chain, or a known agent's command; such an event is shown as that agent's, and dropped as a copy when that agent's own hooks of ours are in place. Claude Code itself is recognised however it was installed, including the native installer's binary that is named after its version.
- **A `~/.claude` folder is not Claude Code.** Skill installers and Cursor create one. Claude Code now counts as installed only with its command, `~/.claude.json`, its transcripts, its native install or the desktop app; connected agents that are not installed stay listed with a note so their hooks can be removed. `install --recommended` and `--all` skip them.
- The native Claude Code CLI counts as running (its process is named after its version).

### Added
- **Creatures with moods, drawn in vector.** Ten species redrawn with shading and faces, each with its own movement at work (the whale spouts, the jellyfish pulses, the crab snaps, the gull flaps, the puffer puffs up, the boat rocks on the swell). Moods follow the session: at work, asking for you (a hop and a "!"), pleased just after a turn (^ ^ and sparkles), waiting (looking up, a speech bubble), asleep after half an hour (z), failed (× eyes, a drop of sweat). Each creature blinks on its own clock. The Pixel style keeps the pixel sprites; the welcome's swimmers, the docs and the site use the new ones.
- **A glow around the closed island**: amber while someone waits on you, the accent while agents work, a flash when a turn ends; and a light running along its lower edge while agents work. Settings → Island can turn it off.
- Moving creatures and the edge light are played by Core Animation from frames drawn once per mood, so an island that moves all day costs the app next to nothing.
- **Motion in the list**: rows arrive one after another when the island opens, the status dot of a working or waiting row sends out a ring, and the verb of a working row shimmers.
- **Every agent's activity, half a year of it.** Counted from the hooks of every connected agent (sessions, prompts, tool calls and which tools), into `~/.niko-island/data/usage/activity.sqlite`; counts and tool names only. The usage view shows 26 weeks as a heatmap, the last week's totals, a streak, the busiest agents and the most used tools. Agents without a token log (Cursor, Gemini CLI, Kiro…) get a usage tab of their own.
- **Cursor's plan** (off until switched on): the included usage of the billing cycle, Auto and the named models apart, and on-demand spending, asked of `cursor.com` with the sign-in Cursor's app keeps (read-only from its settings database).

### Changed
- Provider lookups that have answered once are asked again only while their agent has been heard from in the last two hours (GLM, Kimi and MiniMax: any agent). "Check now" always asks.
- Token counts on the usage tiles and per model no longer include cache reads; they are shown apart ("+ 33.9M read from cache").
- The limits line at the top follows the agent picked in the usage view.

### Verification
- 442 local automated tests, 5 environment-dependent skips, no failures; CI on `main` green.
- The signed nightly of this code (apple-silicon) run with notifications on against a throwaway home: three Claude Code turns, a Codex turn and a SessionEnd, banners delivered, still running, no crash report. With agents working and the island closed it used 0.8-1.8 % CPU (the build before the Core Animation change used 11-13 %).
- On a real desktop: the closed island's edge light and glow, the request card with the asking creature, the moods of finished and working rows. A live Cursor lookup answered from `cursor.com` in the expected shape.
- Not checked: notch layouts of the glow on another Mac, 120 Hz, the Intel build beyond CI's launch under Rosetta, Cursor itself running Claude Code's hooks ("third-party hooks"): the attribution follows Cursor's documentation and its process tree.

## [0.13.0] - 2026-10-16

### Added
- **Plan limits along the top of the open island.** The agent at the top of the list shows its short and long windows (`Claude Code 5h 37% 2h24m │ 7d 61% 3d`), coloured calm, warm or hot, with the time to each reset. Click it for Usage. Settings → Island can turn it off.
- **Older quiet sessions on one line.** Sessions at work, waiting on a decision, changed in the last five minutes, or with a reply being typed keep their card; the rest fold to creature, project, headline and chips. Resting the pointer on a line for a moment opens its card. Settings → Island can turn it off.
- **Permissions, explained.** Settings → General opens with what macOS currently allows: notifications and control of each installed terminal (Terminal, iTerm2), read without ever prompting. A terminal that turns our Apple events down is now noticed (`-1743`) instead of silently bringing only the app forward: the first refusal opens System Settings → Privacy & Security → Automation with a guide docked beside it that watches until the switch is on; later ones say so on the island. "Allow…" asks macOS only while it has not asked yet.

### Changed
- The website's demo is a small story on an evening desktop: the agent edits, asks to run the tests, a pointer allows it on the island, the tests pass, and the list opens with the new limits line and one-line rows. The headline names a different agent with its creature every few seconds. Rendered docs pictures show the new layout, the permissions card and the guide.

### Verification
- 433 local automated tests, 5 environment-dependent skips, no failures.

## [0.12.0] - 2026-10-15

### Changed
- **Permissions survive updates.** Releases are signed with one fixed, self-signed certificate (`NIKO Code Signing`) instead of ad hoc. macOS records Automation and notification grants against the designated requirement, which now names that certificate rather than each build's hash, so an update no longer asks again. The first update from 0.11.0 or earlier asks once. Still not notarized: the project has no Apple Developer account.
- The release workflow refuses to publish a tag that is not signed with the pinned certificate (`scripts/signing-identity.sha1`), and checks the designated requirement of both architectures.

### Added
- **Quick search in pinyin.** Chinese project names, titles and prompts match by pinyin, whole or by initials (`fanyi` and `fy` both find 翻译), ranked just below a match on the characters themselves.

### Fixed
- The log names an agent with two config files once when bringing connected agents up to date (it said "kiro, kiro").

### Verification
- 423 local automated tests, 5 environment-dependent skips, no failures.

## [0.11.0] - 2026-10-15

### Added
- Quick session search with ⌃⌥S, fuzzy project/prompt/agent matching and keyboard selection. Pending requests open on the island.
- Quiet-now durations and `nikoisland://quiet` links for Shortcuts; keep the island closed over the agent's own window, hide session folders or prompt fragments, remind about unread finished turns and warn once near the context limit.
- Restore removed hooks only for previously connected agents, with a two-minute check, ten-minute repair backoff and an opt-out. Deliberate uninstall clears the remembered connection.
- Configurable plan warning level (70 / 80 / 90 / 95%, default 90%), six months of monthly usage, WezTerm / kitty pane jumps and custom app links.
- Basic / Bearer authentication for explicitly configured self-hosted Bark / ntfy servers.

### Changed
- Metal night-sea welcome, Core Animation creatures and confetti, shared transition curves, continuous island corners and list overscroll.
- Bursts of work-started events share a sound cue. READMEs and the bilingual website describe the new controls and use regenerated native view artwork.

### Fixed
- Huge quiet-duration inputs are clamped before integer conversion or multiplication.
- Session search leaves candidate navigation and Return to the input method until composition commits.

### Verification
- 422 local automated tests, 5 environment-dependent skips, no failures; private-file hook repair/backoff verification.
- Native search focus and IME/Return checks; notifications-enabled packaged-app smoke through three synthetic turns and SessionEnd.
- Actual Metal presentation on one 5K / 75 Hz display: 75.0 FPS over six seconds; rendering view released on close. This does not certify 120 Hz, notch layouts, physical Intel hardware, notification buttons or delivery to a phone.

## [0.10.0] - 2026-10-15

Ideas from agent-hud-open (Apache-2.0), rebuilt here in this project's own code.

### Added
- **A warning before a plan runs out.** Every reading of a plan's limits is
  kept (percentages and times only) to tell how fast it is being used: over
  the last hour of a five-hour window, the last day of a weekly one. The
  island says it once per cycle when a window crosses 90 %, or when, at the
  pace of late, it would run out before it resets; with a cue, and to your
  phone if that is on. Nothing is said about readings that were already there
  when the app started, or that are more than half an hour old.
- **The pace under each limit**: so many percent an hour, and either "runs
  out in about 1h 20m, before the reset" or "about 64 % by the reset", with
  the bar showing where the pace leads. Limits are coloured by how full they
  are: under 70 %, from 70 %, from 90 %.
- **A request you did not answer goes back to the agent** after 10 minutes
  (Settings → General; 1 to 60 minutes, or never), answered by nobody, so an
  agent is never stuck behind a card you did not see.
- **The last 24 hours in quarter hours, and four weeks by weekday and hour**,
  in the usage view, with the cache hit rate of the last seven days.
- **Copilot's monthly allowances** (premium requests, chat, completions),
  off until switched on, with the sign-in the GitHub CLI keeps, sent only to
  `api.github.com`.

### Fixed
- **A request answered in the agent's own dialog stays on the island.**
  Claude Code shows its own prompt next to the hook and, once it is answered
  there, leaves the hook waiting. The island now lets such a request go as
  soon as the session reports that very call (same tool, same input) as done,
  or its turn as over, and the hook ends without a decision.

## [0.9.1] - 2026-10-14

### Fixed
- **A session that has ended leaves the island.** A session that said
  goodbye came straight back from its transcript as "waiting for you" for
  up to half an hour; it now stays gone unless the transcript is written
  again (a resumed session comes back). A session whose agent exits without
  a word (the terminal closed, the agent killed, a desktop conversation
  closed) used to stay up to twelve hours; the bridge now tells the app which
  processes it ran under, and the row goes within seconds of the agent
  process exiting. A session found on disk that belongs to a desktop app
  goes when that app is quit.
- **Kiro was not recognised.** Kiro's desktop app (`dev.kiro.desktop`) now
  counts as Kiro running; only its command-line tool did before.
- **Agents connected by an earlier version keep working after an update.**
  0.9.0 moved Kiro's and Copilot CLI's hooks to new files, but an agent
  connected by 0.8 kept the old wiring until Connect was pressed again. The
  installed app now brings agents that carry our entries up to date once
  after an update (the same scan, backup and rollback; the status line is
  left alone).

### Added
- **Kiro sessions are listed without any hook**, from Kiro's own session
  folders (`~/.kiro/sessions/`, read-only): title, folder, last prompt and
  reply, and the tool at work. Only real work counts as activity, not the
  housekeeping Kiro writes when it opens a session.

## [0.9.0] - 2026-10-14

### Added
- **More agents, each in its own format.** Qoder, Qoder CN and QoderWork
  (Claude's format in their own settings), Kimi Code (one marked block of
  `[[hooks]]` tables at the end of `~/.kimi-code/config.toml`; a config that
  defines `hooks` some other way is left alone), Devin (approvals from the
  island, answered as `{"decision": "approve" | "block"}`), MiniMax Code (a
  plugin pack under `~/.minimax/plugins/niko/`) and Amp (a plugin that only
  listens). The formats follow each agent's hook reference and, where that is
  thin, the registrations CodeIsland ships.
- **A permission prompt that only an agent itself can answer** (Kimi Code,
  Qoder, MiniMax Code) shows on the island as "needs permission", without
  holding the agent up.
- **Plan limits from three more providers**, each off until switched on:
  Kimi and MiniMax with a key you paste in (kept in your Keychain), and
  Google for Gemini CLI's daily quotas, with the sign-in Gemini CLI saved and
  only while it has not run out: it is never renewed here.
- **Themes for the island:** Classic, Glass (the desktop blurred behind it),
  Pixel (square corners, monospaced type) and Midnight. On a display with a
  camera housing the closed island stays black.
- **"There is a new version", if you want it.** Once a day the app can ask
  GitHub for the latest release; the header shows a chip, and Settings →
  About can install it: the package for this Mac is downloaded, checked
  against the release's `SHA256SUMS`, its bundle id, version and signature,
  and only then does the old app go to the Trash and the new one start.
- **Settings → Agents says when each connected agent was last heard from**,
  so a hook that never fires is noticed.

### Changed
- **Copilot CLI** gets the file format its hook reference describes, with
  Claude's event names (which give Claude-shaped payloads); it is beta now.
- **Kiro** gets a global hook file in `~/.kiro/hooks/` (Kiro CLI 3 and the
  IDE); the entries earlier versions wrote into `~/.kiro/settings/cli.json`,
  which Kiro never ran, are taken out again.
- **Hooks that Devin and Copilot CLI borrow from Claude Code's settings** are
  shown as theirs, or dropped when their own hooks are connected, so a
  session is never listed twice or under the wrong agent.
- **The first count of a large set of transcripts** reads and commits in
  stretches: on a few gigabytes of real transcripts the counting process peaked
  at 48 MB instead of 91 MB (125 MB resident instead of 211 MB) and took
  18 s instead of 30 s.

### Fixed
- An event the island has no meaning for (a heartbeat, a helper starting, a
  failed tool) no longer replaces a row's activity with its raw name.
- The documentation pictures were drawn with the default look whatever the
  scene's settings said.

## [0.8.2] - 2026-10-14

After 0.8.0 quit at its first notification, the rest of the app was searched
for other ways it could stop itself.

### Fixed
- **A time that is not a time can no longer stop the app.** Numbers that
  other programs and providers write (reset times, sign-in expiry, Claude
  Code's cache date, ZCode's message times) were turned into dates as they
  came; a number such as `1e400` would have become a date at infinity, and
  the app would have stopped the moment it counted the minutes to it. Such
  numbers are now no date at all, the window is still shown without its reset
  time, and the views count minutes in a way that cannot trap.

### Checked
- Every closure the app hands to a system API was looked at for the 0.8.0
  mistake; only that one had it.
- Forced operations (`try!`, forced unwraps, `fatalError`) in what the app
  runs: none outside a deliberate fault injection in the bridge's test build.

## [0.8.1] - 2026-10-14

### Fixed
- **The app quit by itself at the first notification of a run.** macOS
  answers the "may this app show notifications" question on a queue of its
  own; the code that took the answer had been written inside a part of the
  app that may only run on the main thread, and Swift stops an app when such
  code runs anywhere else. Every launch therefore ended at the first banner
  (a permission request, a question, or a finished turn). The answer is now
  taken by code that may run on any thread, a test calls it the way macOS
  does, and a development build with notifications switched on was run
  through three rounds of sessions, requests, failures, shortcuts and a
  stand-in lock without stopping.

### How it was missed
- Every hands-on run of a development build had notifications switched off,
  so the one path that crashed was never taken outside the shipped app. The
  test plan now asks for one run with notifications on before a release.

## [0.8.0] - 2026-10-14

### Added
- **Told when a limit resets.** A window that is used up is remembered with
  the time it opens again. When it does, the island says so once ("Claude
  Code's limit has reset"), with the "finished" cue, and with a line to your
  phone if that is switched on. If you were away, it is said when you are
  back. With two windows used up, it waits for both.
- **What a session has used**, as a chip on its row (off by default): an
  estimate at list prices from the same records as the usage view, or the
  tokens where the model has no list price.

### Checked against the real thing
- **A line through the real ntfy service**: one fixed test line on a random
  throwaway topic, sent by the app's own code and read back from the service.

### Looked into, and not possible today
- **ZCode's limits without a key.** Claude Code can be asked to look up its
  own usage; ZCode cannot: its command-line program has no usage command, and
  its app fetches the figures itself without keeping them on disk. The lookup
  with a key you paste stays the only way.
- **Codex's plan from a real session**: none of the recent sessions on the
  machine the app is built on has written one, so `update_plan` is still read
  from its documented shape.

## [0.7.0] - 2026-10-14

Claude's limits for people who only use the desktop app, and the oldest
unverified promise checked for real.

### Added
- **Let Claude Code look up its own limits (off by default).** The app runs
  your own `claude` program with `/usage` every five minutes while a Claude
  Code session is listed. Claude Code asks Anthropic with its own sign-in, and
  renews it when it must, exactly as when you type `/usage`; the app reads the
  answer Claude Code keeps in `~/.claude.json`. No sign-in is read by Niko
  Island, nothing is saved as a session, your hooks and MCP servers are left
  out of that run, and it works for sessions in the desktop app. Settings →
  Usage.
- **See an edit before you allow it.** A request to write or change a file
  shows the first lines of what it would take out and put in, under the path.
- **Answer on the banner.** A permission request's notification carries
  *Allow once* and *Deny*.
- **⌃⌥J goes to what needs you** (off by default): the waiting request, else a
  session with a question, else the session that stopped last.
- **A request left waiting also goes to your phone** when a reminder is due
  and the phone is switched on, wherever you seem to be.
- **How full the context is**, as a chip: a percentage for Codex, which says
  how large its window is, a size for Claude Code, which does not. Shown on
  request, and by itself once a known window is nearly full.

### Checked against the real thing
- **A real approval, given from the island.** An interactive Claude Code
  session asked to write a file; the request appeared on the island with the
  path; ⌃⌥A was pressed; only then did the file exist.
- **Claude limits through Claude Code itself**, on a Mac whose Claude Code is
  otherwise only used through the desktop app: both windows, with reset times.
- What sits in the foreground of a terminal while Claude Code waits (its own
  binary and `caffeinate`), which is what the reply's guard looks for.
- Codex's `token_count` record, against a real session file.

### Known limitations
- The banner's buttons were not clicked; they call the same decision the
  island's buttons do, which is tested.
- The real approval ran in a terminal of its own, not with Terminal.app,
  iTerm2 or the desktop app in front.
- Replying from the island and a line through the real Bark or ntfy service
  are still unrun against the real thing.

## [0.6.0] - 2026-10-13

The rest of the list, and what running a real agent through it showed.

### Added
- **Back at the screen.** What finished while the screen was locked or asleep
  is said once when you return: one card, a line per session, each a way to
  that session. Nothing is said to an empty room and nothing is lost.
- **A line to your phone (off by default).** Through a push service you set up
  yourself, Bark or ntfy, on their servers or on one of yours. A line names the
  agent, the project and the kind of moment; the command being asked for, or
  the first line of a reply, goes along only if you switch that on. By default
  lines go out only while the screen is locked or asleep. Settings → General.
- **Quiet hours.** A stretch of the day, over midnight if you like, in which
  nothing makes a sound and nothing is sent to a phone.
- **The list by project or by agent**, under a heading each. Settings →
  Sessions.
- **Reply from the island (experimental, off by default).** A session that has
  stopped gets a line to type a follow-up into; it is sent into the tmux pane,
  iTerm2 session or Terminal tab the agent runs in, as if typed there, and
  only after checking that the agent, not a shell, is waiting at that prompt.
  Sessions in a desktop app have no such way in.
- A row's menu: copy the last reply, show the folder in Finder, copy the
  command that resumes the session.
- **Claude Code's own cached limits** are a source too: the last answer Claude
  Code fetched for itself and kept in `~/.claude.json`, shown with its age for
  as long as its windows have not reset. No sign-in is read for it.

### Changed
- **Claude Code's task tools show as planning.** Current Claude Code keeps its
  list with `TaskCreate` and `TaskUpdate` instead of `TodoWrite`; rows now say
  "planning" with the step's name instead of "working TaskCreate".
- **Asking Anthropic** no longer shows windows that the answer carries under
  code names, reads the weekly entry of the newer list form (`weekly_all`),
  and no longer drops a limit because it is not the one that bites right now.

### Checked against the real thing
- **A real Claude Code turn.** Claude Code 2.1.295 was run once, headless, with
  a temporary hook file pointing at a development build. Its `Stop` event
  carries the closing words (`last_assistant_message`); its tasks are one file
  each under `~/.claude/tasks/<session id>/`; the card came down with the
  agent's own sentence and its list at 1 of 3.
- **The shape of Anthropic's answer** as Claude Code itself keeps it on disk,
  which is where the three parser changes above come from.
- **Both push formats** against a stand-in server on the same Mac.

### Known limitations
- **Replying has never been run against a real terminal.** The machine it was
  built on has no tmux, and controlling Terminal or iTerm2 needs a consent
  only the Mac's owner can give. What is covered by tests: which terminals
  qualify, what has to be at the prompt, and how the text is quoted.
- **No line has gone through the real Bark or ntfy service.**
- **Claude limits for desktop-only use** still need a current Claude Code
  sign-in. Reading it may make macOS ask for access to the Keychain item each
  time Claude Code has replaced it.

## [0.5.0] - 2026-10-13

The things 0.4.0 had put on the roadmap, built; and what two open-source
projects taught about asking a provider for limits.

### Added
- **A card when an agent finishes.** Instead of a one-line notice, a card
  comes down from the island with what the agent said last, its bold, code and
  links drawn as such, and a bar for its list of steps if it kept one. A click
  goes to the session, the ✕ puts the card away, and it stays while the
  pointer is on it. It opens nothing and never takes keyboard focus. It is not
  shown when the island is open, when a request is waiting, or when the
  session's own window is already in front. Settings → Island → *When an agent
  finishes*: card, notice, or nothing.
- **Task progress.** A thin bar and the step in hand on the row of an agent
  that keeps a list of steps: Claude Code's `TodoWrite` and task files, Codex's
  `update_plan`, ZCode's todo table.
- **The git branch** next to the project's name, read from `.git/HEAD`
  (worktrees included) without running git. A chip for the **model**, off by
  default.
- **Allow and deny from the keyboard**: ⌃⌥A and ⌃⌥D for the request the island
  is showing. Off by default. The keys are claimed only while a request is
  waiting; with the island closed the first press only opens it; a question is
  never answered this way.
- **A reminder for a request left waiting** (off by default): the cue plays
  again after 2, 5 or 10 minutes, up to three times.
- **Quiet while nobody is there**: no sounds and no cards while the screen is
  locked or asleep (on by default). Requests still wait.
- **One to three lines of the last reply** on a row, or none.
- **A Codex desktop session opens on its own conversation** when its row is
  clicked, through the link the Codex app itself uses.
- **Ask OpenAI for Codex limits (off by default).** A third switch in
  Settings → Usage. Codex's own files already say most of it; this adds a
  current figure while Codex is idle and **how many resets a ChatGPT plan has
  saved**. It reads the sign-in Codex keeps on this Mac and talks to
  chatgpt.com only.

### Changed
- **Asking Anthropic** now also reads each model's own weekly window and paid
  extra usage, where the plan has them. A sign-in whose date has passed is
  offered once rather than not at all (the date is Claude Code's note to
  itself, the answer is Anthropic's), and a sign-in that was turned down is
  not offered again until Claude Code has replaced it.
- **The Coding Plan lookup** recognises the weekly window by its unit, whatever
  count comes with it, and no longer needs a unit at all to tell two windows
  apart.
- A reply belongs to its turn: what an agent said before your newest prompt is
  no longer shown as its last word while it works on the new one.
- The branch of a new session's folder is looked up at once, not at the next
  tick.

### Fixed
- **Codex sessions named after their wrapping.** A prompt sent with files was
  listed as "# Files mentioned by the user:", and project instructions as
  "# AGENTS.md instructions for …". The row now shows what was actually typed.
- A "finished" notice stayed on the island after its session had started
  working again.

### Known limitations
- **No live agent was watched finishing a turn into a card.** The card was
  driven through the real bridge with events in the documented format, and
  from transcripts in tests.
- **Task lists of Claude Code and Codex are read from documented shapes.** No
  session on the machine the app is built on had written one. ZCode's table
  was checked against its real schema.
- **Claude limits still need a current Claude Code sign-in**, which the desktop
  app alone does not keep current. On the one machine tried, Anthropic turned
  the old sign-in down.
- **How many ZCode reset cards are left** is still known only to ZCode's
  account service. The open-source tools looked at do not get it either.

## [0.4.0] - 2026-10-13

What turned up when 0.3.0 was used for an afternoon.

### Fixed
- **ZCode sessions were missing.** ZCode takes its hooks when a session
  starts, so a session that was already open never spoke to the island, and
  nothing else was looking. ZCode sessions are now read from ZCode's own
  session database, the way Claude Code and Codex sessions are read from
  their logs: the title, what it is doing, the last reply, helper agents, and
  whether it lives in the desktop app.
- **The welcome was soft on large displays.** It was laid out for a small
  screen and magnified. It is now laid out at the size of the display it is
  on, so type and creatures are drawn sharp.
- **A whale swam backwards** in the welcome. Creatures now face the way they
  are going.
- The "Reset" button in the usage view did not do what its name said: it only
  started a local counter. It is gone. See *Limits* below for what a reset
  really is.
- A model without a list price (GLM on a Coding Plan, for one) showed as
  "$0.00". It now shows its tokens.

### Added
- **Limits, from whoever knows them.** For each agent the usage view shows
  the plan's windows (five hours, weekly) with the time they reset:
  - Codex: from its session files, as before.
  - Claude Code: from its status line; and when Claude Code is turned away
    because a window is full, that is read from its transcript, so "limit
    reached, resets in 1 h 20 min" shows even for the desktop app.
  - **Ask the provider (off by default).** Two switches in Settings → Usage.
    *Anthropic*: reads the sign-in Claude Code keeps in your Keychain and asks
    api.anthropic.com. *BigModel / Z.ai* (the GLM Coding Plan that ZCode draws
    on): asks with a key you paste in, which is kept in your Keychain. Each
    talks to one host only; percentages and reset times are all that is kept.
- **"Reset in ZCode…"** A quota reset is something ZCode's own app spends
  (its reset cards). The usage view offers a button that brings ZCode forward
  for agents that have such a thing, and never spends one itself.
- A **30-day** figure next to five hours, today and seven days.
- **Text size** (small, regular, large) and **how fast the island opens and
  closes** (calm, standard, brisk) in Settings → Island.
- The welcome's entrance: an aurora, a ripple running out from the island as
  it lands, the name arriving letter by letter, stars and water that react to
  the pointer, and confetti when agents are connected.

### Changed
- Type inside the island is lighter and a little smaller.
- The island closes sooner after the pointer leaves (150 ms instead of 450),
  and closing is quicker than opening.

### Known limitations
- **Claude limits for desktop-only use.** Asking Anthropic needs a current
  Claude Code sign-in. Claude Code renews it when it runs in a terminal; the
  desktop app does not. With a sign-in that has run out, the usage view says
  so and shows only what the transcripts tell (a window that is full). Niko
  Island does not renew or rewrite Claude Code's sign-in.
- **The Coding Plan lookup has not been run against the live service.** It
  follows the answer format that several open-source tools document, and is
  covered by tests built on that format. ZCode keeps its own key encrypted, so
  the key has to come from you.
- **How many reset cards are left** is known only to ZCode's account service
  and is not shown.
- The limitations listed for 0.3.0 still apply: one display setup tried by
  hand, beta adapters not driven against their live agents, Intel build run
  under Rosetta only, ad-hoc signed.

## [0.3.0] - 2026-10-13

The island learns to follow the menu bar, finds sessions on its own, and
gets a welcome, a lot more settings and usage per agent.

### Fixed
- **The island stayed on screen over full-screen apps, and blinked when you
  came back.** It is now two windows: one that belongs to your desktops and
  slides away with them, and one that belongs to full-screen apps and comes
  down together with the menu bar when you push the pointer to the top of the
  screen. Nothing pops in after the slide has finished.
- **"No agents running" while agents were running.** A session used to exist
  only after one of its hooks had fired, so sessions in the Claude and Codex
  desktop apps, and anything started before the app, were invisible. See
  *Sessions without hooks* below.
- A phantom agent called "startup" could appear: the session-start payload of
  some agents has a field named `source`, which was mistaken for the agent's
  name.
- Codex, Cursor, Windsurf, Gemini CLI and Trae were wired with the wrong
  config shape. Each now gets the format its own hook reference describes.

### Added
- **Sessions without hooks.** The app reads the session logs Claude Code and
  Codex keep on disk, so their sessions are listed whether or not the agent is
  connected: what the session is called, what it is doing, the last reply, and
  Codex helper agents. These rows can be watched and jumped to; approving from
  the island still needs the agent to be connected. Can be switched off.
- **A welcome on first launch**: a full-screen introduction that finds the
  agents on your Mac, shows which are running, and connects the ones you tick.
- **ZCode**, and approvals for Codex and ZCode (beta). CodeBuddy, Factory,
  Grok CLI, Qwen Code and Trae moved from experimental to beta.
- **Running agents are detected.** If an agent's app or CLI is running but not
  connected, the empty island and Settings → Agents say so, with one
  **Connect all** button.
- **Usage per agent**: switch between all agents, Claude Code, Codex and
  ZCode. Each shows the last five hours, today, seven days, and a counter you
  can reset with a button. Codex limits (five-hour and weekly) are read from
  its own session files; ZCode usage from its own database, read-only.
- **Settings**: accent colour, island width, row density, how many sessions
  before the list scrolls, which chips a row shows, creatures on or off and
  which creature each agent gets, which display the island lives on, hover
  delays, how long the "finished" notice stays, what to do over full-screen
  apps, how long a quiet session stays listed, language (English / 简体中文 /
  same as macOS), and a global shortcut (⌃⌥I) that opens the island.
- `niko-island install --recommended` connects every detected agent with a
  stable or beta adapter.
- A Codex or ZCode row says what the agent still needs from you (Codex asks
  you to trust new hooks with `/hooks`).

### Changed
- **Downloads are per architecture**: `apple-silicon` for M-series Macs,
  `intel` for Intel Macs, each as `.dmg` and `.zip`. There is no universal
  build any more; each app is about half the size.
- A row found in a desktop app says "Desktop" instead of repeating the
  agent's name, and clicking it brings that app forward.

### Known limitations
- The menu-bar following was worked out and checked on one setup: macOS 15
  with an external display that has no camera housing. A MacBook's built-in
  display, two displays at once, and a menu bar set to hide on the desktop
  have not been tried.
- Beta adapters follow each agent's published hook reference and the config
  files found on a real machine, and are covered by tests. Apart from Claude
  Code, none has been driven end to end against the live agent by us.
- The Intel build has only been run under Rosetta.
- Still ad-hoc signed, not notarized: clear the quarantine flag once with
  `xattr -cr "/Applications/Niko Island.app"`.

## [0.2.0] - 2026-10-13

The island redesign.

### Changed
- The floating panel is replaced by an island that hangs from the top centre
  of the screen, above the menu bar: a small tab while agents work, a wider
  panel when opened. It opens on hover, on click, and by itself when an agent
  needs a decision. A click elsewhere puts it away and never decides a pending
  request.
- Sessions are flat rows: a pixel creature per agent, the project and your
  prompt, what the agent is doing, and chips for elapsed time, agent and the
  terminal that hosts it.
- Permission requests and questions open at the top of the island. Question
  options are tiles in two columns, with a field for typing something else.
- Settings moved into their own window: General, Island, Agents, Sounds,
  Usage, About.
- New app icon.

### Added
- Sounds for five moments: work started, needs you, finished, hit an error,
  limit close. A master switch (off by default), a volume control and a
  preview button per moment. The sound can come from two sets generated by the
  app (Island, 8-bit), a macOS system sound, your own files in
  `~/.niko-island/sounds/`, or a pack folder with an `openpeon.json` manifest.
- Pixel creatures for each agent, drawn in code.
- A short "finished" notice on the collapsed island.
- Claude Code's `StopFailure` hook, so a turn that ends in an error is shown
  as one. Run `niko-island install` again to add it to an existing setup.
- A cue when a Claude rate-limit window passes 90%.
- Island options: open on hover, open for a decision, the finished notice,
  stay visible while nothing is running.
- Releases now carry a disk image (`.dmg`) next to the zip. Both hold the same
  universal, ad-hoc signed app.

### Removed
- The 0.1.0 panel and its tabs. The three per-event sound checkboxes became
  the Sounds page; their values are carried over.

### Known limitations
- This release went out before anyone had worked through the hands-on
  checklist: hover, click-outside and the animations have not been tried by
  hand, nobody has listened to the built-in sounds, and the layout for a
  display with a camera housing exists only as renders. See "What was and was
  not verified" in the README, and please report what you find.
- Still ad-hoc signed, not notarized: clear the quarantine flag once with
  `xattr -cr "/Applications/Niko Island.app"`.

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

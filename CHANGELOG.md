# Changelog

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

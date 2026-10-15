<h1 align="center">
  <img src="docs/images/icon.png" width="64" height="64" alt="Niko Island app icon" valign="middle">&nbsp;
  Niko Island
</h1>
<p align="center">
  <b>An island at the top of your screen for the AI agents that write your code.</b><br>
  <a href="https://baogutang.github.io/niko-island/">Website</a> •
  <a href="#see-it-move">Demo</a> •
  <a href="#install">Install</a> •
  <a href="#features">Features</a> •
  <a href="#supported-agents">Agents</a> •
  <a href="#sounds">Sounds</a> •
  <a href="#privacy">Privacy</a> •
  <a href="#build-from-source">Build</a><br>
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/baogutang/niko-island/releases/latest"><img src="https://img.shields.io/github/v/release/baogutang/niko-island?display_name=tag&style=flat-square" alt="Latest release"></a>
  <a href="https://github.com/baogutang/niko-island/releases"><img src="https://img.shields.io/github/downloads/baogutang/niko-island/total?style=flat-square" alt="Release downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/telemetry-none-111827?style=flat-square" alt="No telemetry">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square" alt="MIT license"></a>
  <a href="https://github.com/baogutang/niko-island/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/baogutang/niko-island/ci.yml?branch=main&style=flat-square&label=tests" alt="Tests"></a>
</p>

<p align="center">
  <img src="docs/images/island-sessions.png" width="760" alt="The island open on six sessions: each row has a pixel creature, the project and what the session is about, what the agent is doing, and chips for elapsed time, agent and the terminal or app it runs in">
</p>

<p align="center">
  <sub>See every session at a glance, approve or answer from where you are, and jump back to the right window when you want to.</sub>
</p>

<p align="center">
  <img src="docs/images/mascots/starfish.gif" width="40" alt="Starfish" title="Claude Code · MiniMax Code">&nbsp;
  <img src="docs/images/mascots/whale.gif" width="40" alt="Whale" title="Codex · Kimi Code">&nbsp;
  <img src="docs/images/mascots/crab.gif" width="40" alt="Crab" title="ZCode · Devin">&nbsp;
  <img src="docs/images/mascots/boat.gif" width="40" alt="Boat" title="Cursor · Windsurf">&nbsp;
  <img src="docs/images/mascots/gull.gif" width="40" alt="Gull" title="Copilot CLI · CodeBuddy">&nbsp;
  <img src="docs/images/mascots/jellyfish.gif" width="40" alt="Jellyfish" title="Gemini CLI · Qwen Code">&nbsp;
  <img src="docs/images/mascots/turtle.gif" width="40" alt="Turtle" title="OpenCode · MiMoCode · Qoder">&nbsp;
  <img src="docs/images/mascots/octopus.gif" width="40" alt="Octopus" title="Trae · Kiro">&nbsp;
  <img src="docs/images/mascots/puffer.gif" width="40" alt="Pufferfish" title="Grok CLI · Factory · Amp">&nbsp;
  <img src="docs/images/mascots/island.gif" width="40" alt="Island" title="Everything else">
</p>
<p align="center">
  <sub>Claude Code · Codex · ZCode · Cursor · Windsurf · Gemini CLI · Trae · Qwen Code · CodeBuddy · Factory · Grok CLI · OpenCode · MiMoCode · Copilot CLI · Qoder · Kimi Code · Devin · Kiro · MiniMax Code · Amp</sub>
</p>

<a id="see-it-move"></a>
## See it move

Idle, working, asking for permission, asking a question, the full list, usage, done.

<p align="center">
  <img src="docs/images/island-demo.gif" width="720" alt="The island moving through its states">
</p>

On a display without a camera housing the island is a small tab on the menu bar instead:

<p align="center">
  <img src="docs/images/plain/island-working.png" width="400" alt="Collapsed island on a display without a notch: a creature and the words running swift test">
  <img src="docs/images/plain/island-attention.png" width="400" alt="Collapsed island saying a session needs you, with a bell">
</p>

<sub>Every image on this page is rendered by the app's own view code with sample sessions (`scripts/make-assets.sh`). They are renders, not captures of somebody's desktop.</sub>

<a id="install"></a>
## Install

### Download a release

1. Get the `.dmg` for your Mac from [Releases](https://github.com/baogutang/niko-island/releases/latest), open it and drag **Niko Island** onto **Applications**.

   | Your Mac | Download |
   |---|---|
   | Apple silicon (M1 and later) | `Niko-Island-<version>-apple-silicon.dmg` |
   | Intel | `Niko-Island-<version>-intel.dmg` |

   Not sure which? Apple menu → **About This Mac**: "Chip: Apple M…" is Apple silicon, "Processor: … Intel …" is Intel. Each build is also there as a `.zip`. There is no universal build.
2. Clear the download quarantine. The app is signed with the project's own NIKO certificate but not notarized by Apple (the project has no Apple Developer account), so macOS will not open a downloaded copy straight away:

   ```bash
   xattr -cr "/Applications/Niko Island.app"
   open "/Applications/Niko Island.app"
   ```

   No terminal at hand? On macOS 14, right-click the app → **Open** → **Open**. On macOS 15 or later, try to open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. The `xattr` command is the reliable route because it also clears the flag on the small helper that agent hooks run; if that flag is still set, **Settings → Agents** says so.

   Since 0.12.0 every release carries the same certificate, so macOS keeps the permissions you granted (Automation for jumping back to a terminal tab, notifications) across updates. Coming from 0.11.0 or earlier, it asks once more.

3. Open it. The first launch greets you with a full-screen welcome that finds the agents on your Mac, shows which ones are running, and connects the ones you tick.

   <p align="center">
     <img src="docs/images/island-onboarding-agents.png" width="720" alt="The welcome screen listing the agents found on this Mac, each with a tick box, and a Connect button">
   </p>

   Prefer the terminal? Look at the plan first, then apply it:

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run --recommended
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --recommended
   ```

   Plain `install` connects Claude Code only. Later on: the gear on the island → **Agents** → **Connect**.

Claude Code and Codex sessions show up as soon as the app runs, connected or not, because the app reads the session logs those agents keep on disk. Connecting adds live status from hooks and lets you approve from the island. After connecting, `~/.niko-island/bin/niko-island` is a shortcut to the same command line.

<a id="build-from-source"></a>
### Build from source

Requires macOS 14+ and Xcode 16 or later (Swift 6).

```bash
git clone https://github.com/baogutang/niko-island.git
cd niko-island
scripts/check.sh              # the whole test suite
scripts/make-app.sh           # → dist/Niko Island.app for this Mac, ad-hoc signed (NIKO_SIGN_IDENTITY signs it for real)
scripts/smoke-launch.sh       # launches it against a throwaway directory
open "dist/Niko Island.app"
scripts/make-release.sh       # what a release ships: apple-silicon and intel, .dmg and .zip
```

## What is Niko Island?

Coding agents spend most of their time working and a little of it waiting for you: a command to approve, a question to answer, a turn that has finished. Those moments are easy to miss when the agent lives in a terminal tab or an app window behind three others.

Niko Island keeps a small black island at the top of the screen, growing out of the camera housing on a MacBook and sitting on the menu bar anywhere else. It stays small while agents work, opens when one needs you, and lets you act right there. It behaves like a piece of the menu bar: where the menu bar goes, it goes.

<a id="features"></a>
## Features

**0.12.0: permissions that survive updates, search in pinyin.** Releases are signed with one fixed certificate, so an update no longer makes macOS ask again for what you already allowed. The quick switcher finds Chinese projects and prompts by pinyin, whole or by initials: `fanyi` or `fy` both find 翻译.

**0.11.0: quieter, with a faster way back.** Press ⌃⌥S, type a project, prompt or agent, move with ↑↓ and press Return. A session with a pending request opens that card instead. Input-method candidate selection keeps its own Return key.

<p align="center">
  <img src="docs/images/island-quick-switcher.png" width="616" alt="Quick search across projects, prompts and agents, with arrow-key and Return navigation">
</p>
The search picture is a capture of its native window with sample sessions. Other artwork is generated by `scripts/make-assets.sh`.


- **Quiet now.** Choose a duration in the menu or Settings. A Shortcuts automation can open `nikoisland://quiet?minutes=60`, then `nikoisland://quiet/off` to stop. This does not read system Focus modes automatically. Sounds, automatic cards and phone pushes pause; requests still wait for you. By default the island also stays closed when the agent's own window is in front.
- **Keep the sessions you want.** Settings → Sessions can hide folders (including children) or prompt fragments. Unread finished turns can join the reminders, and a nearly full context gets one warning.
- **Keep connected agents connected.** Every two minutes, the installed app checks for hooks removed by another tool and restores only agents you previously connected, at most once per agent every ten minutes, with a notice. Switch this off in Settings → Agents. Deliberately uninstalled agents stay disconnected.
- **More usage and jump controls.** Six months of monthly totals; a warning threshold of 70 / 80 / 90 / 95%, default 90%. WezTerm and kitty use the session's pane identifiers; kitty needs local remote control enabled. Custom app links live in Settings → Sessions.
- **Your own push server.** Self-hosted Bark / ntfy accepts Basic or Bearer authentication, kept in Keychain and sent only to the self-hosted address you configured.
- **A new welcome.** Metal draws a night sea; Core Animation moves the creatures and confetti. Shared motion rules keep opening, closing and list transitions consistent.


- **Quiet until it matters.** Collapsed, the island shows one creature and a few words. It opens by itself only when an agent is blocked on you.
- **Moves with the menu bar.** Slide to a full-screen app and the island leaves with the desktop instead of hanging over your work; push the pointer to the top of the screen and it comes down together with the menu bar. A request for a decision can still drop in. You choose: follow the menu bar, always show, or never show over full-screen apps.
- **Finds your sessions by itself.** Claude Code, Codex, ZCode and Kiro sessions are listed from what the agents keep on disk anyway: sessions in the desktop apps, sessions that started before Niko Island did, and agents you have not connected yet.
- **Decide in place.** Allow once, always allow a tool, allow everything for the session, deny, or hand the decision back to the agent. Nothing is approved unless you said so. An edit shows what it would take out and put in before you allow it, and a request for permission can be answered on its notification banner too.
- **Answer questions as tiles.** Multiple-choice questions become big option tiles, single or multi-select, with room to type something else.
- **The answer comes to you.** When a turn ends, a card comes down with what the agent said, its bold, code and links drawn as such. A click on it goes to the session; it opens nothing and takes no keyboard focus. Prefer a one-line notice, or nothing at all: one setting.
- **See how far along it is.** An agent that keeps a list of steps (Claude Code's task list, Codex's plan, ZCode's todos) gets a thin bar on its row with the step in hand.
- **Allow or deny from the keyboard.** ⌃⌥A and ⌃⌥D answer the request the island is showing. Off until you switch it on, and the keys are claimed only while a request is waiting.
- **Never leaves an agent stuck.** A request you did not answer goes back to the agent's own prompt after 10 minutes (you choose how long, or never), answered by nobody; one you answered in the agent's own window leaves the island by itself.
- **Says it twice only if asked.** A request left unanswered can play its cue again after a few minutes. Sounds and cards stay quiet while the screen is locked or asleep, and during quiet hours if you set some.
- **Catches you up.** What finished while the screen was locked is said once when you are back: one card, a line per session, each a way to that session.
- **Warns before a plan runs out.** Each limit shows how fast it is being used and where that leads ("runs out in about 1h 20m, before the reset"), coloured by how full it is. Crossing the threshold you choose (90 % by default), or a pace that would use a window up before it resets, is said once.
- **Tells you when you can go on.** A limit that stopped an agent is remembered with the time it opens again; when it does, the island says so once, with a cue, and to your phone if that is on.
- **Reaches your phone, if you want that.** A short line through a push service you set up yourself (Bark or ntfy): which agent, which project, what kind of moment. Off until you switch it on, and by default only while the screen is locked.
- **A list that scales.** As it comes, or under a heading per project or per agent.
- **One creature per agent.** A starfish for Claude Code, a whale for Codex, a crab for ZCode: you can tell sessions apart before reading a word. Give any agent a different creature if you like.
- **Chips that orient you.** Every row carries how long, which agent, where it runs (iTerm2, Terminal, Ghostty, WezTerm, VS Code, Cursor, tmux, a desktop app, …) and the git branch its folder is on. The model's name is one switch away.
- **Back to the right window.** Click a row or a notification and the session's Terminal.app or iTerm2 tab comes forward, tmux panes included; a desktop-app session brings its app forward, and a Codex desktop session opens on that very conversation. A row's menu copies the last reply, shows the folder in Finder, or copies the command that resumes the session.
- **Usage and limits per agent.** Switch between all agents, Claude Code, Codex and ZCode: the last five hours, today, seven and thirty days, the last 24 hours in quarter hours, four weeks by weekday and hour, and the cache hit rate. The plan's five-hour and weekly limits are shown from whoever knows them: the agent's own files, or, if you switch it on, the provider itself: Anthropic, OpenAI, BigModel / Z.ai, Kimi, MiniMax, GitHub for Copilot's monthly allowances, and Google for Gemini CLI's daily quotas.
- **Yours to shape.** A theme (Classic black, frosted Glass, square-cornered Pixel, deep-blue Midnight), accent colour, width, text size, row density, which chips, hover timing, how fast it opens and closes, which display, language, how many lines of a reply a row shows, a global shortcut (⌃⌥I).
- **Sounds you choose.** Five moments, two built-in sets generated by the app, macOS system sounds, your own files, or a sound pack. All off until you switch them on.
- **An installer you can trust.** It scans first, backs up, verifies, rolls back on failure, and removes only what it added. Settings → Agents says when each connected agent was last heard from, so a hook that never fires does not go unnoticed.
- **Tells you about a new version, if you want that.** Once a day it can ask GitHub whether there is a newer release; *Install and restart* downloads the package for your Mac, checks it against the release's checksums and signature, and puts the old app in the Trash.
- **Private by construction.** No telemetry, no account. The network is used for four optional things, each off until you switch it on.
- **English and 简体中文**, switchable in Settings.

<p align="center">
  <img src="docs/images/island-permission.png" width="400" alt="A request to edit a file, opened on the island: the path, the lines the edit would take out and put in, and Allow once, Always allow Edit, Allow all and Deny">
  <img src="docs/images/island-question.png" width="400" alt="A question shown as four option tiles">
</p>

<p align="center">
  <img src="docs/images/island-done.png" width="640" alt="A finished turn as a card on the island: the agent's last reply with its formatting, a bar for its list of steps, and a way back to the session">
</p>

<p align="center">
  <img src="docs/images/island-recap.png" width="640" alt="What finished while the screen was locked, said once on return: a line per session">
</p>

<p align="center">
  <img src="docs/images/themes/island-classic.png" width="400" alt="The island in the Classic theme: black">
  <img src="docs/images/themes/island-glass.png" width="400" alt="In the Glass theme: the desktop blurred behind it">
  <img src="docs/images/themes/island-pixel.png" width="400" alt="In the Pixel theme: square corners and monospaced type">
  <img src="docs/images/themes/island-midnight.png" width="400" alt="In the Midnight theme: deep blue">
  <br><sub>Classic · Glass · Pixel · Midnight</sub>
</p>

<a id="supported-agents"></a>
## Supported agents

| Agent | Creature | Status | What you get | What connecting touches |
|---|---|---|---|---|
| **Claude Code** (terminal and desktop app) | starfish | Stable | Live status, approvals, questions, usage, rate limits. Sessions are listed even when not connected | `~/.claude/settings.json` (hook entries + status line wrapper) |
| Codex (CLI, IDE extension, desktop app) | whale | Beta | Live status, approvals, usage, limits. Sessions are listed even when not connected. Codex asks you to trust new hooks once (`/hooks`) | `~/.codex/hooks.json` |
| ZCode | crab | Beta | Live status, approvals, usage, plan limits (opt-in). Sessions are listed even when not connected; a session that was open before you connected takes the hooks when it is started again | `~/.zcode/cli/config.json` |
| Cursor | boat | Beta | Live status | `~/.cursor/hooks.json` |
| Windsurf | boat | Beta | Live status | `~/.codeium/windsurf/hooks.json` |
| Gemini CLI | jellyfish | Beta | Live status | `~/.gemini/settings.json` |
| Trae | octopus | Beta | Live status | `~/.trae/hooks.json`, `~/.trae-cn/hooks.json` |
| Qwen Code | jellyfish | Beta | Live status | `~/.qwen/settings.json` |
| CodeBuddy | gull | Beta | Live status | `~/.codebuddy/settings.json` |
| Factory | pufferfish | Beta | Live status | `~/.factory/settings.json` |
| Grok CLI | pufferfish | Beta | Live status | `~/.grok/hooks/niko.json` (own file) |
| OpenCode, MiMoCode | turtle | Experimental | Live status through a small plugin; usage is best effort | `~/.config/opencode/plugins/niko.js`, `~/.config/mimocode/plugins/niko.js` (own files) |
| Copilot CLI | gull | Beta | Live status | `~/.copilot/hooks/niko.json` (own file) |
| Qoder, Qoder CN | turtle | Beta | Live status; a permission prompt shows as "needs permission" and is answered in Qoder | `~/.qoder/settings.json`, `~/.qoder-cn/settings.json` |
| Kimi Code | whale | Beta | Live status; a permission prompt shows as "needs permission" and is answered in Kimi Code | `~/.kimi-code/config.toml` (one marked block at the end) |
| Devin | crab | Beta | Live status, approvals | `~/.config/devin/config.json` |
| QwenWork, QoderWork | jellyfish, turtle | Experimental | Live status | `~/.qwenwork/settings.json`, `~/.qoderwork/settings.json` |
| Kiro (CLI 3 and the IDE) | octopus | Experimental | Live status. Sessions of the Kiro app are listed even when not connected | `~/.kiro/hooks/niko.json` (own file) |
| MiniMax Code | starfish | Experimental | Live status; permission prompts are answered in MiniMax Code | `~/.minimax/plugins/niko/.claude-plugin/plugin.json` and `hooks/hooks.json` (own plugin) |
| Amp | pufferfish | Experimental | Live status through a small plugin that only listens (Amp's plugin API is itself experimental) | `~/.config/amp/plugins/niko.ts` (own file) |
| Mistral Vibe, DeepSeek CLI, Pi / OhMyPi, OpenClaw | — | Planned | — | — |

- **Stable** — wired end to end and covered by tests.
- **Beta** — the adapter writes the format that agent's own hook reference describes, checked against config files from real installations and covered by tests. We have **not driven it end to end against the live agent** ourselves.
- **Experimental** — follows the config location and format listed in [INTEGRATIONS.md](INTEGRATIONS.md), which nobody has validated yet.

The welcome screen and `--recommended` offer stable and beta adapters. Experimental ones are installed only when you pick them:

```bash
niko-island install                         # Claude Code only
niko-island install --recommended           # every detected agent with a stable or beta adapter
niko-island install --agents codex,cursor   # pick some
niko-island install --all                   # every detected agent, experimental ones included
niko-island uninstall                       # always removes everything of ours
```

Approving from the island works with Claude Code, and in beta with Codex, ZCode and Devin. Qoder, Kimi Code and MiniMax Code show a permission prompt as "needs permission" and leave the answer to their own window. For the other agents the island shows status.

### Sessions without hooks

Hooks only speak when something happens, so an idle session, a session that was already open, or an agent you have not connected would be invisible. (ZCode, for one, takes its hooks when a session starts: connect it while a session is open and that session never says a word.) Niko Island therefore also reads what the agents write for themselves: the session logs of Claude Code (`~/.claude/projects/`) and Codex (`~/.codex/sessions/`), and ZCode's session database (`~/.zcode/cli/db/`). From them it takes the session's title, what it is doing, its last reply, and helper agents. That is how sessions of the desktop apps appear.

These rows can be watched and jumped to. Approving from the island needs the agent to be connected, because only a hook can hold a request open. Switch it off in **Settings → Sessions**; the same page sets how long a quiet session stays listed.

<a id="sounds"></a>
## Sounds

Sounds are **off by default**. Open **Settings → Sounds**, switch on **Play sounds**, then keep only the moments you care about. Each one has a play button.

| Moment | Plays when | On once sounds are on |
|---|---|---|
| Work started | an agent picks up your prompt | no (it would fire on every prompt) |
| Needs you | a permission request or a question is waiting | yes |
| Finished | an agent finishes its turn | yes |
| Hit an error | a turn ends because something failed | yes |
| Limit close | a rate-limit window passes 90% | yes |

Where the sound comes from is a separate choice:

- **Island** — soft mallet tones.
- **8-bit** — square-wave arpeggios in the spirit of old game consoles.
- **macOS** — a system sound of your choice per moment.
- **My files** — your own `started`, `attention`, `completed`, `error` or `limit` file (`.wav`, `.aiff`, `.mp3`, `.m4a`) in `~/.niko-island/sounds/`.
- **A sound pack** — a folder with an `openpeon.json` manifest in `~/.niko-island/sounds/packs/` (packs in `~/.openpeon/packs/` are picked up too).

Island and 8-bit are generated by the app from a handful of notes; no audio files ship with it.

<details>
<summary>Sound pack layout</summary>

```text
~/.niko-island/sounds/packs/my-pack/
  openpeon.json
  hello.wav
  ping.mp3
  done.wav
```

```json
{
  "name": "my-pack",
  "display_name": "My Pack",
  "categories": {
    "task.acknowledge": { "sounds": [{ "file": "hello.wav" }] },
    "input.required":   { "sounds": [{ "file": "ping.mp3" }] },
    "task.complete":    { "sounds": [{ "file": "done.wav" }] }
  }
}
```

Work started looks for `task.acknowledge`, then `session.start`. Needs you uses `input.required`, Finished `task.complete`, Hit an error `task.error`, Limit close `resource.limit`. A category with several sounds plays one at random. Files must sit inside the pack folder, and formats the system player cannot decode are skipped. A moment the pack has nothing for falls back to the Island cue.

</details>

<p align="center">
  <img src="docs/images/island-settings-sounds.png" width="640" alt="The Sounds page of the settings window">
</p>

## Settings

Click the gear on the island (or right-click the menu-bar icon) to open the settings window.

- **General** — language (English, 简体中文, or the same as macOS), the global shortcut ⌃⌥I, allowing and denying with ⌃⌥A and ⌃⌥D, going to what needs you with ⌃⌥J, staying quiet while the screen is locked, quiet hours, a reminder for a request left waiting, a line to your phone, open at login, which moments raise a notification.
- **Island** — *Look*: accent colour, which display, width, text size, row density, how many sessions before the list scrolls, creatures or plain dots, which chips a row shows (time, agent, where, git branch, model, how full the context is, what the session has used), how many lines of the last reply. *Opening and closing*: open on hover and how long the pointer has to rest, how soon it closes, how fast it moves, open by itself for a decision, what happens when an agent finishes (a card with its reply, a short notice, or nothing) and how long that stays, whether the island shows while nothing is running. *Full-screen apps*: follow the menu bar, always show, or never; whether a decision may come in over a full-screen app.
- **Sessions** — find sessions from what the agents keep on disk; how long a quiet session stays listed; the list as it comes, by project or by agent; replying from the island (experimental).
- **Agents** — what is on this Mac, what is running now, connect one or all of them, remove, and pick a creature per agent.
- **Sounds** — see above.
- **Usage** — the numbers below, the switches that fetch a plan's limits (one lets Claude Code look itself, three ask a provider), and the opt-in price-list refresh.
- **About** — version, show the welcome again, a redacted diagnostics export, quit.

<p align="center">
  <img src="docs/images/island-settings-island.png" width="520" alt="The Island page of the settings window: look, opening and closing, full-screen apps">
</p>

<a id="usage"></a>
## Usage

Click the bars icon on the island.

<p align="center">
  <img src="docs/images/island-usage.png" width="640" alt="Usage on the island for one agent: five hours, today, seven and thirty days, the plan's limits with their reset times, a bar per day and a line per model">
</p>

- **Per agent.** *All*, or one of Claude Code, Codex, ZCode (and OpenCode, best effort) — whichever have written anything on this Mac.
- **Four windows of your own use.** The last five hours, today, the last seven days, the last thirty. Token counts come from the transcripts on your disk (`~/.claude/projects/`, `~/.codex/sessions/`, ZCode's local database, opened read-only). Cost is an estimate from public list prices; a model with no list price shows its tokens instead.
- **The plan's limits**, with the time each window resets. How much of a plan is used up is known to the provider, so where the figures come from differs per agent:

  | Agent | Without asking anyone | If you switch on "ask the provider" |
  |---|---|---|
  | Codex | Five-hour and weekly windows, from the session files Codex writes | The same windows from ChatGPT, current even while Codex is idle, and how many resets the account has saved; asked with the sign-in Codex keeps on this Mac |
  | Claude Code | The windows from its status line when it runs in a terminal; the last answer Claude Code fetched for itself and kept in `~/.claude.json`, shown with its age for as long as its windows have not reset; and "limit reached, resets at …" from its transcript when it is turned away, desktop app included | Five-hour and weekly percentages from Anthropic, each model's own week where the plan has one, and paid extra usage if it is switched on; asked with the sign-in Claude Code keeps in your Keychain |
  | ZCode (GLM Coding Plan) | Nothing: ZCode writes none of it down | Five-hour and weekly percentages from BigModel or Z.ai, asked with a key of that plan that you paste in |

  The switches are in **Settings → Usage** and are off until you turn them on. For Claude Code there are two ways, and the first is the better one: **let Claude Code look**. The app then runs your own `claude` program with `/usage` every five minutes while a Claude Code session is listed; Claude Code asks Anthropic with its own sign-in (and renews it when needed), exactly as when you type `/usage`, and the app reads what Claude Code keeps in `~/.claude.json`. No sign-in is read by Niko Island, and it works for sessions in the desktop app too. The second way, **Ask Anthropic**, reads Claude Code's sign-in from your Keychain and asks directly; that sign-in has to be current, Niko Island never renews or rewrites it, and a sign-in that was turned down is not offered again until its owner has replaced it. Codex renews its own sign-in when it runs.
- **Resets belong to the provider's own app.** ZCode hands out reset cards and spends them in its own window. For an agent that has such a thing the usage view shows **Reset in ZCode…**, which brings that app forward. Niko Island never spends a reset, and how many cards are left is known only to ZCode's account service. A ChatGPT plan can save resets up; with the Codex lookup on, the usage view says how many are saved.

<a id="privacy"></a>
## Privacy

Short version: **no telemetry, no accounts, all local.** The long version, so you can check it:

- **Nothing phones home.** There is no analytics, crash-reporting or update-check code in the app.
- **No account, no license key, no activation.**
- **Four optional uses of the network, all off by default.** (1) Downloading a public list of model prices, so cost estimates stay current: Settings → Usage, or `niko-island pricing refresh`. Nothing about you is sent. (2) Asking a provider for your plan's limits, see below. (3) A line to your own phone, see below. (4) Asking GitHub whether there is a new version, see below. There is no other network code in the project, and a test keeps it that way.
- **Your data stays in `~/.niko-island/`:**

  ```
  ~/.niko-island/
  ├── bin/        niko-bridge and niko-statusline launchers
  ├── run/        the local socket (directory is 0700, owner-only)
  ├── cache/      rate-limit cache, optional price list
  ├── data/usage/ usage.sqlite: token counts, model names, session ids, project paths
  ├── sounds/     your own sound files and packs, if you add any
  └── logs/       diagnostics, redacted before they are written
  ```

- **Events are trimmed at the source and kept in memory.** The bridge drops tool output and shortens long text in status events. A permission request carries the command or file in question, so you can see what you are approving. None of this is written to disk; the usage database stores numbers and identifiers, never prompts or replies.
- **Session logs are read, never changed, never copied.** To list sessions and count tokens the app reads the logs Claude Code and Codex keep in your home directory, ZCode's local databases and Kiro's session folders (`~/.kiro/sessions/`), read-only. A session's title and last reply are held in memory while the row is on the island. A task list is read the same way (Claude Code's `~/.claude/tasks/`, the plan in a Codex log, ZCode's todo table), and the branch on a row comes from the `.git/HEAD` file of the session's folder: git itself is never run.
- **Running agents are detected locally.** To tell you that an agent is running but not connected, the app looks at the names of your running apps and processes. The list goes nowhere.
- **Local only, owner only.** Agents talk to the app over a unix socket; the app checks the caller's user id on every message. A loopback HTTP port (127.0.0.1, bearer token in an owner-only file) is opened only if you connect an agent that needs a plugin.
- **A sign-in is read only if you switch on "ask the provider".** With **Ask Anthropic** on, the app reads the sign-in Claude Code keeps in your Keychain (macOS may ask you first), holds it in memory, and sends it to `api.anthropic.com` to ask for your limits. With **Ask BigModel / Z.ai** on, it sends a key you pasted in (kept in your Keychain under Niko Island's own name) to `open.bigmodel.cn` or `api.z.ai`. With **Ask OpenAI** on, it reads the ChatGPT sign-in Codex keeps on this Mac (`~/.codex/auth.json`, or the Keychain if Codex is set to use it) and sends it to `chatgpt.com`. Each goes to that one host and nowhere else, under this app's own name; nothing is renewed, rewritten or copied; only percentages, reset times and a count of saved resets are stored. With **Ask Kimi** or **Ask MiniMax** on, a key you pasted in (kept the same way) goes to `api.kimi.com`, or to `api.minimaxi.com` or `api.minimax.io`. With **Ask GitHub** on, the app reads the sign-in the GitHub CLI (`gh`) keeps (`~/.config/gh/hosts.yml`, or its Keychain item) and sends it to `api.github.com` for Copilot's allowances. With **Ask Google** on, the app reads the sign-in Gemini CLI saved (`~/.gemini/oauth_creds.json`, or its Keychain item) and, only while it has not run out, sends it to `cloudcode-pa.googleapis.com`; it is never renewed here. With all these switches off, which is how the app ships, no sign-in or key is ever read. ZCode's own stored sign-in is encrypted by ZCode and is never touched.
- **A line to your phone says only what you let it.** With **Send a line to my phone** on, the app sends a title and one short line to the push server you chose (Bark's or ntfy's own, or one of yours; https, or an address on your own network) and to nowhere else. The line names the agent, the project folder and the kind of moment ("Needs your decision", "Finished"). The command being asked for, or the first line of a reply, goes along only if you also switch on *Say what it is about*. The device key or topic is kept in your Keychain. By default lines go out only while the screen is locked or asleep.
- **Replying types into your terminal, and only there.** With *Reply from the island* on (experimental, off by default), what you type is sent into the tmux pane, iTerm2 session or Terminal tab the agent runs in, as if typed there. Before anything is sent the app checks that the agent is what is waiting at that prompt; if a shell is, nothing is sent. Nothing is typed anywhere else, and macOS asks you before the app may control Terminal or iTerm2.
- **One program is run on your behalf, and only if you ask.** With *Let Claude Code look* on, the app starts your own `claude` program with `/usage`, in an empty folder of its own, with your settings, hooks and MCP servers left out and nothing saved as a session. What Claude Code then says to Anthropic is its own business, done with its own sign-in. The app reads the answer from `~/.claude.json`.
- **A new version, only if you ask.** With *Tell me when there is a new version* on (off by default), the app asks `api.github.com` once a day which release is the latest; the request carries nothing but this app's name and version. *Install and restart* downloads that release's package for this Mac from GitHub, checks it against the release's `SHA256SUMS`, its bundle id, version and signature, and only then moves the old app to the Trash and puts the new one in its place.
- **Auditable hooks.** Every entry the installer writes contains the text `niko-bridge`. Search your config for it at any time.
- **Diagnostics are redacted** and contain file states and counts, not file contents.

## How it compares

There are polished closed-source apps in this space. If you would rather read the code that sits between you and your agents, this is the trade:

| | Niko Island | A typical closed-source alternative |
|---|---|---|
| Price | Free | Paid license or subscription |
| Source | MIT, all of it | Not available |
| License key / activation | None | Usually required |
| Tracking | None, and you can verify that | You have to take their word |
| Direction | Issues and pull requests | The vendor's roadmap |
| Code signing | The project's own certificate, not notarized: one extra step at first launch | Usually notarized |
| Agent coverage today | One stable integration, the rest in beta or experimental | Often broader |

## How it works

```
 agent hook ──▶ niko-bridge ──▶ unix socket ──▶ Niko Island ◀── session logs on disk
      ▲                                              │              (read-only)
      └──────── decision: allow / deny ◀─────────────┘
```

Agents already know how to run a command at each step of their work. `niko-island install` registers a tiny native program, `niko-bridge`, as that command. It forwards a slimmed-down event to the app and, for a permission request, waits for your decision. If the app is not running, or anything at all goes wrong, the bridge exits successfully and the agent carries on as if it were not there.

The second path needs no cooperation from the agent: every second or two the app looks at the tail of the session logs that changed, which is enough to know which sessions exist and what they are doing.

Following the menu bar takes two windows. One belongs to your desktops and travels with them when you swipe; the other belongs to full-screen apps and is moved by exactly as much as that Space's menu bar is showing. The app never asks for Screen Recording or Accessibility permission to do this.

Details for the curious: [SPEC.md](SPEC.md) · [PROTOCOLS.md](PROTOCOLS.md) · [INTEGRATIONS.md](INTEGRATIONS.md).

## What was and was not verified

Here is exactly how far the checking went.

| Verified | How |
|---|---|
| 0.11.0 native smoke | On a 5120×2880 / 2× / 75 Hz display, Metal presented 75.0 FPS over six seconds and released its view after closing. Native search focus, IME Return and committed selection passed. The bundled app stayed running through three synthetic bridge turns and SessionEnd with notifications enabled; banner clicks and a real phone were not tested. |
| Protocol, bridge, installer, approvals, questions, usage engine, session discovery, menu-bar placement, provider lookups, task lists, branches, the finished card, the recap, keyboard decisions, push, the guards around replying, sound synthesis and packs | 422 automated tests (5 environment-dependent skips), including end-to-end runs with the real bridge binary, fault injection and a 100-session soak |
| The island on a real desktop | Tried on macOS 15 with an external display that has no camera housing: hover, click, the settings pages and the usage view; the welcome was captured at the display's own resolution to check that it is sharp; sliding to a full-screen app and back, the menu bar coming down in full screen, and a request arriving over a full-screen app were recorded and checked frame by frame. A finished turn coming down as a card, a request allowed with ⌃⌥A and another denied with ⌃⌥D, and rows with a branch and a step bar were driven through the real bridge and captured from the island's own window |
| Sessions without hooks | Sessions of the Claude, Codex and ZCode desktop apps, Codex helper agents included, appeared on the island without any hook firing for them |
| Installer on a real-world config | Round trip on a private copy of a real `settings.json` that already carried another tool's hooks and a status line: nothing foreign changed, byte-identical after uninstall. The per-agent formats were compared with config files of real installations of Codex, ZCode, Cursor, Windsurf, Gemini CLI and Trae |
| A real approval, given from the island | An interactive Claude Code session (2.1.295, default permission mode, in a terminal of its own) asked to write a file; the request appeared on the island with the path, ⌃⌥A was pressed, and only then did the file exist |
| Claude limits by letting Claude Code look | With the switch on, the usage view showed the five-hour and the weekly window with their reset times, "as Claude Code last saw them, just now", on a Mac whose Claude Code is otherwise only used through the desktop app. No sign-in was read by the app |
| A real Claude Code turn, end to end | Claude Code 2.1.295 was run once, headless, in an empty folder with a temporary hook file pointing at a development build: its `Stop` event carried the closing words, its task list (`TaskCreate` / `TaskUpdate`, one file per task under `~/.claude/tasks/`) was read, and the card came down with both |
| A line to a phone | Both formats were sent to a stand-in server on the same Mac and arrived as JSON with nothing in the address; an address that is neither https nor local was refused. One fixed test line went through the real ntfy service on a random throwaway topic and was read back from it. Not sent through the real Bark service |
| The recap, the grouped list, the card with a reply line | Seen in the running app on that desktop, with a stand-in for the locked screen |
| Limits from ChatGPT for Codex | Asked live, with the sign-in on the machine the app was built on: the weekly window, the plan and the count of saved resets came back and are shown; what was kept on disk holds no sign-in |
| Usage numbers | Totals for about 1 GB of real Claude Code transcripts match an independent recount exactly; Codex sessions are consistent with their own running totals |
| Speed | Cold start to first event in under a second; about 25 ms per hook |
| Both release builds | `scripts/make-release.sh` builds the Apple-silicon and the Intel app, checks architectures and signatures, unpacks the zips and mounts the disk images; the Intel app starts and passes the launch test under Rosetta |

| Not verified yet | Why |
|---|---|
| A MacBook's built-in display, two displays at once, a menu bar set to hide on the desktop | Developed on one external display; the layout for a camera housing exists only as renders |
| Answering a request on its notification banner | The banner's *Allow once* and *Deny* call the same decision as the island's buttons, which is tested; the banner itself was not clicked |
| A real approval in a terminal app or the desktop app | Done once with an interactive Claude Code session in a terminal of its own (see above); not yet with Terminal.app, iTerm2 or the Claude desktop app in front. Section 10 of [docs/TESTPLAN.md](docs/TESTPLAN.md) |
| Any beta adapter against its live agent | See the table above |
| Limits from Anthropic asked directly, with a current sign-in | Never answered on the machine it was tried on. The other way, letting Claude Code look, is the one that was seen working |
| Limits from BigModel / Z.ai | Needs a key typed in by its owner; written against the format several open-source tools document, never run against the live service |
| Codex's plan (`update_plan`) from a live session | The reader follows the documented shape. Claude Code's task files and ZCode's todo table were checked against the real thing |
| Replying from the island into a real terminal | Never run: the machine had no tmux, and letting the app control Terminal or iTerm2 needs a consent only the owner can give. The guards (which terminals, what must be at the prompt, how text is quoted) are covered by tests; the feature is experimental and off by default |
| A line through the real Bark service, and one arriving on a phone | Needs the owner's device key and phone |
| ZCode's limits without a key | Looked into and not possible today: ZCode's own command-line program has no usage command to ask, its app fetches the figures itself and keeps them off the disk. The lookup with a pasted key stays the only way, and that one has not run against the live service |
| The limit-reset notice at a real reset | Tested with a stand-in clock; a real window was not waited out |
| Quiet hours and reminders across real hours, a real lock | Tested with a stand-in clock and a stand-in for the lock |
| Opening a Codex conversation by its link | The link has the form the Codex app itself uses (`codex://threads/<id>`); the click was not watched in Codex's window |
| How the built-in sounds actually sound | They are generated in code and tested for format, length and level. Nobody has listened to them yet |
| Notification and row click-through to Terminal.app, iTerm2 and tmux | Needs a person at the screen; iTerm2 was not available |
| A browser download going through Gatekeeper on another Mac | Release files are checked from the command line, which does not set the quarantine flag |
| Intel hardware, a fresh macOS account | Not available; the Intel build has only run under Rosetta |
| Any of the experimental agents | See the table above |

If something in the second table bites you, please open an issue.

## FAQ

**macOS says the app "cannot be opened" or "is damaged".**
The app is signed with the project's own certificate, not notarized by Apple, because the project has no Apple Developer account, so Gatekeeper does not recognise it. Run `xattr -cr "/Applications/Niko Island.app"` once. Without a terminal: on macOS 14, right-click the app → **Open** → **Open**; on macOS 15 or later, try to open it, then use **System Settings → Privacy & Security → Open Anyway**. The release page lists SHA-256 checksums if you want to verify the download first.

**Which download do I need?**
`apple-silicon` for a Mac with an M-series chip, `intel` for a Mac with an Intel processor (Apple menu → About This Mac tells you). The wrong one either does not start or runs slower under Rosetta.

**The app runs but no creature appears.**
Claude Code and Codex sessions are found from their logs within a few seconds, so first check that **Settings → Sessions → Find sessions…** is on. For a connected agent that stays silent, run `~/.niko-island/bin/niko-island doctor`: the usual cause is the quarantine flag still being set on the bundle, which stops hooks from starting the helper, and `doctor` prints the exact `xattr` command to fix it. Codex also wants you to trust new hooks once (`/hooks`).

**Why are there no limits for Claude Code or ZCode?**
Because nothing on this Mac knows them until somebody asks. Codex writes its limits into its session files; Claude Code and ZCode leave them with the provider. For Claude Code, switch on *Let Claude Code look up my Claude limits* in Settings → Usage: the app then has your own `claude` run `/usage` every few minutes and reads what it keeps, without touching any sign-in, and that works for the desktop app as well. For ZCode, the switch needs a key of the plan from you. See [Usage](#usage).

**Where is the Reset button?**
In 0.3.0 it started a local counter, which is not what anybody means by a reset. A reset of your quota is spent in the provider's own app; for ZCode the usage view has a button that brings it forward. For Codex, the opt-in lookup shows how many resets a ChatGPT plan has saved up.

**A session is listed but I cannot approve from the island.**
That row came from a session log. Connect the agent (Settings → Agents) and restart the session: only a hook can hold a request open while you decide.

**The island shows over my full-screen app / I want it there.**
Settings → Island → Full-screen apps: *Follow the menu bar* (the default), *Always show*, or *Never*. Separately, choose whether a request for a decision may come in over a full-screen app.

**How do I uninstall?**

```bash
~/.niko-island/bin/niko-island uninstall          # removes only entries tagged niko-bridge, restores your status line
~/.niko-island/bin/niko-island uninstall --purge  # also deletes ~/.niko-island and the config backups
```

Then drag the app to the Trash. Your agents keep working throughout. Even if you delete the app without uninstalling, the leftover hooks do nothing: they check for the bridge and exit quietly.

**What exactly does the installer change?**
Run `niko-island install --dry-run` to see. It reads your config first, writes a `*.niko-backup-<timestamp>` copy next to it, adds its entries after yours, re-reads the result to verify, and restores the original if anything does not match. Invalid or unusual config files are left untouched.

**The island is in my way.**
Settings → Island: turn off "Open when the pointer rests on it" (or make the pointer rest longer) and it only opens when you click it or an agent needs you; turn off "Keep the island visible when nothing is running" and it disappears while idle. A click anywhere else puts it away, and that never decides a pending request.

**Does it read my conversations?**
It reads the tail of the session logs on your disk to show a session's title, what it is doing, its list of steps and its last reply; the card that comes down when a turn ends shows that same reply. The text is held in memory while the row or the card is shown, is not written anywhere and does not leave your Mac. Switch the reading off in Settings → Sessions, the card in Settings → Island.

**Can I answer a request without the mouse?**
Yes: switch on *Allow with ⌃⌥A, deny with ⌃⌥D* in Settings → General. The keys answer the request the island is showing. If the island is closed, the first press opens it so that nothing is allowed unseen, and a question is never answered this way. While nothing is waiting, the keys belong to whatever app you are in.

**The card when an agent finishes is too much / too little.**
Settings → Island → *When an agent finishes*: a card with the reply, a one-line notice, or nothing. A card stays while the pointer is on it, goes away when you click its ✕ or open the island, and never takes keyboard focus. How many lines of the reply a row in the list shows is set on the same page.

**Can it tell me on my phone?**
Yes, through a push service you set up yourself: Settings → General → *A line to your phone*. Pick Bark or ntfy, paste the device key or topic, and press *Send a test*. A line says which agent, which project and what kind of moment; switch on *Say what it is about* if you also want the command or the first line of the reply. By default lines go out only while the screen is locked or asleep, and never during quiet hours.

**Can I answer a session from the island?**
Experimentally, for sessions in tmux, iTerm2 or Terminal: Settings → Sessions → *Reply from the island*. What you type is sent into that terminal as if typed there, and only while the agent itself is waiting at its prompt. Sessions in a desktop app have no such way in. This part has not been run against a real terminal yet; it is off by default.

**Will this slow my agent down?**
Each hook starts one small native program that hands off an event and exits: about 25 ms per hook on an Apple-silicon Mac with the release build, whether or not the app is running. It only waits when you are being asked for a decision.

**What does "Allow all" do?**
It approves further requests from that one session until the session ends, you click *Stop*, or the app quits. It is kept in memory only. Questions are never auto-answered.

**Are the cost numbers exact?**
No. They are estimates from public list prices applied to the token counts in your local transcripts. Your plan or invoice may differ.

**What is next?**
See the [Roadmap](docs/ROADMAP.md). Driving the beta adapters against their live agents and trying the island on a MacBook's own display are first on the list.

## Contributing

Issues and pull requests are welcome, especially reports from people running the beta and experimental agents: one confirmed round trip moves an adapter up a level. The manual checklist for what tests cannot cover lives in [docs/TESTPLAN.md](docs/TESTPLAN.md).

## Acknowledgments

A notch-first surface for coding agents is not our idea. Several projects explored it earlier, and their work shaped what people expect from one. Niko Island's code, artwork, sounds and copy are its own.

## License

[MIT](LICENSE). The bundled model price list is a pruned copy of LiteLLM's public table, used under its MIT license ([notice](Assets/LITELLM-NOTICE.txt)).

Niko Island is an independent project. It is not affiliated with, endorsed by, or sponsored by any AI vendor. Product names in the table above are used only to say what the app works with.

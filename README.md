<h1 align="center">
  <img src="docs/images/icon.png" width="64" height="64" alt="Niko Island app icon" valign="middle">&nbsp;
  Niko Island
</h1>
<p align="center">
  <b>An island at the top of your screen for the AI coding agents in your terminals.</b><br>
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
  <img src="docs/images/island-sessions.png" width="760" alt="The island open on five sessions: each row has a pixel creature, the project and prompt, what the agent is doing, and chips for elapsed time, agent and terminal">
</p>

<p align="center">
  <sub>See every session at a glance, approve or answer from where you are, and jump back to the right terminal when you want to.</sub>
</p>

<p align="center">
  <img src="docs/images/mascots/starfish.gif" width="40" alt="Starfish" title="Claude Code">&nbsp;
  <img src="docs/images/mascots/whale.gif" width="40" alt="Whale" title="Codex CLI">&nbsp;
  <img src="docs/images/mascots/boat.gif" width="40" alt="Boat" title="Cursor CLI · Windsurf">&nbsp;
  <img src="docs/images/mascots/gull.gif" width="40" alt="Gull" title="Copilot CLI">&nbsp;
  <img src="docs/images/mascots/jellyfish.gif" width="40" alt="Jellyfish" title="Gemini CLI · Qwen Code">&nbsp;
  <img src="docs/images/mascots/turtle.gif" width="40" alt="Turtle" title="OpenCode · MiMoCode">&nbsp;
  <img src="docs/images/mascots/octopus.gif" width="40" alt="Octopus" title="Trae · Kiro">&nbsp;
  <img src="docs/images/mascots/puffer.gif" width="40" alt="Pufferfish" title="Grok CLI · Factory">&nbsp;
  <img src="docs/images/mascots/island.gif" width="40" alt="Island" title="Everything else">
</p>
<p align="center">
  <sub>Claude Code · Codex CLI · Cursor CLI · Copilot CLI · Gemini CLI · Grok CLI · OpenCode · MiMoCode · Trae · Windsurf · Qwen Code · Kiro · Factory</sub>
</p>

> **Version note.** The pictures show **0.2.0**, the island redesign. It is on `main` and has not been released yet; the latest download is still 0.1.0, which has the earlier, simpler panel. [Build from source](#build-from-source) to try the island today.

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

<sub>Every image on this page is rendered by the app's own view code with sample sessions (`scripts/make-assets.sh`). None is a capture of a real desktop yet.</sub>

<a id="install"></a>
## Install

### Download a release

1. Get the latest zip from [Releases](https://github.com/baogutang/niko-island/releases/latest) and unzip it.
2. Move the app to Applications and clear the download quarantine. The app is ad-hoc signed (the project has no Apple Developer account), so macOS will not open a downloaded copy straight away:

   ```bash
   mv "Niko Island.app" /Applications/
   xattr -cr "/Applications/Niko Island.app"
   open "/Applications/Niko Island.app"
   ```

   No terminal at hand? On macOS 14, right-click the app → **Open** → **Open**. On macOS 15 or later, try to open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. The `xattr` command is the reliable route because it also clears the flag on the small helper that agent hooks run; if that flag is still set, **Settings → Agents** says so.

3. Connect Claude Code. Look at the plan first, then apply it:

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install
   ```

   Or click the gear on the island → **Agents** → **Connect**.

Start `claude` in any terminal and a creature shows up on the island. After installing, `~/.niko-island/bin/niko-island` is a shortcut to the same command line.

<a id="build-from-source"></a>
### Build from source

Requires macOS 14+ and Xcode 16 or later (Swift 6).

```bash
git clone https://github.com/baogutang/niko-island.git
cd niko-island
scripts/check.sh              # the whole test suite
scripts/make-app.sh           # → dist/Niko Island.app, ad-hoc signed
scripts/smoke-launch.sh       # launches it against a throwaway directory
open "dist/Niko Island.app"
```

## What is Niko Island?

Coding agents spend most of their time working and a little of it waiting for you: a command to approve, a question to answer, a turn that has finished. Those moments are easy to miss when the agent lives in a terminal tab behind three other windows.

Niko Island keeps a small black island at the top of the screen, growing out of the camera housing on a MacBook and sitting on the menu bar anywhere else. It stays small while agents work, opens when one needs you, and lets you act right there.

<a id="features"></a>
## Features

- **Quiet until it matters.** Collapsed, the island shows one creature and a few words. It opens by itself only when an agent is blocked on you.
- **Decide in place.** Allow once, always allow a tool, allow everything for the session, deny, or hand the decision back to the terminal. Nothing is approved unless you said so.
- **Answer questions as tiles.** Multiple-choice questions become big option tiles, single or multi-select, with room to type something else.
- **One creature per agent.** A starfish for Claude Code, a whale for Codex, a turtle for OpenCode: you can tell sessions apart before reading a word.
- **Chips that orient you.** Every row carries how long, which agent, and which terminal (iTerm2, Terminal, Ghostty, WezTerm, VS Code, Cursor, tmux, …).
- **Back to the right tab.** Click a row or a notification and the session's Terminal.app or iTerm2 tab comes forward, tmux panes included.
- **Sounds you choose.** Five moments, two built-in sets generated by the app, macOS system sounds, your own files, or a sound pack. All off until you switch them on.
- **Usage, locally.** Tokens and estimated cost per model for today and the last seven days, read from transcripts on your disk; Claude rate limits from the status line.
- **An installer you can trust.** It scans first, backs up, verifies, rolls back on failure, and removes only what it added.
- **Private by construction.** No telemetry, no account, one optional download that is off by default.
- **English and 简体中文.**

<p align="center">
  <img src="docs/images/island-permission.png" width="400" alt="A permission request opened on the island with Allow once, Always allow Bash, Allow all and Deny">
  <img src="docs/images/island-question.png" width="400" alt="A question shown as four option tiles">
</p>

<a id="supported-agents"></a>
## Supported agents

| Agent | Creature | Status | What you get | What `install` touches |
|---|---|---|---|---|
| **Claude Code** | starfish | Stable | Live status, approvals, questions, usage, rate limits | `~/.claude/settings.json` (hook entries + status line wrapper) |
| Codex CLI | whale | Experimental | Live status; usage from session logs | `~/.codex/hooks.json` |
| Cursor CLI | boat | Experimental | Live status | `~/.cursor/hooks.json` |
| Copilot CLI | gull | Experimental | Live status | `~/.copilot/hooks/niko.json` (own file) |
| Gemini CLI | jellyfish | Experimental | Live status | `~/.gemini/config/plugins/niko/` (own directory) |
| Grok CLI | pufferfish | Experimental | Live status | `~/.grok/hooks/niko.json` (own file) |
| Trae | octopus | Experimental | Live status | `~/.trae/hooks.json`, `~/.trae-cn/hooks.json` |
| Windsurf | boat | Experimental | Live status | `~/.codeium/windsurf/hooks.json` |
| OpenCode, MiMoCode | turtle | Experimental | Live status through a small plugin; usage is best effort | `~/.config/opencode/plugins/niko.js`, `~/.config/mimocode/plugins/niko.js` (own files) |
| Qwen Code, QwenWork | jellyfish | Experimental | Live status | `~/.qwen/settings.json`, `~/.qwenwork/settings.json` |
| Kiro | octopus | Experimental | Live status | `~/.kiro/settings/cli.json` |
| Factory | pufferfish | Experimental | Live status | `~/.factory/settings.json` |
| Kimi Code, DeepSeek CLI, Droid, Pi / OhMyPi, OpenClaw, Amp | — | Planned | — | — |

**Stable** means wired end to end and covered by tests. **Experimental** means the adapter follows the config location and format listed in [INTEGRATIONS.md](INTEGRATIONS.md) but has **not been validated against a live copy of that agent**. Experimental adapters are never installed by default:

```bash
niko-island install --agents codex,cursor   # pick some
niko-island install --all                   # every detected agent
niko-island uninstall                       # always removes everything of ours
```

Approving from the island works with Claude Code only for now. For the other agents the island shows status.

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

- **General** — which moments raise a notification; open at login.
- **Island** — open on hover, open by itself for a decision, the short "finished" notice, whether the island shows while nothing is running.
- **Agents** — connect and remove agents.
- **Sounds** — see above.
- **Usage** — today, the last seven days, per model, Claude rate limits; the opt-in price-list refresh.
- **About** — version, a redacted diagnostics export, quit.

<p align="center">
  <img src="docs/images/island-usage.png" width="640" alt="Usage on the island: cost today and for seven days, a bar per day, models and rate-limit windows">
</p>

<a id="privacy"></a>
## Privacy

Short version: **no telemetry, no accounts, all local.** The long version, so you can check it:

- **Nothing phones home.** There is no analytics, crash-reporting or update-check code in the app.
- **No account, no license key, no activation.**
- **One optional network request.** The app can download a public list of model prices to keep cost estimates current. It is **off by default**; switch it on in Settings → Usage or run `niko-island pricing refresh`. That is the only network code in the project.
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
- **Local only, owner only.** Agents talk to the app over a unix socket; the app checks the caller's user id on every message. A loopback HTTP port (127.0.0.1, bearer token in an owner-only file) is opened only if you connect an agent that needs a plugin.
- **Your credentials are never read**, stored or forwarded.
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
| Code signing | Ad-hoc: one extra step at first launch | Usually notarized |
| Agent coverage today | One stable integration, the rest experimental | Often broader |

## How it works

```
 agent hook ──▶ niko-bridge ──▶ unix socket ──▶ Niko Island
      ▲                                              │
      └──────── decision: allow / deny ◀─────────────┘
```

Agents already know how to run a command at each step of their work. `niko-island install` registers a tiny native program, `niko-bridge`, as that command. It forwards a slimmed-down event to the app and, for a permission request, waits for your decision. If the app is not running, or anything at all goes wrong, the bridge exits successfully and the agent carries on as if it were not there.

Details for the curious: [SPEC.md](SPEC.md) · [PROTOCOLS.md](PROTOCOLS.md) · [INTEGRATIONS.md](INTEGRATIONS.md).

## What was and was not verified

Here is exactly how far the checking went.

| Verified | How |
|---|---|
| Protocol, bridge, installer, approvals, questions, usage engine, island state, sound synthesis and packs | About 250 automated tests, including end-to-end runs with the real bridge binary, fault injection and a 100-session soak |
| Installer on a real-world config | Round trip on a private copy of a real `settings.json` that already carried another tool's hooks and a status line: nothing foreign changed, byte-identical after uninstall |
| Usage numbers | Totals for about 1 GB of real Claude Code transcripts match an independent recount exactly; Codex sessions are consistent with their own running totals |
| The island window | The assembled app was launched: the window sits above the menu bar, flush with the top of the screen, lays out collapsed and opens for a permission request (`scripts/smoke-launch.sh`) |
| Speed | Cold start to first event in under a second; about 25 ms per hook |
| Universal build (0.1.0) | Both halves run, the Intel half under Rosetta |

| Not verified yet | Why |
|---|---|
| How the island feels on a real desktop | The layout was judged from rendered images. Hover-to-open, click-outside-to-close and the animations have not been tried by hand |
| How the built-in sounds actually sound | They are generated in code and tested for format, length and level. Nobody has listened to them yet |
| A live Claude Code session driving the island | The end-to-end tests use a simulated agent that follows Claude Code's documented hook contract. Confirming it with a real session is the first step in [docs/TESTPLAN.md](docs/TESTPLAN.md) |
| Notification and row click-through to Terminal.app, iTerm2 and tmux | Needs a person at the screen; iTerm2 was not available |
| A display with a camera housing | Developed on a Mac without one; that layout exists only as renders |
| Intel hardware, a fresh macOS account | Not available |
| Any of the experimental agents | See the table above |

If something in the second table bites you, please open an issue.

## FAQ

**macOS says the app "cannot be opened" or "is damaged".**
The app is ad-hoc signed because the project has no Apple Developer account, so Gatekeeper does not recognise it. Run `xattr -cr "/Applications/Niko Island.app"` once. Without a terminal: on macOS 14, right-click the app → **Open** → **Open**; on macOS 15 or later, try to open it, then use **System Settings → Privacy & Security → Open Anyway**. The release page lists SHA-256 checksums if you want to verify the download first.

**The app runs but no creature appears.**
Run `~/.niko-island/bin/niko-island doctor`. The usual cause is the quarantine flag still being set on the bundle, which stops hooks from starting the helper; `doctor` prints the exact `xattr` command to fix it.

**How do I uninstall?**

```bash
~/.niko-island/bin/niko-island uninstall          # removes only entries tagged niko-bridge, restores your status line
~/.niko-island/bin/niko-island uninstall --purge  # also deletes ~/.niko-island and the config backups
```

Then drag the app to the Trash. Your agents keep working throughout. Even if you delete the app without uninstalling, the leftover hooks do nothing: they check for the bridge and exit quietly.

**What exactly does the installer change?**
Run `niko-island install --dry-run` to see. It reads your config first, writes a `*.niko-backup-<timestamp>` copy next to it, adds its entries after yours, re-reads the result to verify, and restores the original if anything does not match. Invalid or unusual config files are left untouched.

**The island is in my way.**
Settings → Island: turn off "Open when the pointer rests on it" and it only opens when you click it or an agent needs you; turn off "Keep the island visible when nothing is running" and it disappears while idle. A click anywhere else puts it away, and that never decides a pending request.

**Will this slow my agent down?**
Each hook starts one small native program that hands off an event and exits: about 25 ms per hook on an Apple-silicon Mac with the release build, whether or not the app is running. It only waits when you are being asked for a decision.

**What does "Allow all" do?**
It approves further requests from that one session until the session ends, you click *Stop*, or the app quits. It is kept in memory only. Questions are never auto-answered.

**Are the cost numbers exact?**
No. They are estimates from public list prices applied to the token counts in your local transcripts. Your plan or invoice may differ.

**What is next?**
See the [Roadmap](docs/ROADMAP.md). Trying the island by hand and validating the experimental adapters against live agents are first on the list.

## Contributing

Issues and pull requests are welcome, especially reports from people running the experimental agents: one confirmed config format moves an adapter from experimental to stable. The manual checklist for what tests cannot cover lives in [docs/TESTPLAN.md](docs/TESTPLAN.md).

## Acknowledgments

A notch-first surface for coding agents is not our idea. Several projects explored it earlier, and their work shaped what people expect from one. Niko Island's code, artwork, sounds and copy are its own.

## License

[MIT](LICENSE). The bundled model price list is a pruned copy of LiteLLM's public table, used under its MIT license ([notice](Assets/LITELLM-NOTICE.txt)).

Niko Island is an independent project. It is not affiliated with, endorsed by, or sponsored by any AI vendor. Product names in the table above are used only to say what the app works with.

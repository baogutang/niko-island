# Manual test plan

Automated tests (`swift test`) cover the protocol, the bridge, the installer and
the app model end to end. This page lists what still needs a human with a
screen: windows, notifications, and real terminals. Everything here can be done
without touching your real agent configuration until step 4.

Legend: ☐ = check by hand. Items marked **(not automated)** have no test at all
behind them yet.

## 0. Build

```bash
swift test                       # everything green
scripts/make-app.sh              # dist/Niko Island.app (ad-hoc signed)
scripts/smoke-launch.sh          # launches against a throwaway directory
```

## 1. Menu-bar icon and panel

Launch with a throwaway runtime directory so nothing of yours is used:

```bash
NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni "dist/Niko Island.app/Contents/MacOS/niko-island"
```

- ☐ A pill-shaped icon appears in the menu bar; no Dock icon.
- ☐ Click toggles the panel. On a display without a notch it drops down from
  the icon; on a notched display it hangs from the top centre. **(not automated)**
- ☐ Click anywhere else: the panel closes.
- ☐ Right-click the icon: menu with "Open Releases Page" and "Quit".
- ☐ Empty state says no agents are running and offers "Set up hooks…".
- ☐ Switch macOS to 简体中文 (or launch with `-AppleLanguages "(zh-Hans)"`): all
  panel text is Chinese.

## 2. Sessions and approvals with a fake agent

In another terminal, drive the bundled bridge by hand:

```bash
export NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni
B="dist/Niko Island.app/Contents/Helpers/niko-bridge"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"'$PWD'","prompt":"try the panel"}' | "$B" --source claude
echo '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"make test"}}' | "$B" --source claude
```

- ☐ A card appears: project name + "try panel", "running `make test`", a timer.

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"git push"}}' | "$B" --source claude
```

- ☐ The panel opens by itself with a red card showing the command.
- ☐ **Allow once** → the command above prints `{"hookSpecificOutput":…"behavior":"allow"…}`.
- ☐ Repeat; **Deny** → `"behavior":"deny"`.
- ☐ Repeat; **Always allow Bash** → allowed; send the same request again: it
  returns immediately, no card; the session card shows "Auto-approving: Bash"
  with a Stop link.
- ☐ Repeat with `"tool_name":"Edit"`; **Allow all** → later requests for this
  session return immediately; a different `session_id` still asks.
- ☐ **Open in Terminal** → the command prints nothing and exits 0.
- ☐ Send a request, then press Ctrl-C on the command: the card disappears.
- ☐ Send a request, then quit the app: the command exits 0 with no output.
- ☐ A pending card is still there after you close and reopen the panel, and the
  menu-bar icon shows the count. It never resolves on its own.

Question wizard:

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres"},{"label":"SQLite"}]},{"question":"Which features?","header":"Feat","multiSelect":true,"options":[{"label":"Auth"},{"label":"Billing"},{"label":"Search"}]}]}}' | "$B" --source claude
```

- ☐ Step 1 of 2 with radio options; Next is disabled until something is picked.
- ☐ Step 2 allows several; Back returns with the earlier choice intact.
- ☐ Typing in "Other…" works (the panel takes keyboard focus). **(not automated)**
- ☐ Send answer → output contains `"answers":{"Which database?":"…","Which features?":"…, …"}`.

## 3. Notifications and jump-back **(not automated)**

Needs the bundled app (not `swift run`) and notification permission.

- ☐ First notification-worthy event triggers the macOS permission prompt once.
- ☐ `Stop` event → banner "Finished and waiting for you" (unless the terminal
  that hosts the session is the frontmost app).
- ☐ Permission request → banner; question → banner with the question text.
- ☐ Settings → untick an event → no banner for it. Sounds are all off by
  default; ticking one plays a sound for that event.
- ☐ Click a banner for a session started from **Terminal.app** → that window
  and tab come to the front (first time: macOS asks to allow controlling
  Terminal).
- ☐ Same from **iTerm2** → the right window, tab and split pane are selected.
- ☐ Same from **tmux inside iTerm2** and **tmux inside Terminal.app** → the tmux
  window/pane is selected and the hosting tab comes forward.
- ☐ From another host (VS Code terminal, Ghostty, …) → the app is brought
  forward (tab selection is not supported there).

## 4. Real agent (Claude Code)

This is the first step that changes a real config. It is reversible.

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" install --dry-run   # read the plan first
"dist/Niko Island.app/Contents/MacOS/niko-island" install
```

- ☐ `~/.claude/settings.json` gained entries containing `niko-bridge`; your own
  hooks are still there, in the same order; a `settings.json.niko-backup-…`
  sits next to it.
- ☐ Start `claude` in a project: a card appears and follows its activity.
- ☐ Trigger a permission prompt: decide from the panel; Claude continues.
- ☐ Ask Claude something that makes it use its question tool; answer in the panel.
- ☐ Your previous status line (if any) still renders.
- ☐ Usage tab shows today's tokens after a turn.
- ☐ Quit Niko Island, keep using `claude`: no errors, no delays.

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" uninstall
```

- ☐ `diff` against the backup shows `settings.json` is back to what it was.
- ☐ `claude` still works. Delete the app; it still works.

## 5. Release artifact

- ☐ Download the zip from the Releases page on another Mac, unzip, run
  `xattr -cr "Niko Island.app"` (or: right-click → Open on macOS 14; System
  Settings → Privacy & Security → Open Anyway on macOS 15+), confirm it launches.
- ☐ Before clearing the flag, `niko-island doctor` reports the bridge as
  quarantined and the Settings tab shows the same warning; after clearing, both
  are gone. **(not automated beyond the detection itself)**
- ☐ `lipo -archs "Niko Island.app/Contents/MacOS/niko-island"` → `x86_64 arm64`.
- ☐ `shasum -a 256 -c SHA256SUMS` passes.

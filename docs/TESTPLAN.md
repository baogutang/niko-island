# Manual test plan

Automated tests (`scripts/check.sh`) cover the protocol, the bridge, the
installer, the sound engine and the app model end to end. This page lists what
still needs a human with a screen and ears: the island window, sounds,
notifications, and real terminals. Everything here can be done without touching
your real agent configuration until step 6.

Legend: ☐ = check by hand. Items marked **(not automated)** have no test at all
behind them yet. As of 0.2.0 nobody has worked through sections 1 to 5 by hand:
the island was judged from rendered images and a scripted launch only.

## 0. Build

```bash
scripts/check.sh                 # everything green
scripts/make-app.sh              # dist/Niko Island.app (ad-hoc signed)
scripts/smoke-launch.sh          # launches against a throwaway directory
```

## 1. The island window

Launch with a throwaway runtime directory so nothing of yours is used:

```bash
NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni "dist/Niko Island.app/Contents/MacOS/niko-island"
```

- ☐ A small black tab hangs from the top centre of the display, flush with the
  top edge and in front of the menu bar (on the display with a camera housing
  if there is one, otherwise the primary display). No Dock icon; a pill-shaped
  icon sits in the menu bar.
- ☐ On a display with a camera housing the tab wraps around it, with the
  creature on one side and the text on the other. **(not automated; never seen
  on real hardware)**
- ☐ Rest the pointer on the tab: it opens with a spring, without stealing
  keyboard focus from the app you were typing in. Move away: it closes after a
  moment. **(not automated)**
- ☐ Click the tab, or the menu-bar icon: it opens and stays open while the
  pointer is elsewhere. Click anywhere outside: it closes. **(not automated)**
- ☐ While the island is closed, clicks and drags just below the tab reach the
  window underneath (the transparent part of the island's window lets them
  through). **(not automated)**
- ☐ Right-click the menu-bar icon: "Settings…", "Open Releases Page",
  "Quit Niko Island".
- ☐ Open with no sessions: "No agents running yet." and a "Connect an agent…"
  button that opens Settings → Agents.
- ☐ The header has three buttons: usage, sound on/off, settings. Usage switches
  the island to the usage view and back.
- ☐ Switch macOS to 简体中文 (or launch with `-AppleLanguages "(zh-Hans)"`): all
  island and settings text is Chinese.
- ☐ Plug in a second display, change the primary display, change resolution:
  the island re-centres on the right display each time. **(not automated)**

## 2. Sessions and approvals with a fake agent

In another terminal, drive the bundled bridge by hand:

```bash
export NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni
B="dist/Niko Island.app/Contents/Helpers/niko-bridge"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"'$PWD'","prompt":"try the island"}' | "$B" --source claude
echo '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"make test"}}' | "$B" --source claude
```

- ☐ The collapsed tab shows a starfish and "running make test".
- ☐ Open the island: one row with the starfish, the project name, "try the
  island", the activity line, and chips for elapsed time and "Claude Code" (plus
  the terminal's name when the bridge was started from a terminal it knows).

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"git push"}}' | "$B" --source claude
```

- ☐ The island opens by itself with the request on top: the command in a box
  and Allow once / Always allow Bash / Allow all / Deny.
- ☐ **Allow once** → the command above prints `{"hookSpecificOutput":…"behavior":"allow"…}`
  and the island closes again (it opened for the request, so it leaves with it).
- ☐ Repeat; **Deny** → `"behavior":"deny"`.
- ☐ Repeat; **Always allow Bash** → allowed; send the same request again: it
  returns immediately and nothing opens; the session row shows
  "Auto-approving: Bash" with a Stop link.
- ☐ Repeat with `"tool_name":"Edit"`; **Allow all** → later requests for this
  session return immediately; a different `session_id` still asks.
- ☐ **Decide in the terminal instead** → the command prints nothing and exits 0.
- ☐ Send a request, then press Ctrl-C on the command: the request disappears.
- ☐ Send a request, then quit the app: the command exits 0 with no output.
- ☐ Send a request and click outside the island: it closes, the tab says
  "… needs you" with a bell, and the request is still there when you open it
  again. It never resolves on its own.
- ☐ With two requests waiting, a "2 waiting" chip shows; deciding the first
  brings up the second.

Questions:

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres"},{"label":"SQLite"}]},{"question":"Which features?","header":"Feat","multiSelect":true,"options":[{"label":"Auth"},{"label":"Billing"},{"label":"Search"}]}]}}' | "$B" --source claude
```

- ☐ "Question 1 of 2" with two tiles lettered A and B; Next is dimmed until one
  is picked.
- ☐ Question 2 allows several; Back returns with the earlier choice intact.
- ☐ Typing in "Type something else…" works: the island takes keyboard focus
  only once you click the field. **(not automated)**
- ☐ **Send answers** → output contains `"answers":{"Which database?":"…","Which features?":"…, …"}`.

Finishing and failing:

```bash
echo '{"hook_event_name":"Stop","session_id":"t1","cwd":"'$PWD'"}' | "$B" --source claude
echo '{"hook_event_name":"StopFailure","session_id":"t1","cwd":"'$PWD'","error":"rate limited"}' | "$B" --source claude
```

- ☐ After `Stop`, the collapsed tab names the session as finished for a few
  seconds, then returns to its usual text.
- ☐ After `StopFailure`, the row reads "hit an error" with the message.

## 3. Sounds **(not automated beyond synthesis and settings)**

Settings → Sounds. Nobody has listened to the built-in sets yet, so this section
is also a listening test: note anything harsh, too long or too quiet.

- ☐ "Play sounds" is off on first launch and nothing in section 2 made a sound.
- ☐ Switch it on. The play button next to each of the five moments plays it.
  "Work started" is the only moment that is off.
- ☐ Island set: soft mallet tones, each under about a second. 8-bit set: short
  square-wave arpeggios. Both sit at a similar loudness.
- ☐ The volume slider changes the level of the next preview.
- ☐ macOS: each moment gets a menu of system sounds, and previews play them.
- ☐ Repeat the `PermissionRequest` and `Stop` commands from section 2: "Needs
  you" and "Finished" play. Several events in quick succession do not stack into
  noise (cues are spaced at least a second and a half apart).
- ☐ Click the speaker button in the island's header: sounds stop; click again:
  they are back.
- ☐ "Open folder" opens `~/.niko-island/sounds/`. Put a file named
  `completed.wav` (or `.aiff`, `.mp3`, `.m4a`) there, reopen Settings: "My
  files" appears as a sound set and "Finished" plays your file; moments without
  a file fall back to the Island cue.
- ☐ Put a pack folder with an `openpeon.json` manifest into
  `~/.niko-island/sounds/packs/`: it appears by its display name and its sounds
  play for the matching moments.

## 4. Settings window

- ☐ The gear on the island and "Settings…" in the menu both open one window
  with General, Island, Agents, Sounds, Usage, About in a sidebar.
- ☐ Island → switch off "Open when the pointer rests on it": hovering no longer
  opens it, clicking still does.
- ☐ Island → switch off "Open by itself when an agent needs a decision": a
  request leaves the island closed; the tab shows the bell.
- ☐ Island → switch off "Keep the island visible when nothing is running": with
  no sessions the tab disappears, and comes back with the first event.
- ☐ General → "Open Niko Island at login" registers the app (works only from
  the bundled app, ideally in /Applications). **(not automated)**
- ☐ About → "Export diagnostics" writes a report and shows its path.

## 5. Notifications and jump-back **(not automated)**

Needs the bundled app (not `swift run`) and notification permission.

- ☐ First notification-worthy event triggers the macOS permission prompt once.
- ☐ `Stop` event → banner "Finished and waiting for you" (unless the terminal
  that hosts the session is the frontmost app).
- ☐ Permission request → banner; question → banner with the question text.
- ☐ Settings → General → switch a moment off → no banner for it.
- ☐ Click a banner, or a session row, for a session started from
  **Terminal.app** → that window and tab come to the front (first time: macOS
  asks to allow controlling Terminal).
- ☐ Same from **iTerm2** → the right window, tab and split pane are selected.
- ☐ Same from **tmux inside iTerm2** and **tmux inside Terminal.app** → the tmux
  window/pane is selected and the hosting tab comes forward.
- ☐ From another host (VS Code terminal, Ghostty, …) → the app is brought
  forward (tab selection is not supported there), and the row's chip names it.

## 6. Real agent (Claude Code)

This is the first step that changes a real config. It is reversible.

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" install --dry-run   # read the plan first
"dist/Niko Island.app/Contents/MacOS/niko-island" install
```

- ☐ `~/.claude/settings.json` gained entries containing `niko-bridge`; your own
  hooks are still there, in the same order; a `settings.json.niko-backup-…`
  sits next to it.
- ☐ Start `claude` in a project: a starfish appears and the row follows its
  activity.
- ☐ Trigger a permission prompt: decide on the island; Claude continues.
- ☐ Ask Claude something that makes it use its question tool; answer on the
  island.
- ☐ Your previous status line (if any) still renders.
- ☐ The usage view shows today's tokens after a turn.
- ☐ Quit Niko Island, keep using `claude`: no errors, no delays.

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" uninstall
```

- ☐ `diff` against the backup shows `settings.json` is back to what it was.
- ☐ `claude` still works. Delete the app; it still works.

## 7. Release artifact

- ☐ Download the zip from the Releases page on another Mac, unzip, run
  `xattr -cr "Niko Island.app"` (or: right-click → Open on macOS 14; System
  Settings → Privacy & Security → Open Anyway on macOS 15+), confirm it launches.
- ☐ Before clearing the flag, `niko-island doctor` reports the bridge as
  quarantined and Settings → Agents shows the same warning; after clearing,
  both are gone. **(not automated beyond the detection itself)**
- ☐ `lipo -archs "Niko Island.app/Contents/MacOS/niko-island"` → `x86_64 arm64`.
- ☐ `shasum -a 256 -c SHA256SUMS` passes.

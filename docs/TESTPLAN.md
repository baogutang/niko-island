# Manual test plan

Automated tests (`scripts/check.sh`) cover the protocol, the bridge, the
installer, session discovery, the menu-bar placement rules, the sound engine
and the app model end to end. This page lists what still needs a human with a
screen and ears: the island window, full-screen apps, sounds, notifications,
and real agents. Nothing here touches your real agent configuration until
section 10.

Legend: ☐ = check by hand. ☑ = checked by hand for 0.3.0 or 0.4.0, on one
setup: macOS 15 with an external display that has no camera housing. A ☑ says nothing about
a MacBook's own display or two displays at once. Items marked **(not
automated)** have no test at all behind them.

## 0. Build

```bash
scripts/check.sh                 # everything green
scripts/make-app.sh              # dist/Niko Island.app for this Mac (ad-hoc signed)
scripts/smoke-launch.sh          # launches against a throwaway directory
scripts/make-release.sh          # both release packages, built and verified
```

## 1. The island window

Launch with a throwaway runtime directory so nothing of yours is used:

```bash
NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni "dist/Niko Island.app/Contents/MacOS/niko-island" -NikoOnboardingDisabled YES
```

(`-NikoOnboardingDisabled YES` skips the welcome, which section 3 looks at. The
app still lists your real Claude Code and Codex sessions, because it reads
their session logs; switch that off in Settings → Sessions for an empty
island.)

- ☐ A small black tab hangs from the top centre of the display, flush with the
  top edge and in front of the menu bar (on the display with a camera housing
  if there is one, otherwise the primary display). No Dock icon; a pill-shaped
  icon sits in the menu bar.
- ☐ On a display with a camera housing the tab wraps around it, with the
  creature on one side and the text on the other. **(not automated; never seen
  on real hardware)**
- ☑ Rest the pointer on the tab: it opens with a spring, without stealing
  keyboard focus from the app you were typing in. Move away: it closes after a
  moment. **(not automated)**
- ☑ Click the tab, or the menu-bar icon: it opens and stays open while the
  pointer is elsewhere. Click anywhere outside: it closes. **(not automated)**
- ☐ Press ⌃⌥I from any app: the island opens; press it again: it closes.
  **(not automated)**
- ☐ While the island is closed, clicks and drags just below the tab reach the
  window underneath (the transparent part of the island's window lets them
  through). **(not automated)**
- ☐ Right-click the menu-bar icon: "Settings…", "Open Releases Page",
  "Quit Niko Island".
- ☐ Open with no sessions: "No agents running yet." and a "Connect an agent…"
  button that opens Settings → Agents. If an agent's app or CLI is running but
  not connected, the empty island names it instead and offers to connect it.
- ☐ The header has three buttons: usage, sound on/off, settings. Usage switches
  the island to the usage view and back.
- ☐ Switch macOS to 简体中文 (or launch with `-AppleLanguages "(zh-Hans)"`): all
  island and settings text is Chinese.
- ☐ Plug in a second display, change the primary display, change resolution:
  the island re-centres on the right display each time. Settings → Island →
  Display moves it to the display you pick. **(not automated)**

## 2. Menu bar and full-screen apps **(placement rules are tested; the windows are not)**

The island is two windows: one that lives on your desktops and one that lives
in full-screen Spaces. Launch with `NIKO_ISLAND_DEBUG=1` to see a line
`island placement surface=… lift=… bar=…` whenever the placement changes.

- ☑ Put an app in full screen (green button), then swipe between it and the
  desktop: the island travels with the desktop, edge to edge, like the menu
  bar. It does not stay behind over the full-screen app, and nothing pops in
  after the slide has finished.
- ☑ In the full-screen app, push the pointer to the top of the screen: the
  island comes down together with the menu bar, and goes back up with it.
- ☑ Swipe back to the desktop: the island arrives with the desktop. It does
  not disappear first and come back afterwards.
- ☑ With a full-screen app in front, send the `PermissionRequest` from section
  5: the island drops in over the app, and leaves again once decided.
- ☐ Settings → Island → Full-screen apps → **Always show**: the island stays
  at the top of a full-screen app. **Never**: it is not shown there at all,
  not even for a request, if "Come in over a full-screen app…" is off.
- ☐ Mission Control (three-finger swipe up): the island stays where it is and
  does not turn into a window thumbnail.
- ☐ System Settings → Control Centre → "Automatically hide and show the menu
  bar" set to *Always* or *On Desktop Only*: on the desktop the island follows
  the menu bar up and down. **(never tried)**
- ☐ The same setting at *Never*: in a full-screen app the menu bar stays, and
  so does the island. **(never tried)**
- ☐ A MacBook's built-in display with a camera housing. **(never tried)**
- ☐ Two displays, one of them showing a full-screen app: the island on the
  other display is not affected. **(never tried)**

## 3. The welcome

Start once more with a fresh throwaway directory and without
`-NikoOnboardingDisabled`:

```bash
NIKO_ISLAND_HOME=/private/tmp/nk-welcome/ni "dist/Niko Island.app/Contents/MacOS/niko-island"
```

- ☑ A full-screen welcome covers the display: night sky with an aurora, sea,
  the creatures, and a small island at the top that says hello. The name
  arrives letter by letter and the creatures hop in one after another.
- ☑ On a large display the content is larger **and sharp**: look at the small
  type at the display's own resolution (0.3.0 magnified a small layout, which
  made it soft).
- ☐ Creatures crossing the scene face the way they move (in 0.3.0 the whale
  swam backwards). Move the pointer: stars and water shift a little, and
  specks in the water light up near it.
- ☐ A ring of light runs out from the island as it lands; connecting agents
  and reaching the last page throw confetti from the island.
- ☑ "Get started" → the agents found on this Mac, with *running now* next to
  the ones whose app or CLI is running, and a tick on every stable or beta
  adapter. Experimental ones are listed without a tick.
- ☐ **Not now** and **Skip** leave every config untouched (check with
  `niko-island status`).
- ☐ **Connect n agents** writes the hooks (in this throwaway launch they point
  into `/private/tmp`, so run `niko-island uninstall` afterwards, or do this
  step with the installed app in section 10).
- ☐ The remaining pages: a short tour with a demo island, a few preferences
  (colour, sounds, full-screen apps), done. The welcome does not come back at the next
  launch; Settings → About → "Show it again" brings it back.
- ☐ Escape closes it at any point.

## 4. Sessions without hooks

Uses your real session logs, read-only. Nothing needs to be connected.

- ☑ With the Claude desktop app's Code tab or `claude` in a terminal open on a
  session: a row appears within a few seconds, titled like the session, with
  what it last did.
- ☑ With the Codex desktop app or `codex` open: the same, with a whale; a
  session that started helper agents shows "n helpers".
- ☑ With the ZCode desktop app open on a session, including one that was open
  before ZCode was connected: a row with a crab, the session's title, what it
  last did and its last reply. A session started without a project shows no
  project name rather than ZCode's scratch folder.
- ☑ A row found in a desktop app carries a "Desktop" chip. ☐ Clicking it
  brings that app forward.
- ☐ A session nobody has touched for longer than Settings → Sessions → "Keep a
  quiet session listed for" drops off the list.
- ☐ Dismiss a row (right-click → Dismiss): it stays away until that session
  does something new.
- ☐ Settings → Sessions → switch off "Find sessions by reading the agents' own
  session logs": only sessions that fire hooks remain.
- ☐ Such a row never shows Allow / Deny: there is nothing to answer until the
  agent is connected.

## 5. Sessions and approvals with a fake agent

In another terminal, drive the bundled bridge by hand:

```bash
export NIKO_ISLAND_HOME=/private/tmp/nk-manual/ni
B="dist/Niko Island.app/Contents/Helpers/niko-bridge"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"'$PWD'","prompt":"try the island"}' | "$B" --source claude
echo '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"make test"}}' | "$B" --source claude
```

- ☑ The collapsed tab shows a starfish and "running make test".
- ☑ Open the island: one row with the starfish, the project name, "try the
  island", the activity line, and chips for elapsed time and "Claude Code" (plus
  the terminal's name when the bridge was started from a terminal it knows).

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"git push"}}' | "$B" --source claude
```

- ☑ The island opens by itself with the request on top: the command in a box
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

## 6. Usage and limits

Click the bars icon in the island's header.

- ☑ A row of pills: All, then one per agent that has written anything on this
  Mac (Claude Code, Codex, ZCode, …). The tiles, the chart and the model list
  follow the pill.
- ☑ Four tiles: 5 hours, Today, 7 days, 30 days. A model with no list price
  (GLM on a Coding Plan) shows its tokens, not "$0.00".
- ☑ ZCode: a line saying its limits are kept on its servers, "Show them…"
  (opens Settings → Usage) and "Reset in ZCode…". ☐ That button brings ZCode
  to the front and does nothing else.
- ☐ Codex: the windows it reports appear with the plan name, from its session
  files.
- ☐ Claude Code in a terminal: a 5-hour and a weekly bar appear once a
  connected session has drawn its status line.
- ☐ Claude Code turned away at a limit (the transcript gets a "usage limit
  reached" entry): the row says "hit its limit" and the usage view shows that
  window full, with the time it opens again. It disappears at that time.
- ☐ Compare today's total for Claude Code with `niko-island usage`.

Asking the provider (Settings → Usage → "Limits the provider keeps"). Both
switches are off on a fresh install; **check that first**, and that nothing is
asked while they are off (no `provider-limits.json` appears in
`~/.niko-island/cache/`).

- ☐ **Ask Anthropic**, with Claude Code signed in and used in a terminal
  recently: within a few seconds the Claude tab shows a 5-hour and a weekly
  percentage, "asked just now". macOS may ask for access to "Claude
  Code-credentials"; "Deny" turns into a line saying so, and is not asked
  again until you press "Check now". **(the answer path has only been
  exercised with the format Claude Code caches, never with a live answer)**
- ☑ The same switch with a sign-in that has run out (desktop app only): the
  note says the sign-in has run out; nothing is sent. *(checked with the
  hidden `niko-island internal limits claude`, which prints states and
  percentages only)*
- ☐ **Ask BigModel / Z.ai**: paste a key of your Coding Plan, Save. The key
  field turns into "A key is saved in your Keychain"; the ZCode tab shows the
  plan's 5-hour and weekly percentages. "Remove" deletes the key and switches
  the lookup off. A wrong key says "The key was not accepted."
  **(never run against the live service)**
- ☐ With either switch on, quit and reopen: the last answer is shown at once,
  then replaced.
- ☐ `~/.niko-island/cache/provider-limits.json` holds percentages and times;
  search it for your key or sign-in: nothing.

## 7. Sounds **(not automated beyond synthesis and settings)**

Settings → Sounds. Nobody has listened to the built-in sets yet, so this section
is also a listening test: note anything harsh, too long or too quiet.

- ☐ "Play sounds" is off on first launch and nothing in section 5 made a sound.
- ☐ Switch it on. The play button next to each of the five moments plays it.
  "Work started" is the only moment that is off.
- ☐ Island set: soft mallet tones, each under about a second. 8-bit set: short
  square-wave arpeggios. Both sit at a similar loudness.
- ☐ The volume slider changes the level of the next preview.
- ☐ macOS: each moment gets a menu of system sounds, and previews play them.
- ☐ Repeat the `PermissionRequest` and `Stop` commands from section 5: "Needs
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

## 8. Settings window

- ☑ The gear on the island and "Settings…" in the menu both open one window
  with General, Island, Sessions, Agents, Sounds, Usage, About in a sidebar.
- ☐ General → Language: switching between English, 简体中文 and "Same as macOS"
  changes the window and the island at once, without a restart.
- ☐ Island → Look: each colour, width, row density and chip switch changes the
  island straight away; "Pixel creatures" off turns them into coloured dots.
- ☐ Island → the two hover delays and "How long the notice stays" do what they
  say. With the default ("Short") the island is gone about a sixth of a second
  after the pointer has left it.
- ☐ Island → Text size: Small, Regular and Large change the type in the island
  at once; nothing is clipped at Large with the Compact width.
- ☐ Island → "How fast it opens and closes": Calm, Standard, Brisk. Closing is
  always a little quicker than opening.
- ☐ Agents → pick a different creature for an agent: its rows change.
- ☐ Agents → "Connect all" appears when a detected agent is not connected.
- ☐ Island → switch off "Open when the pointer rests on it": hovering no longer
  opens it, clicking still does.
- ☐ Island → switch off "Open by itself when an agent needs a decision": a
  request leaves the island closed; the tab shows the bell.
- ☐ Island → switch off "Keep the island visible when nothing is running": with
  no sessions the tab disappears, and comes back with the first event.
- ☐ General → "Open Niko Island at login" registers the app (works only from
  the bundled app, ideally in /Applications). **(not automated)**
- ☐ About → "Export diagnostics" writes a report and shows its path.

## 9. Notifications and jump-back **(not automated)**

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

## 10. Real agents

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

Codex and ZCode (beta). **None of this has been done with the live agents.**

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" install --dry-run --agents codex,zcode
"dist/Niko Island.app/Contents/MacOS/niko-island" install --agents codex,zcode
```

- ☐ `~/.codex/hooks.json` and `~/.zcode/cli/config.json` gained `niko-bridge`
  entries next to whatever was there; backups sit beside them.
- ☐ Codex: type `/hooks` and trust the new entries. Start a turn: the row
  follows it. Trigger an approval: decide on the island; Codex continues.
- ☐ ZCode: start a new session (open ones keep their old hooks). The row
  follows it; an approval can be decided on the island.
- ☐ With the app not running, both agents behave exactly as before.
- ☐ Any other beta agent you use (Cursor, Windsurf, Gemini CLI, Trae, Qwen
  Code, CodeBuddy, Factory, Grok CLI): after `install --agents <id>` its
  sessions show up with live status, and the agent shows no hook errors.

```bash
"dist/Niko Island.app/Contents/MacOS/niko-island" uninstall
```

- ☐ `diff` against the backup shows `settings.json` is back to what it was.
- ☐ `claude` still works. Delete the app; it still works.

## 11. Release artifact

- ☐ Download the `.dmg` for that Mac (`apple-silicon` or `intel`) from the
  Releases page on another Mac **with a browser**
  (so it carries the quarantine flag), open it, drag the app onto Applications,
  run `xattr -cr "/Applications/Niko Island.app"` (or: right-click → Open on
  macOS 14; System Settings → Privacy & Security → Open Anyway on macOS 15+),
  confirm it launches. **(not automated: CI fetches files without the flag)**
- ☐ The image shows the app, an Applications shortcut and "Read me first.txt",
  and the note reads correctly in English and Chinese.
- ☐ Repeat with the `.zip`.
- ☐ Before clearing the flag, `niko-island doctor` reports the bridge as
  quarantined and Settings → Agents shows the same warning; after clearing,
  both are gone. **(not automated beyond the detection itself)**
- ☐ `lipo -archs "Niko Island.app/Contents/MacOS/niko-island"` → `arm64` for
  the apple-silicon download, `x86_64` for the intel one. Never both.
- ☐ The intel download on a real Intel Mac. **(never tried: it has only run
  under Rosetta)**
- ☐ `shasum -a 256 -c SHA256SUMS` passes.

# Manual test plan

Automated tests (`scripts/check.sh`) cover the protocol, the bridge, the
installer, session discovery, the menu-bar placement rules, the sound engine
and the app model end to end. This page lists what still needs a human with a
screen and ears: the island window, full-screen apps, sounds, notifications,
and real agents. Nothing here touches your real agent configuration until
section 10.

Legend: ☐ = check by hand. ☑ = checked by hand for 0.3.0 to 0.8.0, on one
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

Before every release, run the app once **with notifications on** (no
`-NikoNotificationsDisabled`) and let it show a banner or two: 0.8.0 quit at
its first notification, a path every scripted run had switched off.

- ☑ 0.8.1: a development build with notifications on, three rounds of
  sessions, permission requests that time out, questions, failures, ⌃⌥J and
  ⌃⌥I, a stand-in lock and Claude Code looking for itself: still running, no
  crash report.

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

- ☐ After `Stop` (no closing words came with it, and there is no transcript),
  the collapsed tab names the session as finished for a few seconds, then
  returns to its usual text.
- ☐ After `StopFailure`, the row reads "hit an error" with the message, and a
  card in the error's colour comes down with it.

The card, the list of steps, the keys:

```bash
S='"session_id":"t2","cwd":"'$PWD'"'
echo '{"hook_event_name":"UserPromptSubmit",'$S',"prompt":"fix the flaky test"}' | "$B" --source claude
echo '{"hook_event_name":"PreToolUse",'$S',"tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Find the race","activeForm":"Finding the race","status":"completed"},{"content":"Add a backoff","activeForm":"Adding a backoff","status":"in_progress"},{"content":"Run the tests","activeForm":"Running the tests","status":"pending"}]}}' | "$B" --source claude
echo '{"hook_event_name":"Stop",'$S',"last_assistant_message":"Fixed. The retry now waits, with a **250 ms backoff**.\n\nAll tests pass."}' | "$B" --source claude
```

- ☑ After the second line, the open island shows the row with a thin bar,
  "1/3" and "Adding a backoff"; next to the project's name is the branch of
  the folder you ran this in.
- ☑ After the third line, with the island closed, a card comes down: "Finished",
  the project and the prompt, the reply with "250 ms backoff" in bold, the
  bar, and "Click to go to the session". Nothing else on screen loses focus.
- ☐ Rest the pointer on the card: it stays. Move away: it leaves after about
  ten seconds. The ✕ puts it away at once; so does opening the island.
- ☐ Click the card: the session's terminal comes forward.
- ☐ Send the first line again while a card is showing: the card goes.
- ☐ Settings → Island → *When an agent finishes* → Notice: the same three
  lines end in the one-line notice instead. → Nothing: in nothing.
- ☐ With the session's own terminal tab in front, the third line shows the
  notice, not the card. **(not automated beyond the rule)**
- ☐ Lock the screen, send the three lines, unlock: no sound was played and no
  card is waiting. **(a real lock was not tried; the rule is tested)**
- ☑ Settings → General → *Allow with ⌃⌥A, deny with ⌃⌥D*, then send the
  `PermissionRequest` from above: the buttons show the keys next to their
  names; ⌃⌥A prints `"behavior":"allow"`, and for a second request ⌃⌥D prints
  `"behavior":"deny"`.
- ☐ With "Open by itself when an agent needs a decision" off, the first ⌃⌥A
  only opens the island; the second allows.
- ☐ With the `AskUserQuestion` request from above, neither key does anything.
- ☐ With nothing waiting, ⌃⌥A and ⌃⌥D reach the app in front as usual.
- ☐ Settings → General → *Remind me about a request left waiting* → After
  2 min, sounds on: leave a request alone; its cue plays again after two
  minutes, at most three times. **(a real wait was not sat through)**

Back at the screen, the phone, quiet hours, the list (0.6.0):

- ☑ Start the app with `-NikoAwayFor 8` (a stand-in for a locked screen), send
  two finished turns inside those eight seconds: nothing shows; after them one
  card "While you were away · 2 finished" with a line per session. ☐ The same
  with a real lock. ☐ A click on a line goes to that session.
- ☑ Settings → Sessions → *Arrange the list* → By project: headings with the
  project's name and a count; rows under them drop the project's name.
  ☐ By agent.
- ☐ Settings → General → *Quiet hours* from now until an hour from now, sounds
  on: a finished turn makes no sound; switch it off and it does.
- ☑ `NIKO_PUSH_KEY=x niko-island internal push bark http://127.0.0.1:<port>`
  against a server of your own on this Mac: one POST to `/push` with
  `device_key`, `title`, `body` as JSON. `… push ntfy …`: one POST to `/` with
  `topic`, `title`, `message`. `… push bark http://example.org`: refused.
- ☑ `NIKO_PUSH_KEY=<a long random topic> niko-island internal push ntfy ""`,
  then `curl -s "https://ntfy.sh/<that topic>/json?poll=1"`: the line that was
  sent comes back from the real service.
- ☐ Settings → General → *A line to your phone*: paste a real Bark key or ntfy
  topic, *Send a test*: the phone shows "Niko Island" and one line; the note
  says the server accepted it. A wrong key says the server said no.
  **(never sent through the real services)**
- ☐ With it on, lock the screen and let an agent ask for a decision: the phone
  shows the agent, the project and "Needs your decision", not the command.
  With *Say what it is about* on, the command is there too.
- ☑ Settings → Sessions → *Reply from the island*, and a session whose bridge
  ran inside tmux: the card and the row get a line "Reply…". ☐ In a real tmux
  pane with the agent waiting: what is typed arrives in the agent and the row
  goes back to work. ☐ With the agent gone and the shell back at the prompt:
  "Not sent", and nothing arrives in the shell. ☐ The same two checks in
  iTerm2 and in Terminal (macOS asks for permission to control them first).
  **(never run against a real terminal)**

Seeing an edit, the jump key, the context chip (0.7.0):

```bash
echo '{"hook_event_name":"PermissionRequest","session_id":"t1","cwd":"'$PWD'","tool_name":"Edit","tool_input":{"file_path":"'$PWD'/a.swift","old_string":"let retries = 3","new_string":"let retries = 5\nlet backoff = 0.25"}}' | "$B" --source claude
```

- ☐ Under the path: one red line with "let retries = 3", two green lines with
  what replaces it. A `Write` with `content` shows its first six lines and
  "and N more lines".
- ☐ Settings → General → *Go to what needs me with ⌃⌥J*: with a request
  waiting and the island closed, the key opens it on that request; with none,
  it brings the session that stopped last to the front.
- ☐ Settings → Island → *Show how full the context is*: Codex rows show a
  percentage, Claude Code rows a size; a Codex session above 85 % shows the
  chip in amber without the switch.

A limit that resets, what a session has used (0.8.0):

- ☐ With a Claude Code window at 100 % (the usage view shows it in red with a
  reset time), wait for that time: within a few seconds the closed island says
  "Claude Code's limit has reset" for a moment, the "finished" cue plays if
  sounds are on, and nothing more is said about it. **(tested with a stand-in
  clock; a real window was not waited out)**
- ☐ Settings → Island → *Show what the session has used*: rows of sessions
  that have used anything in the last two days show "$1.24", or tokens for a
  model without a list price.

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
- ☑ `niko-island internal limits claude-cache` prints the windows Claude Code
  last kept in `~/.claude.json` and which of them have not reset yet; no
  sign-in is read. ☐ With a recent one, the Claude tab shows it as "as Claude
  Code last saw them, … ago".
- ☐ Claude Code turned away at a limit (the transcript gets a "usage limit
  reached" entry): the row says "hit its limit" and the usage view shows that
  window full, with the time it opens again. It disappears at that time.
- ☐ Compare today's total for Claude Code with `niko-island usage`.

Asking the provider (Settings → Usage → "Limits the provider keeps"). All three
switches are off on a fresh install; **check that first**, and that nothing is
asked while they are off (no `provider-limits.json` appears in
`~/.niko-island/cache/`).

- ☑ **Let Claude Code look up my Claude limits**: within about ten seconds the
  Claude tab shows a 5-hour and a weekly bar with reset times and "as Claude
  Code last saw them, just now". No Keychain question appears, no new session
  shows up on the island, and `~/.claude/projects/` gains no transcript (only
  an empty folder for the app's own working directory). ☐ On a Mac where
  Claude Code never signed in: the note says to run `claude` once.
- ☐ **Ask Anthropic**, with Claude Code signed in and used in a terminal
  recently: within a few seconds the Claude tab shows a 5-hour and a weekly
  percentage, "asked just now". macOS may ask for access to "Claude
  Code-credentials"; "Deny" turns into a line saying so, and is not asked
  again until you press "Check now". **(the answer path has only been
  exercised with the format Claude Code caches, never with a live answer)**
- ☑ The same switch with a sign-in that has run out (desktop app only): it is
  offered to Anthropic once, turned down, and the note says the sign-in has
  run out; the same sign-in is not sent again. *(checked with the hidden
  `niko-island internal limits claude`, which prints states and percentages
  only)*
- ☐ With a plan that has a weekly window per model: rows "Weekly, Opus" and
  the like appear under the two main bars; "Extra usage" only if the account
  has it switched on. **(written against the answer format open-source tools
  document; not seen live)**
- ☑ **Ask OpenAI**, with Codex signed in to a ChatGPT plan: the Codex tab says
  "asked just now", shows the plan and its windows, and a chip "N resets
  saved" when the account has any. *(answered live on one machine: a weekly
  window, the plan, no saved resets)* ☐ With an account that has saved
  resets, the chip shows their number.
- ☐ Sign Codex out (or use an API key): the note says there is no ChatGPT
  plan signed in on this Mac, and nothing is sent.
- ☐ **Ask BigModel / Z.ai**: paste a key of your Coding Plan, Save. The key
  field turns into "A key is saved in your Keychain"; the ZCode tab shows the
  plan's 5-hour and weekly percentages. "Remove" deletes the key and switches
  the lookup off. A wrong key says "The key was not accepted."
  **(never run against the live service)**
- ☐ With any of the switches on, quit and reopen: the last answer is shown at once,
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
- ☐ Island → Theme: Classic, Glass, Pixel, Midnight each change the open
  island at once. Glass shows the desktop blurred behind it; Pixel has square
  corners, square chips and monospaced type. On a display with a camera
  housing the closed island stays black in every theme.
- ☑ A session whose agent exits without a word leaves the list: a stand-in
  agent (a python process running the bridge as a hook would) was killed with
  `kill -9`; its row was gone within 20 s (0.9.1, development build,
  notifications on). A session found on disk for a desktop app that is not
  running (Kiro) went the same way.
- ☐ Agents: a connected agent says "last event …" once its hooks have fired,
  and "no event since Niko Island started" before that.
- ☐ About → "Tell me when there is a new version": with an older build, the
  status row says which version is out and the island's header shows a chip;
  "Install and restart" downloads, checks and replaces the app (old one in the
  Trash) and the new version starts. **(not run against /Applications)**

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

Done once for 0.6.0, without touching the real configuration: Claude Code
2.1.295, headless, in an empty folder, with `--settings` naming a temporary
hook file that points at a development build's bridge
(`claude -p "…" --settings <file> --allowedTools TodoWrite`).

- ☑ `Stop` carries `last_assistant_message`; the card showed that sentence
  with its bold drawn as bold.
- ☑ The agent kept its list with `TaskCreate` / `TaskUpdate`; the files under
  `~/.claude/tasks/<session id>/` were read and the card showed 1/3.
- ☑ An interactive session (`claude --permission-mode default`, in a terminal
  of its own, same temporary hook file) asked to write a file: the island
  opened with "Claude Code wants to edit approved.txt" and the path; the file
  did not exist; ⌃⌥A; the file existed. (In that account's usual mode Claude
  Code ran the same write without asking anybody, so there was nothing to
  approve: the island only sees requests the agent actually makes.)
- ☐ The same with Terminal.app, iTerm2 and the Claude desktop app in front,
  and with the banner's *Allow once* / *Deny*.

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

Added in 0.9.0 (beta: Copilot CLI, Qoder, Qoder CN, Kimi Code, Devin;
experimental: QoderWork, Kiro, MiniMax Code, Amp). **None of these has been
run against the live agent.**

- ☐ Kimi Code: `install --agents kimi`; `~/.kimi-code/config.toml` ends with
  one block between `# >>> niko-island` and `# <<< niko-island`; `kimi` starts
  without a config error; a session shows up and a permission prompt shows as
  "needs permission" (answered in Kimi Code). `uninstall` leaves the file as
  it was.
- ☐ Devin: a permission request decided on the island is honoured
  (`{"decision":"approve"}` / block). With Devin's own hooks connected, the
  hooks it borrows from Claude Code's settings do not show a second session.
- ☐ Copilot CLI: `~/.copilot/hooks/niko.json`; a session shows up with live
  status; tool calls are never held up.
- ☐ Kiro CLI 3: `~/.kiro/hooks/niko.json` runs in a workspace without
  `--agent`; an older `~/.kiro/settings/cli.json` lost only our entries.
- ☐ MiniMax Code: the plugin pack is picked up by `mcode` at the next session.
- ☐ Amp: after reloading plugins, a thread shows up with its last tool and
  its reply at the end of a turn.
- ☐ Qoder / Qoder CN / QoderWork: a session shows up with live status.

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

# niko-island — Agent Integration Matrix

Public, stable facts about where each agent accepts hooks/plugins.
Registration payloads follow each vendor's documented format; we always tag our
commands with `niko-bridge` so installs are identifiable and reversible.
Ship v1 with the first three; the rest are additive and follow the same pattern.

| Agent | Config path (HOME-relative) | Mechanism | Notes |
|---|---|---|---|
| Claude Code | `.claude/settings.json` → `hooks` | command hooks on all events; `statusLine.command` | matcher `*`; PermissionRequest entry gets `"timeout": 86400`; PreCompact/PostCompact matcher `manual\|auto`; wrap command in `/bin/sh -c '[ -x ... ] && ... ; exit 0'` |
| Claude (statusline) | same file → `statusLine` | our bash script | preserves user section on rewrite |
| Codex CLI | `.codex/hooks.json` | same JSON shape as Claude hooks | also respects `.codex/config.toml` (never rewrite user content; only append our hook file reference if supported) |
| Cursor CLI | `.cursor/hooks.json` | same shape | |
| Copilot CLI | `.copilot/hooks/niko.json` + `.copilot/settings.json` | self-contained hook file preferred | |
| Gemini CLI | `.gemini/config/plugins/niko/hooks.json` + `plugin.json` | plugin dir | |
| Grok CLI | `.grok/hooks/niko.json` | self-contained hook file | |
| Trae | `.trae/hooks.json` (+ `.trae-cn/` variant) | same shape | |
| Windsurf | `.codeium/windsurf/hooks.json` | same shape | |
| OpenCode | `.config/opencode/plugins/niko.js` (+ `.ts`) | in-process JS plugin → HTTP ingress | plugin receives `{client, directory}`; posts events, handles permission replies |
| MiMoCode | `.config/mimocode/plugins/niko.js` | same as OpenCode | |
| Qwen / QwenWork | `.qwen/settings.json`, `.qwenwork/settings.json` | settings hook | |
| Kimi Code | `.kimi/config.toml`, `.kimi-code/config.toml` | toml hook entry | |
| DeepSeek CLI | `.deepseek/config.toml` | toml hook entry | |
| Kiro | `.kiro/settings/cli.json` | settings hook | |
| Droid (dsh) | `.dsh/profiles/web/cordis.patch.yml` + plugin | YAML patch + JS worker | worker registers on unix socket with focus/visibility protocol |
| Pi / OhMyPi | `.pi/` extensions + `~/.omp/agent/extensions/` symlink | JS extension | |
| OpenClaw | `.openclaw/` plugin dir | JS plugin | |
| Factory / Droid / Amp / custom | `.factory/settings.json`, `.dsh`, `.amp` | settings-style hooks | treat via generic settings-adapter |

## As implemented in 0.3.0

The table above is the plan this project started from. Where the agents' own
hook references turned out to say something else, the adapters follow the
reference; `HookDialect` in `Sources/NikoCore/Installer/HookMerge.swift` and
`AgentRegistry` are the source of truth. "Groups" is Claude's shape (see the
next section); "flat" is a plain list of entries per event.

| Agent | File | Shape | Notes |
|---|---|---|---|
| Claude Code | `.claude/settings.json` → `hooks` | groups, `matcher: "*"`, timeout in seconds | 12 events; status line wrapper |
| Codex | `.codex/hooks.json` → `hooks` | groups without a matcher | a permission reply carries the decision only (no `updatedInput`, no `interrupt`); Codex runs a new hook after the user trusts it with `/hooks` |
| ZCode | `.zcode/cli/config.json` → `hooks.events`, with `hooks.enabled: true` | groups, `matcher: ".*"`, `timeoutMs`, `async: false` | read when a session starts |
| Cursor | `.cursor/hooks.json`, `version: 1` | flat, entries are `{ "command": …, "timeout": … }` | observing events only (`beforeSubmitPrompt`, `afterFileEdit`, `stop`, …); nothing that could block the agent |
| Windsurf | `.codeium/windsurf/hooks.json` | flat, `show_output: false`, no timeout | `pre_` / `post_` events; payload names the event in `agent_action_name` |
| Gemini CLI | `.gemini/settings.json` → `hooks` | groups, timeout in milliseconds, entries carry a `name` | `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`, …; 0.2.0's plugin directory is removed on install |
| Trae | `.trae/hooks.json` (+ `.trae-cn/`), `version: 1` | groups | |
| Qwen Code, CodeBuddy, Factory | `<dir>/settings.json` → `hooks` | groups | |
| Grok CLI, Copilot CLI | `<dir>/hooks/niko.json` | a file of our own, groups | |
| OpenCode, MiMoCode | `.config/<name>/plugins/niko.js` | JS plugin → loopback HTTP | |

Added in 0.9.0 (formats from each agent's hook reference; where that is thin,
from the registrations CodeIsland and open-vibe-island ship and keep working):

| Agent | File | Shape | Notes |
|---|---|---|---|
| Copilot CLI | `.copilot/hooks/niko.json` (any `*.json` in that folder is read) | `{ "version": 1, "hooks": { Event: [{ "type": "command", "bash": …, "timeoutSec": n }] } }` | Claude's event names (`PreToolUse`, …) select Claude-shaped payloads (`hook_event_name`, `session_id`, `tool_name`, `tool_input`); its own camelCase format (`sessionId`, `toolName`, `toolArgs` as JSON text) is read too. Every command carries `--event <name>` for payloads that do not name it. Tool hooks fail closed on a non-zero exit: ours always exits 0. Copilot CLI also reads Claude Code's hooks (below) |
| Qoder, Qoder CN, QoderWork | `.qoder/settings.json`, `.qoder-cn/settings.json`, `.qoderwork/settings.json` | Claude's groups | the events CodeIsland registers; the approval hook is only watched (`--observe`) |
| Kimi Code | `.kimi-code/config.toml` | `[[hooks]]` tables with exactly `event`, `matcher`, `command`, `timeout` (1–600 s); any other key, or an event outside its list of twenty, stops the whole config from loading | ours sit in one block between `# >>> niko-island (niko-bridge)` and `# <<< niko-island (niko-bridge)` at the end of the file; a root-level `hooks` key or `[hooks]` table makes the installer leave the file alone. `PermissionRequest` only watches (the agent waits for it before asking): `--observe` |
| Devin | `.config/devin/config.json` → `hooks` | Claude's groups, no matcher (every tool), timeout in seconds | a permission request is answered with `{"decision": "approve"}` or `{"decision": "block", "reason": …}` and exit 2 (`--reply devin`). Devin also runs the hooks in Claude Code's settings by default (`read_config_from.claude`) |
| Kiro (CLI 3 and the IDE) | `.kiro/hooks/niko.json` | `{ "version": "v1", "hooks": [{ "name", "trigger", "action": { "type": "command", "command" }, "timeout", "enabled" }] }` | global hook files run in every workspace; 0.8 and earlier wrote Claude-shaped entries into `.kiro/settings/cli.json`, which are taken out again |
| MiniMax Code (`mcode`) | `.minimax/plugins/niko/.claude-plugin/plugin.json` + `hooks/hooks.json` | a plugin pack laid out as Claude Code plugins are | hook timeouts must be whole seconds from 1 to 10 or the handler is dropped, so the approval hook only watches; installed only where `~/.minimax` exists |
| Amp | `.config/amp/plugins/niko.ts` | `export default function (amp) { amp.on(…) }`, run by Bun | `session.start`, `agent.start`, `tool.result`, `agent.end` → loopback HTTP; it never subscribes to `tool.call`, so it cannot stand between Amp and a tool. Amp's plugin API is experimental |

**Hooks that run in more than one agent.** Devin and Copilot CLI also run
the hooks in Claude Code's settings. The bridge looks up its own process
ancestry (executable names, and for a `node` / `bun` host the script path of
its command line, never the environment): an event that arrives as Claude
Code's from inside one of them is relabelled as that agent's, or dropped when
that agent's own hooks of ours are installed, so nothing is counted twice.
Claude Code itself is recognised in the chain and wins.

**Watching instead of deciding** (`--observe`): a `PermissionRequest` is
forwarded as a `Notification` with `notification_type: "permission_prompt"`
and the bridge returns at once. The island shows "needs permission"; the
agent asks in its own window as it always does.

Event names are translated to the canonical (Claude) names by
`EventDialect.normalize`; the original name is kept in `native_event`. The
adapter's identity travels in `_niko.source`, never in a top-level `source`
field, because some agents use that name for something else (a session start
reports `"source": "startup"`).

Sessions of Claude Code and Codex are also read from their session logs
(`.claude/projects/<project>/<session>.jsonl`,
`.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`), and ZCode's from its database
(`.zcode/cli/db/db.sqlite`: `session`, `message`, `part`; the desktop app's
task list is `.zcode/v2/tasks-index.sqlite`), all read-only. None of that needs
registration. See `Sources/NikoCore/Scout/`.

Seen from a real Claude Code (2.1.295, headless run, 0.6.0): every hook input
carries `session_id`, `transcript_path`, `cwd`, `hook_event_name`,
`scratchpad_dir`, and from the first prompt on `prompt_id`, `permission_mode`
and `effort`; `Stop` adds `last_assistant_message`, `stop_hook_active`,
`background_tasks` and `session_crons`; `PostToolUse` adds `tool_response` and
`duration_ms`. The agent keeps its list of steps with `TaskCreate {subject,
description}` and `TaskUpdate {taskId, status}`, one file per task in
`~/.claude/tasks/<session id>/<n>.json` (`id`, `subject`, `description`,
`status`, `blocks`, `blockedBy`), next to a `.lock` and a `.highwatermark`.

Limits of a plan (0.4.0, extended in 0.5.0 and 0.6.0: Claude Code's own cached
answer in `~/.claude.json`, key `cachedUsageUtilization`) come from, in this order of trust: files the agent
writes (Codex rollouts: `rate_limits`), Claude Code's status line, Claude
Code's transcript when a request is refused (`apiErrorParams.rate_limit_info`),
and, only when the user switches it on, the provider:

| Provider | Request | Credential | Answer |
|---|---|---|---|
| Anthropic | `GET https://api.anthropic.com/api/oauth/usage`, `anthropic-beta: oauth-2025-04-20` | Claude Code's own sign-in from the Keychain item `Claude Code-credentials` (or `~/.claude/.credentials.json`), read at call time, never renewed | `five_hour` / `seven_day` (and other named windows) with `utilization` and `resets_at`; a `limits` list, in which `kind: weekly_scoped` carries a week per model (`scope.model.display_name`); `extra_usage` |
| BigModel / Z.ai (GLM Coding Plan) | `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit` or `https://api.z.ai/…` | a key the user pastes, kept in the Keychain under this app's name | `data.limits[]` with `type`, `unit` (3 = hours, 6 = the week), `number`, `percentage`, `nextResetTime`; `data.level` |
| OpenAI (a ChatGPT plan used by Codex, 0.5.0) | `GET https://chatgpt.com/backend-api/wham/usage` and `…/wham/rate-limit-reset-credits`, `ChatGPT-Account-Id` | Codex's own sign-in from `~/.codex/auth.json` (`auth_mode: chatgpt`), or the Keychain item `Codex Auth` when Codex keeps it there; read at call time, never renewed | `rate_limit.primary_window` / `secondary_window` with `used_percent`, `limit_window_seconds`, `reset_at`; `plan_type`; saved resets as `credits[]` with `status` and `expires_at` |

| Kimi (Kimi Code plan, 0.9.0) | `GET https://api.kimi.com/coding/v1/usages`, `Bearer` | a key the user pastes, in the Keychain | `limits[].detail` (`limit`, `remaining`, `resetTime`; `window.duration` / `timeUnit`, five hours when absent) and `usage` for the week; numbers may come as text |
| MiniMax (Coding Plan, 0.9.0) | `GET https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains` (or `api.minimax.io`), `Bearer` | a key the user pastes, in the Keychain | `base_resp.status_code` 0, then `model_remains[]` where `model_name` is `general`: `current_interval_remaining_percent` + `end_time`, and the week only when `current_weekly_status` is 1 |
| Google (Gemini CLI, 0.9.0) | `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`, then `…:retrieveUserQuota` with the project | Gemini CLI's own sign-in from `~/.gemini/oauth_creds.json` or the Keychain item `gemini-cli-oauth`, used only while unexpired and never renewed | `cloudaicompanionProject` (text or `{id}`), `currentTier.name`; `buckets[]` with `modelId`, `remainingFraction`, `resetTime`, grouped into Pro / Flash / Flash-Lite by the bucket with least left |

None of these endpoints is documented by its provider; the shapes are the ones several open-source tools read, and the OpenAI one was answered live once. See
`Sources/NikoCore/Usage/ProviderLookups.swift`. ZCode's own stored sign-in is
encrypted by ZCode and is not read.

## Generic settings-adapter pattern

Most settings-JSON agents share this shape; one adapter covers them:
`{ "hooks": { "<Event>": [ { "matcher": "*", "hooks": [ { "type": "command",
"command": "<shim>", "timeout"?: n } ] } ] } }` — merge by event key, never
drop foreign entries, tag ours with the `niko-bridge` substring.

## Event translation rules (adapter → canonical)

- Claude-family: pass-through (canonical dialect IS Claude's)
- OpenCode-family JS: `permission.requested` → `PermissionRequest` (+ keep
  request id in `tool_input._request_id`); `permission.replied`/`question.replied`
  → `PostToolUse`; `question.asked` → `PermissionRequest` with
  `tool_name:"AskUserQuestion"`, `tool_input.questions[{text, options[],
  multiSelect}]`; on reply, send `updatedInput.answers[]`
- Codex: rollout/session file events → SessionStart/Stop/PostToolUse synthesis
- Unknown agents: emit `Notification` + best-effort fields

## Terminal jump-back (notifications)

AppleScript (`osascript`):
- iTerm2: select window/tab/session by `ITERM_SESSION_ID` env of the originating
  process (read at event time via `ps`/proc info), `select session` /
  `create window with tab` fallback; tmux sessions via `run_command "attach"`
- Terminal.app: `activate` + `set selected tab` matched by tty
Requires `com.apple.security.automation.apple-events` usage description in
Info.plist; unsigned apps get the standard TCC prompt at runtime.

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

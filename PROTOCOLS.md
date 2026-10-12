# niko-island — Protocol Specifications

All protocols below are the project's own contracts. External schemas we adopt
(Claude Code hook schema) are publicly documented by Anthropic; per-agent config
locations are public facts documented by each tool.

## 1. Canonical event schema

Every agent event is normalized to this JSON (Claude Code hook dialect):

```json
{
  "source": "claude",                      // adapter id: claude|codex|cursor|gemini|opencode|...
  "hook_event_name": "PreToolUse",         // see §1.1
  "session_id": "uuid",                    // stable per session
  "transcript_path": "/abs/path.jsonl",    // optional
  "cwd": "/abs/dir",
  "tool_name": "Bash",
  "tool_input": { },                       // object
  "ts": 1760000000000                      // adapter-local ms timestamp
}
```

### 1.1 Event names
`SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse,
Notification, Stop, SubagentStop, PreCompact` — plus the permission extension
`PermissionRequest` (payload identical to PreToolUse; semantics: adapter is
BLOCKING and awaits a reply).

### 1.2 Activity mapping (for UI status line)
PreToolUse(tool_name) → activity verb: Bash→"running", Read→"reading",
Write/Edit→"editing", Grep/Glob→"finding", WebFetch→"fetching",
Task→"delegating", default→"working". Stop/Notification(idle) → "waiting for you".

## 2. Ingress (app side)

### 2.1 Unix socket (primary)
- Path `~/.niko-island/run/niko-island.sock`; `run/` and `~/.niko-island/`
  created 0700, owned by uid, rejected if symlinked or realpath ≠ path
- **Framing: newline-delimited JSON** (one event per `\n`-terminated line,
  UTF-8). Max line 1 MiB. Probe frame:
  `{"_probe":1}\n` → server answers any single byte then keeps socket open
- One connection per agent process; server tolerates many short-lived
  connections (hooks are process-per-event)

### 2.2 Reply path (blocking events only)
For `PermissionRequest` the bridge keeps the socket open; the server writes
one reply line:

```json
{"ok":true,"reply":{"hookSpecificOutput":{
   "hookEventName":"PermissionRequest",
   "decision":{"behavior":"approve","reason":"user allowed",
               "updatedInput":{ }}}}}
```

`behavior` ∈ `approve | deny | block` (case-insensitive compare),
optional `reason` (string), optional `updatedInput` (merged object — used to
inject answers for AskUserQuestion-style tools). Timeout budget: the bridge
waits up to 23h (hooks registered with timeout 86400 in agent configs).

### 2.3 Local HTTP ingress (secondary, for in-process JS plugins)
- `127.0.0.1:<port>` (default 4096, overridable); POST JSON bodies
- `Authorization: Bearer <token>` where token is generated at install time,
  stored in `~/.niko-island/run/ingress-token` (0600)
- `X-Niko-Directory: <url-encoded cwd>` routes events to the right session
- Same reply JSON for blocking events (response body)

### 2.4 Port discovery for hooks
The installer exports `NIKO_ISLAND_PORTS=<port>` (and `NIKO_ISLAND_RAW_PORTS`)
into hook environments when needed; the socket path is fixed so most hooks
don't need it.

### 2.5 Admission (anti-spoofing, required)
Before admitting a session the server collects evidence:
`cwd`, ancestor process chain (pids + bundle ids where available), socket
peer credentials (uid must equal app uid). Default rule: accept same-uid
processes whose cwd or ancestors look like developer tooling; user can
deny-list bundles. Unadmitted sessions get events dropped + one log line.

## 3. Bridge CLI contract (`niko-bridge`)

Invoked by agent hooks: `niko-bridge --source <agent>` with the hook JSON on
stdin. Behavior:

1. Read stdin fully, parse JSON (on parse error exit 0 — never break the agent)
2. Append `ts`, forward over ingress socket
3. If `hook_event_name == PermissionRequest` (or adapter-marked blocking):
   await reply (§2.2), then translate for the agent:
   - Claude Code: print reply JSON to stdout (`hookSpecificOutput` form);
     on deny-without-JSON fallback exit code 2 + reason on stderr
   - other agents: adapter-specific mapping (see INTEGRATIONS.md)
4. Exit 0 on any internal failure (app missing, socket absent, timeout) —
   **the agent must never fail because we do**

Flags: `--source <id>`, `--task statusline-cache --cache-file <path>`,
`--integrity-check <app-bundle>` (self-check), `--version`.
The installed shim at `~/.niko-island/bin/niko-bridge` locates the real binary
inside the app bundle, with fallbacks: fixed paths → `~/.niko-island/bin/.bridge-cache`
→ `mdfind 'kMDItemCFBundleIdentifier == "app.nikoisland.macos"'`; if not found
exit 0 silently.

## 4. Statusline protocol

`~/.niko-island/bin/niko-statusline` (bash): `input=$(cat)`; forwards stdin to
`niko-bridge --task statusline-cache --cache-file ~/.niko-island/cache/rl.json`;
then prints the user's custom lines (the script has a clearly-marked
user section that rewrites must preserve). Claude Code's statusline payload
contains `rate_limits` — the bridge extracts them into the cache file; the app
reads the cache for usage display (no API needed).

## 5. Hook installation protocol

Phase A — scan (read-only). Run a POSIX shell probe that emits
`<<<NI:<section>>>`-delimited sections per agent: dir exists (D/N/U for
dir/missing/unknown), config file base64 (size-capped, unreadable → U),
plugin states, versions. Never modify before a successful scan.

Phase B — mutate. For each agent: parse existing config (tolerant), insert our
hook entries tagged with a recognizable command substring (`niko-bridge`),
leave everything else byte-identical where formats allow, write atomically
(tmp + rename), record a backup next to the file (`.niko-backup-<ts>`).

Phase C — verify & rollback. Re-run scan; on mismatch restore backups.
Uninstall removes only entries containing our marker substring.

## 6. Usage accounting

### 6.1 Local transcript tailing (primary, no credentials)
Watch (FSEvents + poll fallback):
- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex: `~/.codex/sessions/**`, `~/.codex/archived_sessions/**`,
  `~/.codex/session_index.jsonl`
- OpenCode family: per-project `transcript.jsonl` / `wire.jsonl` /
  `events-recent.jsonl` under their state dirs

SQLite (WAL) schema:

```sql
CREATE TABLE source_files(
  id INTEGER PRIMARY KEY, path TEXT NOT NULL, provider TEXT NOT NULL,
  file_identity TEXT NOT NULL, generation INTEGER NOT NULL,
  size INTEGER NOT NULL, mtime REAL NOT NULL,
  committed_offset INTEGER NOT NULL, tail_hash TEXT NOT NULL,
  parser_version INTEGER NOT NULL, status TEXT NOT NULL,
  UNIQUE(path, generation));
CREATE TABLE events(
  id INTEGER PRIMARY KEY, identity_key TEXT NOT NULL UNIQUE,
  event_kind TEXT NOT NULL, ts REAL NOT NULL, day TEXT NOT NULL,
  agent TEXT NOT NULL, model TEXT NOT NULL, session TEXT, project TEXT,
  input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
  cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL,
  reasoning_tokens INTEGER NOT NULL,
  estimated_cost REAL NOT NULL, cost_source TEXT NOT NULL);
```

`identity_key` = hash(provider, file, offset, request_id/message_id) → dedupe.
`committed_offset` + `tail_hash` → resume after restart/truncate.

### 6.2 Cost
Embedded snapshot of LiteLLM `model_prices_and_context_window.json`
(pruned, vendored with license notice; refreshed at runtime, opt-in) —
input/output/cache_read/cache_write per model → estimated_cost.
`cost_source` ∈ `estimated|reported`.

### 6.3 Optional official APIs (user-enabled, direct, their creds)
- Claude: `GET https://claude.ai/v1/code/sessions` — Authorization from the
  user's keychain entry (Claude Code OAuth), header `anthropic-version`
- Cursor: `GET https://cursor.com/api/usage` + `/api/usage-summary` — session
  cookies read from Cursor's own storage on disk
- Kimi: `POST .../kimi.gateway.billing.v1.BillingService/GetUsages` (Cookie+Origin)
- MiniMax: `GET https://api.minimaxi.com/v1/coding_plan/remains`
Never hardcode or proxy credentials; read at call time from user's stores.

## 7. SSH remote (v3)

- Own Ed25519 keypair; release a `niko-hook` Go binary per platform
  (darwin/linux/freebsd × amd64/arm64) via signed manifest
  (`{kind, agentVersion, assets[{platform, url, sha256, size}]}` + detached sig)
- Install on remote host into `~/.niko-island/bin/`; hook configures agent
  hooks there; events posted to `127.0.0.1:${PORT}` on the remote side where
  PORT is a reverse tunnel (`ssh -R`) owned by the user's own sshd session
  (verify with lsof/ss: listener must be user-owned sshd; else drop)
- Mac side manages tunnel lifecycle, reconnect, stale-port cleanup

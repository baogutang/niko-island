# PROGRESS
updated: 2026-10-12T22:50:00+08:00
milestone: M3
done: [M0, M1, M2]
next: "M3 — Sources/NikoCore/Installer/: ScanProbe.swift (POSIX sh probe, <<<NI:section>>> output, base64 size-capped), AgentRegistry.swift (descriptors from INTEGRATIONS.md), HookMerge.swift (settings-JSON merge/strip by marker), Installer.swift (plan/dry-run → apply atomically with .niko-backup-<ts> → verify by rescan → rollback; uninstall), NikoSettings.swift; CLI install/uninstall/scan; fixture tests"
notes:
  - "PROGRESS.md is committed (BUILD-PLAN overrides the initial .gitignore entry)"
  - "Toolchain: Xcode 26.3 / Swift 6.2.4 locally; keep sources compatible with Swift 6.0+ (CI macos-15). Never reference a weak-captured self from a nested closure (error on 6.0/6.1)"
  - "shellcheck not installed locally -> lint runs in CI (ubuntu job); local fallback is sh -n / bash -n"
  - "NEVER run the installer against the real ~/.claude — tests use temp HOME via --home / NIKO_ISLAND_HOME"
  - "Layout: NikoCore (all non-UI logic) / NikoIslandApp (AppKit+SwiftUI lib, testable) / niko-island (exe = CLI + app) / niko-bridge (exe)"
  - "Bundle: Contents/MacOS/niko-island, Contents/Helpers/niko-bridge; no SwiftPM resources (they break codesign) — Assets/* copied by scripts/make-app.sh"
  - "JSONValue is an own order-preserving parser/serialiser (raw number text kept) so installer rewrites keep foreign config bytes stable"
  - "Unix socket path limit is 104 bytes: tests use Scratch() = /private/tmp/nk-<hex>"
  - "Never use URL.standardizedFileURL / resolvingSymlinksInPath (they strip /private and break the realpath check) — use NikoPaths.normalize / canonicalPath"
  - "M1 finding: on macOS a unix-socket client that connects+writes+closes before the server accept()s can lose its data. Protocol decision: for non-blocking events the bridge half-closes (shutdown SHUT_WR) and waits (bounded) for the server's EOF; the server closes on EOF. Blocking events keep the socket open for the reply line."
  - "Admission: kernel peer uid is the hard gate on every frame; developer-tooling heuristic (ancestors or project-marker cwd) + bundle deny-list evaluated once per session; denial logged once per (session, uid). Bridge self-reports ancestors in _niko because hook processes usually exit before we can inspect them."
  - "HTTP ingress: 127.0.0.1 only, bearer token (run/ingress-token 0600), rejects Origin header, port 4096 with fall-forward (4096 is also OpenCode's default server port) and live port in run/ingress-port. Will be OFF unless an HTTP-plugin agent is installed (settings.httpIngressEnabled)."
  - "Probe reply byte is a single \\n (harmless for line readers)"
  - "TODO app: raise RLIMIT_NOFILE soft limit at launch (GUI default 256)"
  - "M2 bridge: all crash/stop signals + SIGALRM watchdog → _exit(0); only non-zero exits are explicit deny in --reply exit-code mode (2) and --integrity-check (1, never called by hooks). DEBUG-only fault injection via NIKO_BRIDGE_FAULT / NIKO_BRIDGE_WATCHDOG."
  - "M2 bridge slims payloads: drops tool_response/tool_result, prompt capped at 512 chars, strings capped at 4 KiB for non-blocking events; blocking tool_input kept intact; >1 MiB frames are cut down and flagged _niko.truncated (app must not echo updatedInput for those)"
  - "M2 reply translation: app replies canonical approve|deny|block (case-insensitive); bridge emits Claude PermissionRequest JSON (allow/deny+message, block → interrupt:true), PreToolUse dialect for adapter-marked --blocking PreToolUse, exit 2 + stderr otherwise. reply:null = no decision → silent, agent shows its own prompt."
  - "M2 AskUserQuestion: canonical updatedInput.answers = [[labels…]] per question; bridge converts to Claude's {question text: 'a, b'} map"
  - "M2 shim: sh shim maps bridge exit status {2→2, anything else→0}; NIKO_BRIDGE_BIN env override (dev/tests); miss remembered 60 min in bin/.bridge-miss; redirects grouped so a deleted runtime dir cannot make the shim fail (found by test)"
  - "M2 statusline: bash script, rate-limit capture is backgrounded; user section between '# >>> niko-island user section >>>' markers is preserved on rewrite; a pre-existing foreign statusLine command gets chained into the user section and its original JSON saved to cache/statusline-original.json for uninstall"
  - "Tests locate built products via Bundle(for:).bundleURL/.. (works for .build/<triple>/debug)"

# PROGRESS
updated: 2026-10-12T22:20:00+08:00
milestone: M2
done: [M0, M1]
next: "M2 — Sources/NikoCore/Bridge.swift (BridgeRunner: stdin→socket, blocking reply, Claude translation, statusline-cache task, integrity check) + Sources/niko-bridge/main.swift + Shims.swift (bridge shim, niko-statusline) + integration test fake agent→bridge→socket→decision→stdout"
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

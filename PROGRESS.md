# PROGRESS
updated: 2026-10-12T21:45:00+08:00
milestone: M1
done: [M0]
next: "M1 — Sources/NikoCore: Event.swift, Framing.swift (1 MiB NDJSON), Admission.swift, RingBuffer.swift, UnixIngressServer.swift, HTTPIngressServer.swift, IngressHub.swift + tests with a real socket client"
notes:
  - "PROGRESS.md is committed (BUILD-PLAN overrides the initial .gitignore entry)"
  - "Toolchain: Xcode 26.3 / Swift 6.2.4 locally; keep sources compatible with Swift 6.0+ (CI macos-15)"
  - "shellcheck not installed locally -> lint runs in CI (ubuntu job); local fallback is sh -n / bash -n"
  - "NEVER run the installer against the real ~/.claude — tests use temp HOME via --home / NIKO_ISLAND_HOME"
  - "Layout: NikoCore (all non-UI logic) / NikoIslandApp (AppKit+SwiftUI lib, testable) / niko-island (exe = CLI + app) / niko-bridge (exe)"
  - "Bundle: Contents/MacOS/niko-island, Contents/Helpers/niko-bridge; no SwiftPM resources (they break codesign) — Assets/* copied by scripts/make-app.sh"
  - "JSONValue is an own order-preserving parser/serialiser (raw number text kept) so installer rewrites keep foreign config bytes stable"
  - "Unix socket path limit is 104 bytes: tests must use short realpath'd dirs under /private/tmp"
  - "M0 verified: swift build, swift test, scripts/make-app.sh --debug, scripts/smoke-launch.sh (app stays up 3s)"

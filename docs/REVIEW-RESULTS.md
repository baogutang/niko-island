# Review results for 0.1.0

The checklist in [REVIEW.md](../REVIEW.md), walked item by item before the first
push. Each line says what was actually done to check it. "Pass" means there is a
test or a measurement behind it; "Partial" and "Not verified" mean exactly that.

Test names refer to `Tests/`; run everything with `scripts/check.sh`
(220 tests at the time of writing).

## Security

| Item | Result | Evidence |
|---|---|---|
| Socket dir 0700, app dir owned by uid, symlink paths rejected | Pass | `UnixIngressTests`: `testStartCreatesHardenedLayout`, `testLoosePermissionsAreTightened`, `testSymlinkedRunDirectoryIsRejected`, `testSymlinkedRootIsRejected`, `testSymlinkedParentIsRejectedByRealpathCheck`; `SecureDirectoryTests.testRejectsDirectoriesOwnedBySomeoneElse` (uses root-owned `/usr`). `scripts/smoke-launch.sh` checks 0700 on the real bundle. |
| Ingress drops oversize frames (>1 MiB) and malformed JSON without crash | Pass | `testOversizeFrameDroppedAndStreamRecovers`, `testLineOfExactlyOneMebibyteIsAccepted`, `testMalformedJSONDroppedWithoutCrash` (binary junk, 4000-deep nesting, non-objects). HTTP: 413 / 400 in `testRejectsBrowserOriginsOversizeAndBadMethods`. |
| Admission: cross-uid events rejected; denial logged once per session | Pass | `testCrossUIDEventsRejectedAndLoggedOncePerSession`, `testAdmittedSessionStillRejectsOtherUID`, `AdmissionTests`. A second uid cannot be created in the test environment, so the kernel-reported peer uid is rewritten through a test seam; the policy itself is unit-tested with synthetic evidence. |
| HTTP ingress binds 127.0.0.1 only; token file 0600; wrong token 401 | Pass | `HTTPIngressTests`: `testBindsLoopbackOnly` (connects via the machine's LAN address and must fail), `testTokenFileIsPrivateAndStable`, `testLooseTokenPermissionsAreTightened`, `testWrongOrMissingTokenIs401`. Requests carrying an `Origin` header are refused. The listener is off unless a plugin-based agent is connected (`testHTTPIngressOnlyRunsWhenEnabled`). |
| No credentials/tokens in logs or diagnostics export | Pass | `RedactorTests` (key shapes, headers, key=value, license shapes, JWT), `testLoggerRedactsBeforeWritingAndRotates`, `CLITests.testDoctorAndDiagnosticsAreRedacted` (planted keys, ingress token, config contents and home path must be absent). Log call sites were read one by one: none logs a payload. |
| Installer: never weakens foreign entries; backups restored on partial failure; uninstall removes only marker-tagged entries | Pass | `InstallerTests` (33 tests), in particular `testForeignConfigurationIsPreservedExactly`, `testPartialFailureRollsEverythingBack`, `testVerificationMismatchRollsBack`, `testFileChangedAfterScanIsNotOverwritten`, `testUninstallRemovesOnlyMarkerTaggedEntriesInsideSharedGroups`, `testUninstallRestoresOriginalBytes`. Also run by hand on a private copy of a real-world `settings.json` that already had another tool's hooks and a status line: foreign groups unchanged and first, byte-identical after uninstall. |
| All shell snippets pass `shellcheck` | Pass in CI, one documented exception | `shellcheck` is not installed on the build machine, so this runs in `ci.yml` (shellcheck 0.11.0) over every generated script and everything in `scripts/`. Exception: SC1003 is disabled for the three sample hook wrappers whose install path deliberately contains a single quote; the nested quoting it flags is intended and is exercised by `HookCommandEndToEndTests.testHookCommandSurvivesAwkwardInstallPath`. Locally every generated script is also syntax-checked with `sh -n`, `dash -n` and `bash -n`. |

## Robustness

| Item | Result | Evidence |
|---|---|---|
| Bridge never returns non-zero on internal failure | Pass | `BridgeBinaryTests` drive the real binary: `testFaultInjectionAlwaysExitsZero` (crash, abort, segfault, hang → watchdog), `testGarbageInputIsSilentSuccess`, `testSilentSuccessWhenAppIsNotRunning`, `testWedgedAppDoesNotStallTheAgent`, `testTerminatedWhilePendingExitsZero`. The shim adds a second layer (`testOnlyDenyStatusIsPassedThrough`, `testCorruptBinaryIsSilentSuccess`). The only non-zero exits are an explicit deny in exit-code mode and the `--integrity-check` self-test. Fault injection is compiled into debug builds only. |
| App quit/relaunch mid-PermissionRequest: bridge returns cleanly, agent not wedged | Pass | `AppModelTests.testQuitMidRequestReleasesTheAgent` (quit, then a relaunched instance serves the next request), `BridgeBinaryTests.testAppQuitWhilePendingReleasesTheAgent`, and `scripts/smoke-launch.sh` against the assembled bundle. |
| Socket absent → hooks no-op; uninstall simulation leaves a working agent | Partial | `InstallerTests.testInstalledHooksAreHarmlessOnceTheAppIsDeleted` runs every installed hook command and the status-line command in three stages (app gone, shims gone, runtime directory gone): all exit 0 silently. **Not done:** an actual `claude` run after uninstall. |
| SQLite WAL corruption tolerated | Pass | `UsageEngineTests.testDeletedOrDamagedWALIsTolerated`, `testGarbageDatabaseIsSetAsideAndRebuilt`, `UsageEngineIntegrationTests.testEngineRebuildsAfterDatabaseDamage`. |
| Tailer handles truncated/rotated files without dupes | Pass | `testTruncatedFileStartsANewGenerationWithoutDuplicates`, `testRotatedFileBumpsGenerationAndDedupes`, `testInPlaceRewriteIsCaughtByTheTailHash`, `testParserVersionChangeRereadsWithoutDoubleCounting`, `testResumedSessionCopyIsNotCountedTwice`. Known limit: a rewrite that leaves the 64 bytes before the committed offset unchanged is not noticed. |
| 100 concurrent sessions: UI stays responsive, no fd leak | Pass | `AppModelTests.testHundredConcurrentSessionsKeepMainActorResponsive` (1200 events from 16 threads; main-actor gap under 0.25 s locally, descriptor count back to baseline), `UnixIngressTests.testSoakHundredConcurrentSessionsNoDescriptorLeak`. This review found and fixed a 0.3 s stall (events are now delivered in batches). |

## Product

| Item | Result | Evidence |
|---|---|---|
| Cold start to first event < 2 s on M-series | Pass | `scripts/smoke-launch.sh` on the universal release bundle: 536 ms and 729 ms in two runs (834 ms for a debug build). |
| Notification click-through lands on the right terminal tab | Not verified | The AppleScript for Terminal.app is compile-checked (`TerminalJumpTests.testTerminalAppScriptCompiles`) and the generated scripts and tmux commands are unit-tested, including an injection attempt. Nobody has clicked a notification yet; iTerm2 is not installed on the build machine. Steps are in `docs/TESTPLAN.md` §3. |
| Approvals: all four decisions produce correct bridge output | Pass | `AppModelTests`: `testAllowOnce`, `testAllowAlwaysForTool`, `testAllowAllForSession`, `testDenyAndBlock`, plus `testOpenInTerminalMakesNoDecision`, each asserting the real bridge's stdout. |
| Question wizard multi-select answers arrive as `updatedInput.answers` | Pass | `AppModelTests.testQuestionWizardAnswersArriveAsUpdatedInput`, `BridgeBinaryTests.testQuestionAnswersAreTranslatedForClaude`, `OpenCodePluginTests` (canonical array form through the HTTP ingress). |

## Release

| Item | Result | Evidence |
|---|---|---|
| Universal artifact runs on arm64 + x86_64 | Partial | Locally: `lipo -archs` reports `x86_64 arm64` for both binaries, the signature verifies, the arm64 half runs natively and the x86_64 half runs under Rosetta. `release.yml` repeats this on the runner. **Not done:** a run on Intel hardware. |
| README links valid; download link points to releases/latest | Pass | `DocsTests.testRelativeLinksInReadmesResolve`. External links can only be checked after publishing. |
| Website renders on mobile (no horizontal scroll) | Pass | Loaded at 375 px in a browser: `scrollWidth == innerWidth`, all images load, no requests to other origins. An overflowing hero image was found and fixed during this check. |
| No third-party trademarks/assets/copy | Pass, with one note | Icon and screenshots are generated by this repository's code; all copy is original; agent names appear only where the text says what the app works with. `PROTOCOLS.md` carried a leftover third-party identifier in a description of the probe frame; it was removed in this review. **Note:** the first commit in the history still contains that line. |
| LICENSE = MIT; vendored LiteLLM data carries its notice | Pass | `DocsTests.testLicenseAndNotices`, `UsageSupportTests.testBundledSnapshotIsSaneAndCarriesItsNotice`; the notice ships inside the app bundle. |

## Docs honesty

| Item | Result | Evidence |
|---|---|---|
| Every README claim is implemented or marked planned | Pass, after corrections | `DocsTests` ties the agent table to the registry and the documented flags to the CLI. Reading the README against the code changed four things: Gatekeeper instructions were wrong for macOS 15 and later; "returns in milliseconds" became the measured "about 25 ms per hook"; "never resolves on its own" and "trimmed before they leave the agent" were reworded to what the code does; and a section now lists what was not verified first-hand. |
| Uninstall instructions verified on a clean VM/user account | Not verified | No VM or second account was available. Verified against throwaway home directories only (`CLITests.testDryRunThenInstallThenUninstall`, `InstallerTests`). |

## Found and fixed during the review

1. A third-party identifier in `PROTOCOLS.md` (removed).
2. Gatekeeper instructions that no longer work on macOS 15+ (corrected everywhere).
3. A bridge helper left in quarantine would make hooks silently do nothing:
   `niko-island doctor` and the Settings tab now detect it and print the fix.
4. The event ring buffer could hold on to up to 1024 full-size frames; large
   frames are now kept as summaries (`testRingBufferDoesNotRetainLargePayloads`).
5. Usage discovery stopped five directories deep and missed Claude Code's
   nested workflow transcripts; found by running the engine over real
   transcripts and comparing with an independent recount (now an exact match).
6. The main actor stalled for about 0.3 s under a 1200-event burst (batched delivery).
7. A hero image on the website overflowed narrow screens.

## Open items carried forward

Filed as issues after publishing:

- Confirm the Claude Code integration with a live session (status, approvals,
  question tool, status line, rate limits).
- Click-through from notifications: Terminal.app, iTerm2, tmux.
- Notch layout on a notched display.
- `shellcheck` result from CI, and any exceptions it needs.
- Validate each experimental adapter against its agent. The author's own doubt:
  the hook formats listed for Cursor and Gemini CLI in `INTEGRATIONS.md` may not
  match those tools' current releases.
- Intel hardware and a clean macOS account.

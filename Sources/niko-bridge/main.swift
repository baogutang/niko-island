import Darwin
import Foundation
import NikoCore

// niko-bridge: invoked by agent hooks with the hook JSON on stdin (PROTOCOLS §3).
//
// The one rule that outranks everything else in this file: an agent must never
// fail because we did. Every abnormal way out of this process — a crash, a
// signal, a wedged socket — is turned into a silent exit 0.

for crash in [SIGILL, SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGSYS] {
    signal(crash) { _ in _exit(0) }
}
for stop in [SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGALRM] {
    signal(stop) { _ in _exit(0) }
}
signal(SIGPIPE, SIG_IGN)

let invocation = BridgeInvocation.parse(Array(CommandLine.arguments.dropFirst()))
let needsInput = !invocation.showVersion && invocation.integrityCheck == nil

// Watchdog: nothing before the (optional) wait for a decision may take long.
// SIGALRM lands in the handler above and exits 0.
var watchdogSeconds: UInt32 = needsInput ? 5 : 30

#if DEBUG
// Fault injection for the test suite; compiled out of release builds.
if let override = ProcessInfo.processInfo.environment["NIKO_BRIDGE_WATCHDOG"].flatMap(UInt32.init) {
    watchdogSeconds = override
}
alarm(watchdogSeconds)
switch ProcessInfo.processInfo.environment["NIKO_BRIDGE_FAULT"] {
case "crash": fatalError("injected crash")
case "abort": abort()
case "segv": raise(SIGSEGV)
case "hang": while true { pause() }
default: break
}
#endif

alarm(watchdogSeconds)

var input = Data()
if needsInput {
    // Hook payloads are small; anything beyond the cap is not ours to forward.
    let limit = 8 << 20
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let n = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
        if n < 0, errno == EINTR { continue }
        guard n > 0 else { break }
        input.append(contentsOf: buffer[0..<n])
        if input.count > limit { exit(0) }
    }
}

var configuration = BridgeConfiguration()
if let override = configuration.environment["NIKO_BRIDGE_REPLY_TIMEOUT"].flatMap(Double.init), override > 0 {
    configuration.replyTimeout = override
}
// A pending approval may legitimately wait for hours: disarm the watchdog.
configuration.willAwaitReply = { alarm(0) }

alarm(watchdogSeconds)
let result = BridgeRunner.run(invocation, stdin: input, configuration: configuration)
if !result.stdout.isEmpty { FileHandle.standardOutput.write(result.stdout) }
if !result.stderr.isEmpty { FileHandle.standardError.write(result.stderr) }
exit(result.exitCode)

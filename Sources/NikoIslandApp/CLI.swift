import Foundation
import NikoCore

public enum NikoCLI {
    /// Returns an exit status when `arguments` name a CLI subcommand, or `nil`
    /// when the process should carry on and launch the menu-bar app.
    public static func run(arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }
        var args = Arguments(Array(arguments.dropFirst()))
        switch command {
        case "--version", "-v", "version":
            print("niko-island \(NikoVersion.current)")
            return 0
        case "--help", "-h", "help":
            print(usage)
            return 0
        case "install": return install(&args, action: .install)
        case "uninstall": return install(&args, action: .uninstall)
        case "scan": return scan(&args)
        case "status": return status(&args)
        case "doctor": return doctor(&args)
        case "diagnostics": return diagnostics(&args)
        case "pricing": return pricing(&args)
        case "usage": return usage(&args)
        case "internal": return internalCommand(&args)
        default:
            // Finder/LaunchServices may pass `-psn_…`/`-NS…` style arguments: that is an app launch.
            if command.hasPrefix("-") { return nil }
            fail("unknown command '\(command)'\n\n\(usage)")
            return 64
        }
    }

    static let usage = """
    Niko Island \(NikoVersion.current) — menu-bar companion for AI coding agents

    USAGE
      niko-island                       launch the menu-bar app
      niko-island install [options]     register hooks (scan first, back up, verify, roll back on failure)
          --dry-run                     show what would change, change nothing
          --agents a,b,…                choose agents (default: stable adapters only)
          --recommended                 every detected agent with a stable or beta adapter
          --all                         every detected agent, including experimental adapters
          --no-statusline               do not touch the Claude Code status line
      niko-island uninstall [options]   remove every niko-bridge entry; agents keep working
          --dry-run                     show what would change, change nothing
          --purge                       also delete ~/.niko-island and config backups
      niko-island scan [--versions]     read-only report of detected agents
      niko-island status                is the app running, which agents are wired
      niko-island doctor                check permissions, shims and the bundle
      niko-island diagnostics [--out F] redacted report for bug reports
      niko-island usage                 today's and the last 7 days' tokens and estimated cost
      niko-island pricing [status]      which price list is in use
      niko-island pricing refresh       download the latest price list (the only network call this app makes)
      niko-island --version | --help

    Agent ids: \(AgentRegistry.installable.map(\.id).joined(separator: ", "))
    """

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("niko-island: \(message)\n".utf8))
    }

    struct Arguments {
        private var items: [String]
        init(_ items: [String]) { self.items = items }

        mutating func flag(_ name: String) -> Bool {
            guard let index = items.firstIndex(of: name) else { return false }
            items.remove(at: index)
            return true
        }

        mutating func value(_ name: String) -> String? {
            guard let index = items.firstIndex(of: name), index + 1 < items.count else { return nil }
            let value = items[index + 1]
            items.removeSubrange(index...(index + 1))
            return value
        }

        mutating func positional() -> String? { items.isEmpty ? nil : items.removeFirst() }
        var leftovers: [String] { items }
    }

    private static func home(_ args: inout Arguments) -> URL {
        if let override = args.value("--home") {
            return URL(fileURLWithPath: NikoPaths.canonicalPath(override))
        }
        return NikoPaths.userHome()
    }

    private static func rejectLeftovers(_ args: Arguments) -> Bool {
        guard let extra = args.leftovers.first else { return false }
        fail("unexpected argument '\(extra)'")
        return true
    }

    // MARK: install / uninstall

    static func install(_ args: inout Arguments, action: InstallAction) -> Int32 {
        var options = InstallOptions(home: home(&args), paths: .resolve())
        options.dryRun = args.flag("--dry-run")
        options.purge = args.flag("--purge")
        if args.flag("--no-statusline") { options.includeStatusLine = false }
        let all = args.flag("--all")
        let recommended = args.flag("--recommended")
        if let list = args.value("--agents") {
            let ids = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let unknown = ids.filter { AgentRegistry.descriptor($0) == nil }
            guard unknown.isEmpty else {
                fail("unknown agent id: \(unknown.joined(separator: ", "))")
                return 64
            }
            let planned = ids.filter { AgentRegistry.descriptor($0)?.stability == .planned }
            guard planned.isEmpty else {
                fail("no adapter yet for: \(planned.joined(separator: ", ")) (planned)")
                return 64
            }
            options.agentIDs = ids
        } else if all, action == .install {
            options.agentIDs = AgentRegistry.installable.map(\.id)
        } else if recommended, action == .install {
            // Everything the app would offer on first launch; agents that are not installed are skipped by the scan.
            options.agentIDs = AgentRegistry.recommendedIDs
        }
        if rejectLeftovers(args) { return 64 }
        if options.purge, action == .install {
            fail("--purge only applies to uninstall")
            return 64
        }
        options.bridgeBinary = Shims.locateBridgeBinary()
        options.appExecutable = Bundle.main.executablePath

        let installer = Installer(options: options)
        let selected = installer.agents(for: action)
        let beta = selected.filter { $0.stability == .beta }
        let experimental = selected.filter { $0.stability == .experimental }
        if action == .install, !beta.isEmpty {
            print("Beta adapters selected: \(beta.map(\.id).joined(separator: ", ")).")
            print("They follow each agent's own hook reference; we have not driven them against the live agents ourselves.\n")
        }
        if action == .install, !experimental.isEmpty {
            print("Experimental adapters selected: \(experimental.map(\.id).joined(separator: ", ")).")
            print("Their config format is taken on trust and has not been confirmed.\n")
        }
        print("Scanning \(options.home.path) …")
        let result = installer.run(action)
        print(result.report(home: options.home.path))
        if action == .install, result.succeeded {
            for agent in selected where result.touched(agent.id) {
                if let followUp = agent.followUp { print("\(agent.displayName): \(followUp)") }
            }
        }
        if action == .install, result.succeeded, !options.dryRun, options.bridgeBinary == nil {
            print("note: bridge binary not found next to this executable; hooks stay inert until the app is installed.")
        }
        return result.succeeded ? 0 : 1
    }

    // MARK: scan / status / doctor / diagnostics

    static func scan(_ args: inout Arguments) -> Int32 {
        let home = home(&args)
        let versions = args.flag("--versions")
        if rejectLeftovers(args) { return 64 }
        print("Agents under \(home.path) (read-only scan):")
        Diagnostics.agentSummary(home: home, includeVersions: versions).forEach { print("  " + $0) }
        return 0
    }

    static func status(_ args: inout Arguments) -> Int32 {
        let home = home(&args)
        if rejectLeftovers(args) { return 64 }
        let paths = NikoPaths.resolve()
        print("app: \(Diagnostics.isAppRunning(paths: paths) ? "running" : "not running") (\(paths.socket.path))")
        Diagnostics.agentSummary(home: home).forEach { print("  " + $0) }
        return 0
    }

    static func doctor(_ args: inout Arguments) -> Int32 {
        let home = home(&args)
        if rejectLeftovers(args) { return 64 }
        let paths = NikoPaths.resolve()
        var problems = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "ok  " : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            if !ok { problems += 1 }
        }
        print("Niko Island \(NikoVersion.current)")
        for directory in [paths.root, paths.run] where FileManager.default.fileExists(atPath: directory.path) {
            do {
                try SecureDirectory.validate(directory)
                var st = stat()
                lstat(directory.path, &st)
                check(directory.path, st.st_mode & 0o777 == 0o700, "mode \(String(st.st_mode & 0o777, radix: 8))")
            } catch {
                check(directory.path, false, "\(error)")
            }
        }
        if FileManager.default.fileExists(atPath: paths.ingressToken.path) {
            var st = stat()
            lstat(paths.ingressToken.path, &st)
            check("ingress token is private", st.st_mode & 0o777 == 0o600)
        }
        print("info app \(Diagnostics.isAppRunning(paths: paths) ? "running" : "not running")")
        let shimPresent = FileManager.default.isExecutableFile(atPath: paths.bridgeShim.path)
        print("info bridge shim \(shimPresent ? "installed" : "not installed (run `niko-island install`)")")
        if let bridge = Shims.locateBridgeBinary() {
            check("bridge binary", true, bridge)
            check("bridge is not quarantined", !Diagnostics.isQuarantined(bridge),
                  Diagnostics.isQuarantined(bridge) ? "hooks cannot run it; fix with: \(Diagnostics.quarantineFix(for: bridge))" : "")
        } else {
            check("bridge binary", false, "not found next to this executable")
        }
        if Bundle.main.bundleURL.pathExtension == "app", let bridge = Shims.locateBridgeBinary() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bridge)
            process.arguments = ["--integrity-check", Bundle.main.bundleURL.path]
            process.standardOutput = FileHandle.nullDevice
            if (try? process.run()) != nil {
                process.waitUntilExit()
                check("bundle integrity", process.terminationStatus == 0)
            }
        }
        print("Agents:")
        Diagnostics.agentSummary(home: home).forEach { print("  " + $0) }
        print(problems == 0 ? "No problems found." : "\(problems) problem(s) found.")
        return problems == 0 ? 0 : 1
    }

    static func diagnostics(_ args: inout Arguments) -> Int32 {
        let home = home(&args)
        let out = args.value("--out")
        if rejectLeftovers(args) { return 64 }
        let text = Diagnostics.export(paths: .resolve(), home: home)
        if let out {
            do {
                try Data(text.utf8).write(to: URL(fileURLWithPath: out), options: .atomic)
                print("wrote \(out)")
            } catch {
                fail("could not write \(out): \(error.localizedDescription)")
                return 1
            }
        } else {
            print(text, terminator: "")
        }
        return 0
    }

    /// Reads the local transcripts once and prints the totals. Read-only apart from our own database.
    static func usage(_ args: inout Arguments) -> Int32 {
        let home = home(&args)
        if rejectLeftovers(args) { return 64 }
        let paths = NikoPaths.resolve()
        let started = Date()
        let engine = UsageEngine(paths: paths, home: home, pricing: Pricing.load(paths: paths)) { _ in }
        let snapshot = engine.scanNow()
        engine.stop()
        if let failure = snapshot.failure {
            fail("usage is unavailable: \(failure)")
            return 1
        }
        func line(_ row: UsageTotals) -> String {
            let name = "\(AgentRegistry.displayName(for: row.agent)) / \(row.model)"
            return "  " + name.padding(toLength: 44, withPad: " ", startingAt: 0)
                + tokenText(row.tokens).padding(toLength: 10, withPad: " ", startingAt: 0) + costText(row.cost)
        }
        print("Today        \(costText(snapshot.todayCost))   \(tokenText(snapshot.todayTokens)) tokens")
        snapshot.today.forEach { print(line($0)) }
        print("Last 7 days  \(costText(snapshot.weekCost))   \(tokenText(snapshot.weekTokens)) tokens")
        snapshot.week.forEach { print(line($0)) }
        if !snapshot.unpricedModels.isEmpty { print("No price known for: \(snapshot.unpricedModels.joined(separator: ", "))") }
        print("Costs are estimates from public list prices (\(snapshot.pricingSource)). Scan took \(String(format: "%.1f", Date().timeIntervalSince(started))) s.")
        return 0
    }

    static func pricing(_ args: inout Arguments) -> Int32 {
        let paths = NikoPaths.resolve()
        switch args.positional() {
        case "refresh":
            // An explicit command is the user's consent for this one request.
            print("Downloading \(Pricing.refreshURL) …")
            let box = OutcomeBox()
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                box.set(await PricingRefresher.refresh(paths: paths))
                done.signal()
            }
            done.wait()
            switch box.get() {
            case .updated(let models):
                print("Price list updated: \(models) models → \(paths.pricingCache.path)")
                return 0
            case .failed(let reason):
                fail("refresh failed: \(reason)")
                return 1
            }
        case "status", nil:
            let pricing = Pricing.load(paths: paths)
            print("price list: \(pricing.rates.count) models (\(pricing.source))")
            print("automatic weekly refresh: \(NikoSettings.load(paths: paths).pricingRefreshEnabled ? "on" : "off")")
            return 0
        default:
            fail("usage: niko-island pricing [status|refresh]")
            return 64
        }
    }

    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var outcome = PricingRefresher.Outcome.failed("no result")
        func set(_ value: PricingRefresher.Outcome) { lock.lock(); outcome = value; lock.unlock() }
        func get() -> PricingRefresher.Outcome { lock.lock(); defer { lock.unlock() }; return outcome }
    }

    // MARK: internal helpers (CI)

    static func internalCommand(_ args: inout Arguments) -> Int32 {
        switch args.positional() {
        case "dump-scripts":
            guard let directory = args.positional() else {
                fail("usage: niko-island internal dump-scripts <dir>")
                return 64
            }
            return dumpScripts(to: URL(fileURLWithPath: directory))
        case "scout":
            // What the transcripts on disk say right now. Text is shown as lengths
            // unless --text is given, so the output can go into a bug report.
            let showText = args.flag("--text")
            let minutes = args.positional().flatMap(Double.init) ?? 30
            var options = TranscriptScout.Options()
            options.window = minutes * 60
            let scout = TranscriptScout(home: URL(fileURLWithPath: NSHomeDirectory()), options: options) { _ in }
            let started = Date()
            let snapshots = scout.scanOnce()
            func show(_ text: String?) -> String {
                guard let text else { return "-" }
                return showText ? "\"\(Activity.oneLine(text, limit: 60))\"" : "\(text.count) chars"
            }
            for snapshot in snapshots {
                print("\(snapshot.key.source)\t\(snapshot.key.sessionID.prefix(8))\t\(snapshot.phase.rawValue)\t\(snapshot.activity.verb)"
                      + "\tage=\(Int(Date().timeIntervalSince(snapshot.updatedAt)))s\thost=\(snapshot.host?.name ?? "-")"
                      + "\tsubagent=\(snapshot.isSubagent)\tproject=\(AutoNamer.projectName(cwd: snapshot.cwd) ?? "-")"
                      + "\ttitle=\(show(snapshot.title))\tprompt=\(show(snapshot.lastPrompt))\treply=\(show(snapshot.lastReply))"
                      + "\tdetail=\(show(snapshot.activity.detail))")
            }
            print("\(snapshots.count) session(s) active in the last \(Int(minutes)) min, scanned in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            return 0
        case "listen":
            // Headless ingress for checking an integration: prints one line per
            // admitted event (names and keys only, never values) and makes no decisions.
            let seconds = args.positional().flatMap(Double.init) ?? 30
            let paths = NikoPaths.resolve()
            let hub = IngressHub(policy: NikoSettings.load(paths: paths).admissionPolicy, log: NikoLog())
            hub.setHandler { delivery in
                let event = delivery.event
                let inputKeys = (event.toolInput?.keys ?? []).sorted().joined(separator: ",")
                print("\(event.name)\tsource=\(event.source)\ttool=\(event.toolName ?? "-")\tblocking=\(event.isBlocking)"
                      + "\tkeys=\(event.raw.keys.sorted().joined(separator: ","))\tinput_keys=\(inputKeys)")
                fflush(stdout)
                delivery.replier?.send(ReplyBuilder.line(for: .passToTerminal, event: event))
            }
            let server = UnixIngressServer(paths: paths, hub: hub)
            do {
                try server.start()
            } catch {
                fail("\(error)")
                return 1
            }
            print("listening on \(paths.socket.path) for \(Int(seconds)) s")
            fflush(stdout)
            Thread.sleep(forTimeInterval: seconds)
            server.stop()
            let counters = hub.counters
            print("received=\(counters.received) admitted=\(counters.admitted) dropped=\(counters.dropped)")
            return 0
        case "render-icon":
            guard let directory = args.positional() else {
                fail("usage: niko-island internal render-icon <AppIcon.iconset>")
                return 64
            }
            return MainActor.assumeIsolated {
                IconRenderer.writeIconset(to: URL(fileURLWithPath: directory)) ? 0 : 1
            }
        case "render-preview":
            guard let directory = args.positional() else {
                fail("usage: niko-island internal render-preview <dir>")
                return 64
            }
            // Called from main.swift, i.e. on the main thread.
            return MainActor.assumeIsolated {
                let root = URL(fileURLWithPath: directory)
                var failed = 0
                for scene in PreviewRenderer.Scene.allCases {
                    let url = root.appendingPathComponent("island-\(scene.rawValue).png")
                    if PreviewRenderer.render(scene, to: url) { print("wrote \(url.path)") } else { failed += 1 }
                }
                // The same scenes as they look on a display without a camera housing.
                for scene in [PreviewRenderer.Scene.working, .attention, .sessions] {
                    let url = root.appendingPathComponent("plain/island-\(scene.rawValue).png")
                    if PreviewRenderer.render(scene, to: url, metrics: .plain) { print("wrote \(url.path)") } else { failed += 1 }
                }
                if PreviewRenderer.renderDemo(to: root.appendingPathComponent("island-demo.gif")) { print("wrote island-demo.gif") } else { failed += 1 }
                if PreviewRenderer.renderMascots(to: root.appendingPathComponent("mascots")) { print("wrote mascots/") } else { failed += 1 }
                return failed == 0 ? 0 : 1
            }
        default:
            fail("unknown internal command")
            return 64
        }
    }

    /// Writes every shell snippet we generate so CI can run shellcheck over them.
    static func dumpScripts(to directory: URL) -> Int32 {
        let defaults = NikoPaths(root: NikoPaths.userHome().appendingPathComponent(".niko-island"), isDefaultLocation: true)
        let custom = NikoPaths(root: URL(fileURLWithPath: "/tmp/odd path's/ni"))
        var files: [(String, String)] = []
        for (label, paths) in [("default", defaults), ("custom", custom)] {
            // The hook wrappers are one-line commands stored in agent configs; here
            // they get a shebang so a linter can read them. The "custom" sample
            // install path contains a single quote on purpose, which makes the
            // (correct) nested quoting look like a mistake to shellcheck's SC1003.
            let head = label == "custom"
                ? "#!/bin/sh\n# shellcheck disable=SC1003 # sample path contains a quote: the nested quoting is intended\n"
                : "#!/bin/sh\n"
            files.append(("bridge-shim.\(label).sh", Shims.bridgeShim(paths: paths)))
            files.append(("statusline.\(label).bash", Shims.statuslineScript(paths: paths)))
            files.append(("statusline-chained.\(label).bash",
                          Shims.statuslineScript(paths: paths, userSection: Shims.chainedUserSection(originalCommand: "cat"))))
            files.append(("hook-command.\(label).sh", head + Shims.hookCommand(paths: paths, source: "claude") + "\n"))
            files.append(("hook-command-deny.\(label).sh",
                          head + Shims.hookCommand(paths: paths, source: "generic", extraArguments: ["--reply", "exit-code"], propagateDeny: true) + "\n"))
            files.append(("statusline-command.\(label).sh", head + Shims.statuslineCommand(paths: paths) + "\n"))
        }
        files.append(("cli-shim.sh", Shims.cliShim(appExecutable: "/Applications/Niko Island.app/Contents/MacOS/niko-island")))
        files.append(("scan-probe.sh", ScanProbe.script(agents: AgentRegistry.installable, includeVersions: true)))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, content) in files {
                try Data(content.utf8).write(to: directory.appendingPathComponent(name))
            }
        } catch {
            fail("\(error.localizedDescription)")
            return 1
        }
        print("wrote \(files.count) scripts to \(directory.path)")
        return 0
    }
}

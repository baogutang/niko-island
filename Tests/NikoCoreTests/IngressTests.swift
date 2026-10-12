import XCTest
@testable import NikoCore

final class UnixIngressTests: XCTestCase {
    var scratch: Scratch!
    var log: NikoLog!
    var hub: IngressHub!
    var server: UnixIngressServer!
    var collector: Collector!

    override func setUp() {
        scratch = Scratch()
        log = NikoLog.inMemory()
        hub = IngressHub(log: log)
        collector = Collector()
        let collector = self.collector!
        hub.setHandler { collector.add($0) }
        server = UnixIngressServer(paths: scratch.paths, hub: hub)
    }

    override func tearDown() {
        server.stop()
        server = nil
        scratch = nil
    }

    private func connect() throws -> SocketClient {
        try XCTUnwrap(SocketClient(path: scratch.paths.socket.path))
    }

    func testStartCreatesHardenedLayout() throws {
        try server.start()
        XCTAssertEqual(mode(of: scratch.paths.root), 0o700)
        XCTAssertEqual(mode(of: scratch.paths.run), 0o700)
        XCTAssertEqual(mode(of: scratch.paths.socket), 0o600)
    }

    func testLoosePermissionsAreTightened() throws {
        try FileManager.default.createDirectory(at: scratch.paths.run, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        chmod(scratch.paths.root.path, 0o755)
        try server.start()
        XCTAssertEqual(mode(of: scratch.paths.root), 0o700)
        XCTAssertEqual(mode(of: scratch.paths.run), 0o700)
    }

    func testSymlinkedRunDirectoryIsRejected() throws {
        let elsewhere = scratch.file("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch.paths.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scratch.paths.run, withDestinationURL: elsewhere)
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? SecureDirectoryError, .symlink(self.scratch.paths.run.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("niko-island.sock").path))
    }

    func testSymlinkedRootIsRejected() throws {
        let elsewhere = scratch.file("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scratch.paths.root, withDestinationURL: elsewhere)
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? SecureDirectoryError, .symlink(self.scratch.paths.root.path))
        }
    }

    func testSymlinkedParentIsRejectedByRealpathCheck() throws {
        let real = scratch.file("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = scratch.file("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let paths = NikoPaths(root: link.appendingPathComponent("ni"))
        let viaLink = UnixIngressServer(paths: paths, hub: hub)
        XCTAssertThrowsError(try viaLink.start()) { error in
            guard case .realpathMismatch = error as? SecureDirectoryError else {
                return XCTFail("expected realpathMismatch, got \(error)")
            }
        }
    }

    func testProbeAnswersOneByteAndKeepsConnection() throws {
        try server.start()
        let client = try connect()
        client.send("{\"_probe\":1}\n")
        XCTAssertEqual(client.readBytes(1)?.count, 1)
        client.send(eventJSON("SessionStart"))
        XCTAssertEqual(collector.wait(count: 1).count, 1)
        XCTAssertEqual(hub.counters.received, 1, "the probe itself is not an event")
    }

    func testEventDeliveredWithEvidence() throws {
        try server.start()
        let client = try connect()
        client.send(eventJSON("PreToolUse", session: "abc", tool: "Bash"))
        let delivery = try XCTUnwrap(collector.wait(count: 1).first)
        XCTAssertEqual(delivery.event.name, "PreToolUse")
        XCTAssertEqual(delivery.event.key, SessionKey(source: "claude", sessionID: "abc"))
        XCTAssertEqual(delivery.event.toolName, "Bash")
        XCTAssertEqual(delivery.event.toolInput?["command"]?.stringValue, "ls -la")
        XCTAssertEqual(delivery.event.cwd, "/tmp")
        XCTAssertEqual(delivery.evidence.peerUID, getuid())
        XCTAssertEqual(delivery.evidence.peerPID, getpid())
        XCTAssertFalse(delivery.evidence.ancestors.isEmpty)
        XCTAssertNil(delivery.replier)
    }

    func testFramesSplitAcrossWritesAndBatched() throws {
        try server.start()
        let client = try connect()
        let line = eventJSON("PostToolUse", tool: "Read")
        let half = line.index(line.startIndex, offsetBy: line.count / 2)
        client.send(String(line[..<half]))
        usleep(50_000)
        client.send(String(line[half...]) + eventJSON("Stop") + eventJSON("SessionEnd"))
        XCTAssertEqual(collector.wait(count: 3).map(\.event.name), ["PostToolUse", "Stop", "SessionEnd"])
    }

    func testOversizeFrameDroppedAndStreamRecovers() throws {
        try server.start()
        let client = try connect()
        var big = Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"x\",\"pad\":\"".utf8)
        big.append(Data(repeating: UInt8(ascii: "a"), count: (1 << 20) + 4096))
        big.append(Data("\"}\n".utf8))
        XCTAssertTrue(client.send(big))
        client.send(eventJSON("Stop"))
        XCTAssertEqual(collector.wait(count: 1).map(\.event.name), ["Stop"])
        XCTAssertEqual(hub.counters.oversize, 1)
        XCTAssertEqual(hub.counters.admitted, 1)
        XCTAssertTrue(server.isRunning)
    }

    func testLineOfExactlyOneMebibyteIsAccepted() throws {
        try server.start()
        let client = try connect()
        let prefix = "{\"hook_event_name\":\"Stop\",\"session_id\":\"x\",\"cwd\":\"/tmp\",\"pad\":\""
        let suffix = "\"}"
        let padding = String(repeating: "a", count: (1 << 20) - prefix.utf8.count - suffix.utf8.count)
        let line = prefix + padding + suffix
        XCTAssertEqual(line.utf8.count, 1 << 20)
        client.send(line + "\n")
        XCTAssertEqual(collector.wait(count: 1).count, 1)
        XCTAssertEqual(hub.counters.oversize, 0)
    }

    func testMalformedJSONDroppedWithoutCrash() throws {
        try server.start()
        let client = try connect()
        client.send("this is not json\n")
        client.send("{\"unterminated\": \n")
        client.send("[1,2,3]\n")                       // valid JSON, not an event object
        client.send("{\"session_id\":\"x\"}\n")         // no event name
        client.send(Data([0xFF, 0xFE, 0x00, 0x0A]))    // binary junk
        client.send(String(repeating: "[", count: 4000) + "\n")
        client.send("\n\r\n")                          // blank lines are ignored
        client.send(eventJSON("Stop"))
        XCTAssertEqual(collector.wait(count: 1).map(\.event.name), ["Stop"])
        XCTAssertEqual(hub.counters.malformed, 6)
        XCTAssertEqual(hub.counters.admitted, 1)
    }

    func testBlockingRequestReceivesReplyLine() throws {
        try server.start()
        let client = try connect()
        client.send(eventJSON("PermissionRequest", tool: "Bash"))
        let delivery = try XCTUnwrap(collector.wait(count: 1).first)
        let replier = try XCTUnwrap(delivery.replier)
        XCTAssertTrue(replier.isOpen)
        XCTAssertTrue(replier.send(.object(["ok": .bool(true), "n": .int(7)])))
        XCTAssertEqual(client.readLine(), "{\"ok\":true,\"n\":7}")
        XCTAssertFalse(replier.send(.null), "only one reply per request")
    }

    func testClientDisconnectBeforeReplyNotifiesOnClose() throws {
        try server.start()
        var client: SocketClient? = try connect()
        client?.send(eventJSON("PermissionRequest", tool: "Bash"))
        let replier = try XCTUnwrap(collector.wait(count: 1).first?.replier)
        let closed = expectation(description: "onClose")
        replier.onClose { closed.fulfill() }
        client = nil
        wait(for: [closed], timeout: 3)
        XCTAssertFalse(replier.isOpen)
        XCTAssertFalse(replier.send(.null))
        XCTAssertTrue(waitUntil { self.server.connectionCount == 0 })
    }

    func testCrossUIDEventsRejectedAndLoggedOncePerSession() throws {
        try server.start()
        server.setPeerUIDOverride { $0 &+ 1 }
        let client = try connect()
        for _ in 0..<3 { client.send(eventJSON("PreToolUse", session: "evil", tool: "Bash")) }
        client.send(eventJSON("PreToolUse", session: "evil2", tool: "Bash"))
        XCTAssertTrue(waitUntil { self.hub.counters.dropped == 4 })
        XCTAssertTrue(collector.all.isEmpty)
        let denials = log.lines.filter { $0.contains("not admitted") }
        XCTAssertEqual(denials.count, 2, "one line per session, not per event")
        XCTAssertEqual(denials.filter { $0.contains("claude/evil,") || $0.contains("claude/evil ") }.count, 1)
    }

    func testAdmittedSessionStillRejectsOtherUID() throws {
        try server.start()
        let good = try connect()
        good.send(eventJSON("SessionStart", session: "shared"))
        XCTAssertEqual(collector.wait(count: 1).count, 1)
        server.setPeerUIDOverride { $0 &+ 1 }
        let bad = try connect()
        bad.send(eventJSON("Stop", session: "shared"))
        XCTAssertTrue(waitUntil { self.hub.counters.dropped == 1 })
        XCTAssertEqual(collector.all.count, 1)
    }

    func testRingBufferKeepsLast1024Events() throws {
        try server.start()
        let client = try connect()
        var batch = ""
        for index in 0..<1100 { batch += eventJSON("PostToolUse", extra: ["n": "\(index)"]) }
        client.send(batch)
        XCTAssertEqual(collector.wait(count: 1100, timeout: 10).count, 1100)
        let recent = hub.recentEvents
        XCTAssertEqual(recent.count, 1024)
        XCTAssertEqual(recent.first?.raw["n"]?.stringValue, "76")
        XCTAssertEqual(recent.last?.raw["n"]?.stringValue, "1099")
    }

    func testRingBufferDoesNotRetainLargePayloads() throws {
        try server.start()
        let client = try connect()
        let big = String(repeating: "z", count: 200_000)
        client.send("{\"source\":\"claude\",\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"big\",\"cwd\":\"/tmp\",\"tool_name\":\"Write\",\"tool_input\":{\"content\":\"\(big)\"}}\n")
        client.send(eventJSON("Stop", session: "small", tool: "Bash"))
        let deliveries = collector.wait(count: 2)
        XCTAssertEqual(deliveries.first?.event.toolInput?["content"]?.stringValue?.count, 200_000, "the request itself is delivered whole")
        let remembered = hub.recentEvents
        XCTAssertEqual(remembered.map(\.name), ["PermissionRequest", "Stop"])
        XCTAssertNil(remembered[0].toolInput, "but the ring keeps only a summary of it")
        XCTAssertNil(remembered[0].raw["tool_input"])
        XCTAssertEqual(remembered[0].toolName, "Write")
        XCTAssertEqual(remembered[0].raw["session_id"]?.stringValue, "big")
        XCTAssertNotNil(remembered[1].toolInput, "ordinary small events are kept as they are")
        deliveries.first?.replier?.send(.null)
    }

    func testSecondInstanceRefusesToStealSocket() throws {
        try server.start()
        let second = UnixIngressServer(paths: scratch.paths, hub: hub)
        XCTAssertThrowsError(try second.start()) { error in
            guard case .alreadyRunning = error as? IngressError else { return XCTFail("got \(error)") }
        }
        let client = try connect()
        client.send(eventJSON("Stop"))
        XCTAssertEqual(collector.wait(count: 1).count, 1, "first instance keeps serving")
    }

    func testStaleSocketFileIsReplaced() throws {
        try server.start()
        server.stop()
        // Simulate a crash: a socket inode nobody listens on.
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try XCTUnwrap(SocketIO.makeUnixAddress(scratch.paths.socket.path))
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        close(stale)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.paths.socket.path))
        try server.start()
        let client = try connect()
        client.send(eventJSON("Stop"))
        XCTAssertEqual(collector.wait(count: 1).count, 1)
    }

    func testRegularFileAtSocketPathIsNotClobbered() throws {
        try SecureDirectory.ensureTree(scratch.paths)
        try Data("precious".utf8).write(to: scratch.paths.socket)
        XCTAssertThrowsError(try server.start())
        XCTAssertEqual(try String(contentsOf: scratch.paths.socket, encoding: .utf8), "precious")
    }

    func testStopRemovesSocketAndClosesConnections() throws {
        try server.start()
        let client = try connect()
        client.send(eventJSON("PermissionRequest", tool: "Bash"))
        let replier = try XCTUnwrap(collector.wait(count: 1).first?.replier)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.paths.socket.path))
        XCTAssertFalse(replier.isOpen)
        XCTAssertNil(client.readLine(timeout: 1), "peer sees EOF, not a fabricated reply")
    }

    func testSoakHundredConcurrentSessionsNoDescriptorLeak() throws {
        try server.start()
        let baseline = openFileDescriptorCount()
        let path = scratch.paths.socket.path
        let sessions = 100, eventsPerSession = 20
        let next = Counter()
        let failures = Counter()
        // Real threads (not GCD) so the clients cannot starve the server's queue.
        let workers = (0..<16).map { _ in
            Thread {
                while true {
                    let index = next.increment() - 1
                    guard index < sessions else { return }
                    // One short-lived connection per event, like real hook processes.
                    for step in 0..<eventsPerSession {
                        guard let client = SocketClient(path: path) else { failures.increment(); continue }
                        client.send(eventJSON(step == 0 ? "SessionStart" : "PostToolUse", session: "soak-\(index)", tool: "Read"))
                        if !client.finish() { failures.increment() }
                    }
                }
            }
        }
        workers.forEach { $0.start() }
        XCTAssertEqual(collector.wait(count: sessions * eventsPerSession, timeout: 30).count, sessions * eventsPerSession)
        XCTAssertEqual(failures.value, 0)
        XCTAssertEqual(Set(collector.all.map(\.event.sessionID)).count, sessions)
        XCTAssertTrue(waitUntil { workers.allSatisfy(\.isFinished) })
        XCTAssertTrue(waitUntil { self.server.connectionCount == 0 })
        XCTAssertTrue(waitUntil { openFileDescriptorCount() <= baseline }, "fd count \(openFileDescriptorCount()) vs baseline \(baseline)")
    }
}

final class HTTPIngressTests: XCTestCase {
    var scratch: Scratch!
    var hub: IngressHub!
    var server: HTTPIngressServer!
    var collector: Collector!
    var token = ""

    override func setUpWithError() throws {
        scratch = Scratch()
        hub = IngressHub(log: .inMemory())
        collector = Collector()
        let collector = self.collector!
        hub.setHandler { collector.add($0) }
        server = HTTPIngressServer(paths: scratch.paths, hub: hub, preferredPort: 0)
        try server.start()
        token = try HTTPIngressServer.loadOrCreateToken(paths: scratch.paths)
    }

    override func tearDown() {
        server.stop()
        server = nil
        scratch = nil
    }

    private var body: String { String(eventJSON("PostToolUse", source: "opencode", tool: "read").dropLast()) }

    func testTokenFileIsPrivateAndStable() throws {
        XCTAssertEqual(mode(of: scratch.paths.ingressToken), 0o600)
        XCTAssertEqual(token.count, 64)
        XCTAssertEqual(try HTTPIngressServer.loadOrCreateToken(paths: scratch.paths), token)
        XCTAssertEqual(scratch.read("ni/run/ingress-port")?.trimmingCharacters(in: .whitespacesAndNewlines), "\(server.port)")
    }

    func testLooseTokenPermissionsAreTightened() throws {
        chmod(scratch.paths.ingressToken.path, 0o644)
        _ = try HTTPIngressServer.loadOrCreateToken(paths: scratch.paths)
        XCTAssertEqual(mode(of: scratch.paths.ingressToken), 0o600)
    }

    func testAcceptsEventWithValidToken() throws {
        let response = try XCTUnwrap(httpPost(port: server.port, token: token, body: body))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, "{\"ok\":true}")
        let delivery = try XCTUnwrap(collector.wait(count: 1).first)
        XCTAssertEqual(delivery.event.source, "opencode")
        XCTAssertEqual(delivery.evidence.channel, .http)
    }

    func testWrongOrMissingTokenIs401() throws {
        XCTAssertEqual(httpPost(port: server.port, token: nil, body: body)?.status, 401)
        XCTAssertEqual(httpPost(port: server.port, token: "nope", body: body)?.status, 401)
        XCTAssertEqual(httpPost(port: server.port, token: String(token.dropLast()), body: body)?.status, 401)
        XCTAssertEqual(httpPost(port: server.port, token: token + "0", body: body)?.status, 401)
        XCTAssertEqual(httpPost(port: server.port, token: "", body: body)?.status, 401)
        XCTAssertEqual(rawHTTP(port: server.port, "GET /health HTTP/1.1\r\nHost: x\r\n\r\n")?.status, 401)
        XCTAssertTrue(collector.all.isEmpty)
        XCTAssertEqual(hub.counters.received, 0)
    }

    func testBindsLoopbackOnly() throws {
        // Find a non-loopback IPv4 address of this machine, if it has one.
        var external: String?
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0 {
            var cursor = list
            while let entry = cursor {
                if let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                   entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0, entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        external = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                        break
                    }
                }
                cursor = entry.pointee.ifa_next
            }
            freeifaddrs(list)
        }
        XCTAssertEqual(rawHTTP(port: server.port, "GET /health HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer \(token)\r\n\r\n")?.status, 200)
        if let external {
            XCTAssertNil(rawHTTP(port: server.port, host: external, "GET /health HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer \(token)\r\n\r\n", timeout: 2),
                         "must not be reachable on \(external)")
        }
    }

    func testDirectoryHeaderRoutesSession() throws {
        let event = "{\"hook_event_name\":\"Stop\",\"source\":\"opencode\"}"
        let response = try XCTUnwrap(httpPost(port: server.port, token: token, body: event,
                                              headers: ["X-Niko-Directory": "%2FUsers%2Fme%2Fmy%20project"]))
        XCTAssertEqual(response.status, 422, "no project markers and no ancestors: not admitted")
        hub.updatePolicy(AdmissionPolicy(requireDeveloperEvidence: false))
        XCTAssertEqual(httpPost(port: server.port, token: token, body: event,
                                headers: ["X-Niko-Directory": "%2FUsers%2Fme%2Fmy%20project"])?.status, 200)
        let delivery = try XCTUnwrap(collector.wait(count: 1).first)
        XCTAssertEqual(delivery.event.cwd, "/Users/me/my project")
        XCTAssertEqual(delivery.event.sessionID, "cwd:/Users/me/my project")
    }

    func testBlockingEventHoldsResponseUntilReply() throws {
        let port = server.port, token = self.token
        let answered = expectation(description: "http response")
        let request = String(eventJSON("PermissionRequest", source: "opencode", tool: "bash").dropLast())
        nonisolated(unsafe) var response: (status: Int, body: String)?
        DispatchQueue.global().async {
            response = httpPost(port: port, token: token, body: request)
            answered.fulfill()
        }
        let replier = try XCTUnwrap(collector.wait(count: 1).first?.replier)
        usleep(100_000)
        XCTAssertNil(response, "response must be held while the request is pending")
        replier.send(.object(["ok": .bool(true), "reply": .object(["decision": .string("x")])]))
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(response?.status, 200)
        XCTAssertEqual(response?.body, "{\"ok\":true,\"reply\":{\"decision\":\"x\"}}")
    }

    func testRejectsBrowserOriginsOversizeAndBadMethods() throws {
        XCTAssertEqual(httpPost(port: server.port, token: token, body: body, headers: ["Origin": "https://evil.example"])?.status, 403)
        XCTAssertEqual(rawHTTP(port: server.port, "PUT /event HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: 0\r\n\r\n")?.status, 405)
        XCTAssertEqual(httpPost(port: server.port, token: token, body: body, path: "/nope")?.status, 404)
        XCTAssertEqual(httpPost(port: server.port, token: token, body: "{not json")?.status, 400)
        XCTAssertEqual(rawHTTP(port: server.port, "POST /event HTTP/1.1\r\nAuthorization: Bearer \(token)\r\n\r\n")?.status, 411)
        let huge = "POST /event HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \((1 << 20) + 1)\r\n\r\n{"
        XCTAssertEqual(rawHTTP(port: server.port, huge)?.status, 413)
        XCTAssertEqual(rawHTTP(port: server.port, "garbage\r\n\r\n")?.status, 400)
        XCTAssertTrue(collector.all.isEmpty)
        XCTAssertTrue(server.isRunning)
    }

    func testPortFallsForwardWhenBusy() throws {
        let otherScratch = Scratch()
        let second = HTTPIngressServer(paths: otherScratch.paths, hub: hub, preferredPort: server.port, portAttempts: 8)
        try second.start()
        defer { second.stop() }
        XCTAssertNotEqual(second.port, server.port)
        XCTAssertGreaterThan(second.port, server.port)
    }
}

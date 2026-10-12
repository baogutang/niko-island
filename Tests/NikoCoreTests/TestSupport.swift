import Foundation
import XCTest
@testable import NikoCore

/// Short, realpath'd scratch directory (unix socket paths are capped at 103 bytes).
final class Scratch {
    let url: URL

    init(file: StaticString = #filePath, line: UInt = #line) {
        var generator = SystemRandomNumberGenerator()
        let suffix = String(UInt32.random(in: .min ... .max, using: &generator), radix: 16)
        let path = "/private/tmp/nk-\(suffix)"
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            XCTFail("cannot create scratch dir: \(error)", file: file, line: line)
        }
        url = URL(fileURLWithPath: path)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var paths: NikoPaths { NikoPaths(root: url.appendingPathComponent("ni")) }

    func file(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    @discardableResult
    func write(_ relative: String, _ text: String) -> URL {
        let target = file(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: target)
        return target
    }

    func read(_ relative: String) -> String? {
        try? String(contentsOf: file(relative), encoding: .utf8)
    }
}

func mode(of url: URL) -> mode_t {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return 0 }
    return st.st_mode & 0o777
}

/// Thread-safe collector for ingress deliveries.
final class Collector: @unchecked Sendable {
    private let condition = NSCondition()
    private var deliveries: [IngressDelivery] = []

    func add(_ delivery: IngressDelivery) {
        condition.lock()
        deliveries.append(delivery)
        condition.broadcast()
        condition.unlock()
    }

    var all: [IngressDelivery] {
        condition.lock()
        defer { condition.unlock() }
        return deliveries
    }

    @discardableResult
    func wait(count: Int, timeout: TimeInterval = 5) -> [IngressDelivery] {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while deliveries.count < count {
            if !condition.wait(until: deadline) { break }
        }
        return deliveries
    }
}

/// Blocking unix-socket client used by tests.
final class SocketClient {
    let fd: Int32

    init?(path: String) {
        let fd = SocketIO.connectUnix(path, timeoutMS: 2000)
        guard fd >= 0 else { return nil }
        self.fd = fd
    }

    deinit { close(fd) }

    @discardableResult
    func send(_ text: String) -> Bool { SocketIO.writeAll(fd, Data(text.utf8), timeoutMS: 5000) }

    @discardableResult
    func send(_ data: Data) -> Bool { SocketIO.writeAll(fd, data, timeoutMS: 5000) }

    /// What the bridge does for fire-and-forget events: half-close, then wait
    /// for the server to close its side. Returns true once EOF was observed.
    @discardableResult
    func finish(timeout: TimeInterval = 5) -> Bool {
        shutdown(fd, SHUT_WR)
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) > 0 else { return false }
        var byte: UInt8 = 0
        return read(fd, &byte, 1) == 0
    }

    func readBytes(_ count: Int, timeout: TimeInterval = 3) -> Data? {
        var out = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while out.count < count {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            guard poll(&pfd, 1, remaining) > 0 else { return out.isEmpty ? nil : out }
            var buffer = [UInt8](repeating: 0, count: count - out.count)
            let n = read(fd, &buffer, buffer.count)
            guard n > 0 else { return out.isEmpty ? nil : out }
            out.append(contentsOf: buffer[0..<n])
        }
        return out
    }

    func readLine(timeout: TimeInterval = 3) -> String? {
        var out = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            guard poll(&pfd, 1, remaining) > 0 else { return nil }
            var byte: UInt8 = 0
            let n = read(fd, &byte, 1)
            guard n == 1 else { return out.isEmpty ? nil : String(decoding: out, as: UTF8.self) }
            if byte == 0x0A { return String(decoding: out, as: UTF8.self) }
            out.append(byte)
        }
    }
}

func eventJSON(_ name: String, session: String = "s1", source: String = "claude", tool: String? = nil,
               extra: [String: String] = [:]) -> String {
    var object = JSONObject([
        "source": .string(source), "hook_event_name": .string(name), "session_id": .string(session),
        "cwd": .string("/tmp"), "ts": .number("1760000000000"),
    ])
    if let tool {
        object["tool_name"] = .string(tool)
        object["tool_input"] = .object(["command": .string("ls -la")])
    }
    for (key, value) in extra { object[key] = .string(value) }
    if source == "opencode" {
        // In-process plugins identify themselves by pid.
        object[AgentEvent.metaKey] = .object(["pid": .int(Int(getpid()))])
    }
    return JSONValue.object(object).serialized(.compact) + "\n"
}

func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(10_000)
    }
    return condition()
}

func openFileDescriptorCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
}

/// One-shot HTTP/1.1 request over a raw loopback socket.
func rawHTTP(port: UInt16, host: String = "127.0.0.1", _ request: String, timeout: TimeInterval = 5) -> (status: Int, body: String)? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    inet_pton(AF_INET, host, &address.sin_addr)
    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard connected == 0 else { return nil }
    guard SocketIO.writeAll(fd, Data(request.utf8), timeoutMS: Int32(timeout * 1000)) else { return nil }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { break }
        response.append(contentsOf: buffer[0..<n])
    }
    guard let text = String(data: response, encoding: .utf8),
          let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
    let statusLine = text.split(separator: "\r\n").first.map(String.init) ?? ""
    let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
    return (status, String(text[headerEnd.upperBound...]))
}

func httpPost(port: UInt16, token: String?, body: String, headers: [String: String] = [:], path: String = "/event") -> (status: Int, body: String)? {
    var request = "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
    if let token { request += "Authorization: Bearer \(token)\r\n" }
    for (name, value) in headers { request += "\(name): \(value)\r\n" }
    request += "\r\n" + body
    return rawHTTP(port: port, request)
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

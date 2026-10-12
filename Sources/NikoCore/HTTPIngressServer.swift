import Darwin
import Foundation

/// Secondary ingress for in-process JS plugins (PROTOCOLS §2.3).
/// Loopback only, bearer-token authenticated, one request per connection.
public final class HTTPIngressServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 4096
    public static let maxBodyBytes = 1 << 20
    static let maxHeaderBytes = 16 * 1024
    static let maxConnections = 128
    static let headerTimeout: TimeInterval = 15

    public let paths: NikoPaths
    private let hub: IngressHub
    private let preferredPort: UInt16
    private let portAttempts: Int
    private let queue = DispatchQueue(label: "app.nikoisland.ingress.http")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var sweepTimer: DispatchSourceTimer?
    private var connections: [UInt64: Connection] = [:]
    private var nextConnectionID: UInt64 = 1
    private var token = ""
    private var boundPort: UInt16 = 0
    private var running = false

    private final class Connection: @unchecked Sendable {
        let id: UInt64
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var request: Request?
        var replier: IngressReplier?
        var responded = false
        var respondedAt: Date?
        var closed = false
        let opened = Date()

        init(id: UInt64, fd: Int32) {
            self.id = id
            self.fd = fd
        }
    }

    struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var bodyStart: Int
        var contentLength: Int
    }

    public init(paths: NikoPaths, hub: IngressHub, preferredPort: UInt16 = HTTPIngressServer.defaultPort,
                portAttempts: Int = 16) {
        self.paths = paths
        self.hub = hub
        self.preferredPort = preferredPort
        self.portAttempts = max(1, portAttempts)
    }

    deinit {
        sweepTimer?.cancel()
        acceptSource?.cancel()
        connections.values.forEach { $0.source?.cancel() }
    }

    /// The port actually bound (0 until started).
    public var port: UInt16 { queue.sync { boundPort } }
    public var isRunning: Bool { queue.sync { running } }
    public var connectionCount: Int { queue.sync { connections.count } }

    // MARK: Token

    /// Reads the ingress token, creating it (0600) on first use.
    public static func loadOrCreateToken(paths: NikoPaths) throws -> String {
        try SecureDirectory.ensure(paths.root)
        try SecureDirectory.ensure(paths.run)
        let path = paths.ingressToken.path
        var st = stat()
        if lstat(path, &st) == 0 {
            guard st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid() else {
                throw IngressError.unexpectedFile(path)
            }
            if st.st_mode & 0o777 != 0o600 { chmod(path, 0o600) }
            if let existing = try? String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
                return existing
            }
            unlink(path)
        }
        var generator = SystemRandomNumberGenerator()
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw IngressError.system("create \(path)", errno) }
        defer { close(fd) }
        guard SocketIO.writeAll(fd, Data((token + "\n").utf8)) else { throw IngressError.system("write \(path)", errno) }
        return token
    }

    // MARK: Lifecycle

    public func start() throws {
        try queue.sync {
            guard !running else { return }
            token = try HTTPIngressServer.loadOrCreateToken(paths: paths)
            var lastError: Int32 = EADDRINUSE
            for offset in 0..<portAttempts {
                let candidate = preferredPort == 0 ? 0 : preferredPort &+ UInt16(offset)
                if let (fd, actual) = HTTPIngressServer.bindLoopback(port: candidate, error: &lastError) {
                    listenFD = fd
                    boundPort = actual
                    break
                }
                if preferredPort == 0 { break }
            }
            guard listenFD >= 0 else { throw IngressError.system("bind 127.0.0.1", lastError) }
            let fd = listenFD
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptPending() }
            source.setCancelHandler { close(fd) }
            source.resume()
            acceptSource = source

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in self?.sweepStalled() }
            timer.resume()
            sweepTimer = timer

            // Plugins discover the live port from this file (PROTOCOLS §2.4).
            try? Data("\(boundPort)\n".utf8).write(to: paths.ingressPort, options: .atomic)
            chmod(paths.ingressPort.path, 0o600)
            running = true
        }
    }

    public func stop() {
        queue.sync {
            guard running else { return }
            running = false
            sweepTimer?.cancel()
            sweepTimer = nil
            acceptSource?.cancel()
            acceptSource = nil
            listenFD = -1
            boundPort = 0
            for connection in Array(connections.values) { closeConnection(connection) }
            unlink(paths.ingressPort.path)
        }
    }

    private static func bindLoopback(port: UInt16, error: inout Int32) -> (Int32, UInt16)? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            error = errno
            return nil
        }
        SocketIO.setCloseOnExec(fd)
        SocketIO.setNonBlocking(fd)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)   // 127.0.0.1, never INADDR_ANY
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0, listen(fd, 64) == 0 else {
            error = errno
            close(fd)
            return nil
        }
        var actual = sockaddr_in()
        var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &actualLength) }
        }
        guard named == 0 else {
            error = errno
            close(fd)
            return nil
        }
        return (fd, UInt16(bigEndian: actual.sin_port))
    }

    // MARK: Connections (all on `queue`)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            guard connections.count < HTTPIngressServer.maxConnections else {
                close(fd)
                continue
            }
            SocketIO.setNonBlocking(fd)
            SocketIO.setCloseOnExec(fd)
            SocketIO.setNoSigPipe(fd)
            let connection = Connection(id: nextConnectionID, fd: fd)
            nextConnectionID += 1
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.drain(connection)
            }
            source.setCancelHandler { close(fd) }
            connection.source = source
            connections[connection.id] = connection
            source.resume()
        }
    }

    private func drain(_ connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 32 * 1024)
        while !connection.closed {
            let n = chunk.withUnsafeMutableBytes { read(connection.fd, $0.baseAddress, $0.count) }
            if n > 0 {
                guard !connection.responded, connection.replier == nil else { continue }   // ignore pipelined bytes
                connection.buffer.append(contentsOf: chunk[0..<n])
                advance(connection)
            } else if n == 0 {
                closeConnection(connection)   // client went away (possibly while we were holding a reply)
                return
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                closeConnection(connection)
                return
            }
        }
    }

    private func advance(_ connection: Connection) {
        if connection.request == nil {
            guard let headerEnd = connection.buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if connection.buffer.count > HTTPIngressServer.maxHeaderBytes {
                    respond(connection, status: 431, body: errorBody("headers too large"))
                }
                return
            }
            guard let request = HTTPIngressServer.parseHead(connection.buffer[..<headerEnd.lowerBound],
                                                            bodyStart: headerEnd.upperBound) else {
                respond(connection, status: 400, body: errorBody("malformed request"))
                return
            }
            connection.request = request
            // Cheap rejections first, before any body is buffered.
            if request.headers["origin"] != nil {
                respond(connection, status: 403, body: errorBody("browser origins are not allowed"))
                return
            }
            guard authorized(request) else {
                respond(connection, status: 401, body: errorBody("missing or invalid bearer token"),
                        extraHeaders: ["WWW-Authenticate": "Bearer"])
                return
            }
            if request.method == "GET", request.path == "/health" {
                respond(connection, status: 200, body: .object(["ok": .bool(true), "app": .string("niko-island"),
                                                                 "version": .string(NikoVersion.current)]))
                return
            }
            guard request.method == "POST" else {
                respond(connection, status: 405, body: errorBody("use POST"), extraHeaders: ["Allow": "POST"])
                return
            }
            guard ["/", "/event", "/v1/event"].contains(request.path) else {
                respond(connection, status: 404, body: errorBody("unknown path"))
                return
            }
            guard request.contentLength >= 0 else {
                respond(connection, status: 411, body: errorBody("Content-Length required"))
                return
            }
            guard request.contentLength <= HTTPIngressServer.maxBodyBytes else {
                hub.noteOversize(channel: .http)
                respond(connection, status: 413, body: errorBody("body exceeds 1 MiB"))
                return
            }
        }
        guard let request = connection.request else { return }
        let available = connection.buffer.count - request.bodyStart
        guard available >= request.contentLength else { return }
        let start = connection.buffer.startIndex + request.bodyStart
        let body = connection.buffer[start..<(start + request.contentLength)]
        dispatch(Data(body), request: request, connection: connection)
    }

    private func dispatch(_ body: Data, request: Request, connection: Connection) {
        let json: JSONValue
        do {
            json = try JSONValue.parse(body)
        } catch {
            hub.noteMalformed(channel: .http, reason: "invalid JSON")
            respond(connection, status: 400, body: errorBody("invalid JSON"))
            return
        }
        let directory = request.headers["x-niko-directory"].flatMap { $0.removingPercentEncoding }
        let context = IngressContext(channel: .http, peerUID: nil, peerPID: nil, directory: directory,
                                     defaultSource: request.headers["x-niko-source"])
        let connectionID = connection.id
        let result = hub.ingest(json, context: context, frameBytes: body.count) { [weak self] data in
            guard let self else { return }
            self.queue.async {
                guard let connection = self.connections[connectionID] else { return }
                self.respondRaw(connection, status: 200, body: data)
            }
        }
        switch result.outcome {
        case .accepted(blocking: true):
            connection.replier = result.replier   // hold the response until the user decides
        case .accepted(blocking: false):
            respond(connection, status: 200, body: .object(["ok": .bool(true)]))
        case .dropped(let reason):
            respond(connection, status: 422, body: errorBody(reason))
        }
    }

    private func authorized(_ request: Request) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return HTTPIngressServer.constantTimeEquals(String(parts[1]).trimmingCharacters(in: .whitespaces), token)
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        var difference = UInt8(truncatingIfNeeded: lhs.count ^ rhs.count)
        for index in 0..<max(lhs.count, rhs.count) {
            let x = index < lhs.count ? lhs[index] : 0
            let y = index < rhs.count ? rhs[index] : 0
            difference |= x ^ y
        }
        return difference == 0 && lhs.count == rhs.count && !rhs.isEmpty
    }

    static func parseHead(_ head: Data, bodyStart: Int) -> Request? {
        guard let text = String(data: head, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil { return nil }   // chunked bodies are not supported
        var contentLength = -1
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else { return nil }
            contentLength = parsed
        }
        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return Request(method: String(requestLine[0]).uppercased(), path: path, headers: headers,
                       bodyStart: bodyStart, contentLength: contentLength)
    }

    private func errorBody(_ message: String) -> JSONValue {
        .object(["ok": .bool(false), "error": .string(message)])
    }

    private func respond(_ connection: Connection, status: Int, body: JSONValue, extraHeaders: [String: String] = [:]) {
        respondRaw(connection, status: status, body: body.serializedData(.compact), extraHeaders: extraHeaders)
    }

    private func respondRaw(_ connection: Connection, status: Int, body: Data, extraHeaders: [String: String] = [:]) {
        guard !connection.closed, !connection.responded else { return }
        connection.responded = true
        connection.respondedAt = Date()
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 411: reason = "Length Required"
        case 413: reason = "Payload Too Large"
        case 422: reason = "Unprocessable Content"
        case 431: reason = "Request Header Fields Too Large"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.replier = nil
        guard SocketIO.writeAll(connection.fd, payload) else {
            closeConnection(connection)
            return
        }
        // Half-close and let the client finish: closing with unread request
        // bytes still queued would turn our response into a connection reset.
        // `drain` discards the rest and closes on EOF; the sweep is the backstop.
        shutdown(connection.fd, SHUT_WR)
    }

    private func closeConnection(_ connection: Connection) {
        guard !connection.closed else { return }
        connection.closed = true
        connections[connection.id] = nil
        connection.source?.cancel()
        connection.source = nil
        connection.replier?.markClosed()
        connection.replier = nil
    }

    /// Connections that never finish sending a request are dropped; held
    /// (blocking) requests are left alone.
    private func sweepStalled() {
        let cutoff = Date().addingTimeInterval(-HTTPIngressServer.headerTimeout)
        for connection in Array(connections.values) where connection.replier == nil {
            let since = connection.respondedAt ?? connection.opened
            if since < cutoff { closeConnection(connection) }
        }
    }
}

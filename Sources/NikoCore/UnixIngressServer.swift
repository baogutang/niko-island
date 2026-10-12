import Darwin
import Foundation

public enum IngressError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case alreadyRunning(String)
    case unexpectedFile(String)
    case system(String, Int32)

    public var description: String {
        switch self {
        case .pathTooLong(let p): return "socket path exceeds the 103-byte limit: \(p)"
        case .alreadyRunning(let p): return "another instance is already listening on \(p)"
        case .unexpectedFile(let p): return "refusing to replace non-socket file at \(p)"
        case .system(let what, let code): return "\(what): \(String(cString: strerror(code)))"
        }
    }
}

enum SocketIO {
    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    static func setCloseOnExec(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFD)
        if flags >= 0 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }
    }

    static func setNoSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes everything or gives up after `timeoutMS` of the peer not draining.
    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data, timeoutMS: Int32 = 2000) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, base + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0, errno == EINTR {
                    continue
                } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    if poll(&pfd, 1, timeoutMS) <= 0 { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    static func makeUnixAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    /// Blocking connect with a timeout. Returns a connected fd or -1.
    static func connectUnix(_ path: String, timeoutMS: Int32) -> Int32 {
        guard var address = makeUnixAddress(path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        setCloseOnExec(fd)
        setNoSigPipe(fd)
        setNonBlocking(fd)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        if result != 0 {
            guard errno == EINPROGRESS || errno == EINTR else {
                close(fd)
                return -1
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, timeoutMS) > 0 else {
                close(fd)
                return -1
            }
            var failure: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size) == 0, failure == 0 else {
                close(fd)
                return -1
            }
        }
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        return fd
    }
}

/// Primary ingress: newline-delimited JSON over a unix socket (PROTOCOLS §2.1/§2.2).
public final class UnixIngressServer: @unchecked Sendable {
    public static let probeKey = "_probe"
    public static let maxConnections = 512
    static let idleTimeout: TimeInterval = 60

    public let paths: NikoPaths
    private let hub: IngressHub
    private let maxLineBytes: Int
    private let queue = DispatchQueue(label: "app.nikoisland.ingress.unix")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var sweepTimer: DispatchSourceTimer?
    private var connections: [UInt64: Connection] = [:]
    private var nextConnectionID: UInt64 = 1
    private var running = false
    /// Test seam: rewrite the kernel-reported peer uid of accepted connections.
    private var peerUIDOverride: (@Sendable (uid_t) -> uid_t)?

    private final class Connection: @unchecked Sendable {
        let id: UInt64
        let fd: Int32
        let peerUID: uid_t?
        let peerPID: pid_t?
        var framer: LineFramer
        var source: DispatchSourceRead?
        var repliers: [IngressReplier] = []
        var lastActivity = Date()
        var closed = false

        init(id: UInt64, fd: Int32, peerUID: uid_t?, peerPID: pid_t?, maxLineBytes: Int) {
            self.id = id
            self.fd = fd
            self.peerUID = peerUID
            self.peerPID = peerPID
            self.framer = LineFramer(maxLineBytes: maxLineBytes)
        }
    }

    public init(paths: NikoPaths, hub: IngressHub, maxLineBytes: Int = LineFramer.defaultMaxLineBytes) {
        self.paths = paths
        self.hub = hub
        self.maxLineBytes = maxLineBytes
    }

    deinit {
        // No queue hop here: deinit may run on `queue` itself. Nothing else can
        // reference us any more, so tearing down directly is safe.
        sweepTimer?.cancel()
        acceptSource?.cancel()
        connections.values.forEach { $0.source?.cancel() }
        if running { unlink(paths.socket.path) }
    }

    public func setPeerUIDOverride(_ override: (@Sendable (uid_t) -> uid_t)?) {
        queue.sync { peerUIDOverride = override }
    }

    public var connectionCount: Int { queue.sync { connections.count } }
    public var isRunning: Bool { queue.sync { running } }

    public func start() throws {
        try queue.sync { try startLocked() }
    }

    private func startLocked() throws {
        guard !running else { return }
        // Both directories are (re)validated on every start: 0700, ours, not symlinks.
        try SecureDirectory.ensure(paths.root)
        try SecureDirectory.ensure(paths.run)

        let path = paths.socket.path
        guard var address = SocketIO.makeUnixAddress(path) else { throw IngressError.pathTooLong(path) }

        var st = stat()
        if lstat(path, &st) == 0 {
            switch st.st_mode & S_IFMT {
            case S_IFSOCK:
                let probe = SocketIO.connectUnix(path, timeoutMS: 200)
                if probe >= 0 {
                    close(probe)
                    throw IngressError.alreadyRunning(path)
                }
                unlink(path)
            case S_IFLNK:
                unlink(path)   // removes the link itself, never its target
            default:
                throw IngressError.unexpectedFile(path)
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IngressError.system("socket", errno) }
        SocketIO.setCloseOnExec(fd)
        SocketIO.setNonBlocking(fd)

        let previousMask = umask(0o177)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        let bindError = errno
        umask(previousMask)
        guard bound == 0 else {
            close(fd)
            throw IngressError.system("bind \(path)", bindError)
        }
        chmod(path, 0o600)
        guard listen(fd, 128) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw IngressError.system("listen", code)
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.sweepIdle() }
        timer.resume()
        sweepTimer = timer
        running = true
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
            for connection in Array(connections.values) { closeConnection(connection) }
            unlink(paths.socket.path)
        }
    }

    // MARK: Accept / read (all on `queue`)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            guard connections.count < UnixIngressServer.maxConnections else {
                close(fd)
                continue
            }
            SocketIO.setNonBlocking(fd)
            SocketIO.setCloseOnExec(fd)
            SocketIO.setNoSigPipe(fd)

            var uid: uid_t = 0
            var gid: gid_t = 0
            var peerUID: uid_t? = getpeereid(fd, &uid, &gid) == 0 ? uid : nil
            if let override = peerUIDOverride, let actual = peerUID { peerUID = override(actual) }
            var pid: pid_t = 0
            var pidSize = socklen_t(MemoryLayout<pid_t>.size)
            let peerPID: pid_t? = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidSize) == 0 && pid > 0 ? pid : nil

            let connection = Connection(id: nextConnectionID, fd: fd, peerUID: peerUID, peerPID: peerPID,
                                        maxLineBytes: maxLineBytes)
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
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !connection.closed {
            let n = buffer.withUnsafeMutableBytes { read(connection.fd, $0.baseAddress, $0.count) }
            if n > 0 {
                connection.lastActivity = Date()
                for frame in connection.framer.feed(Data(buffer[0..<n])) {
                    handle(frame, from: connection)
                    if connection.closed { return }
                }
            } else if n == 0 {
                closeConnection(connection)
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

    private func handle(_ frame: LineFramer.Frame, from connection: Connection) {
        switch frame {
        case .oversize:
            hub.noteOversize(channel: .unixSocket)
        case .line(var line):
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { return }
            let json: JSONValue
            do {
                json = try JSONValue.parse(line)
            } catch {
                hub.noteMalformed(channel: .unixSocket, reason: "invalid JSON")
                return
            }
            if json[UnixIngressServer.probeKey] != nil {
                // Liveness probe: answer one byte, keep the connection.
                SocketIO.writeAll(connection.fd, Data([0x0A]))
                return
            }
            let context = IngressContext(channel: .unixSocket, peerUID: connection.peerUID, peerPID: connection.peerPID)
            let connectionID = connection.id
            let result = hub.ingest(json, context: context, frameBytes: line.count) { [weak self] data in
                guard let self else { return }
                self.queue.async { self.transmit(data, to: connectionID) }
            }
            if let replier = result.replier { connection.repliers.append(replier) }
        }
    }

    private func transmit(_ data: Data, to connectionID: UInt64) {
        guard let connection = connections[connectionID], !connection.closed else { return }
        var line = data
        line.append(0x0A)
        connection.lastActivity = Date()
        if !SocketIO.writeAll(connection.fd, line) { closeConnection(connection) }
    }

    private func closeConnection(_ connection: Connection) {
        guard !connection.closed else { return }
        connection.closed = true
        connections[connection.id] = nil
        connection.source?.cancel()   // cancel handler closes the fd
        connection.source = nil
        let repliers = connection.repliers
        connection.repliers = []
        repliers.forEach { $0.markClosed() }
    }

    /// Drop connections that have gone quiet without a pending reply.
    private func sweepIdle() {
        let cutoff = Date().addingTimeInterval(-UnixIngressServer.idleTimeout)
        for connection in Array(connections.values)
        where connection.lastActivity < cutoff && !connection.repliers.contains(where: \.isOpen) {
            closeConnection(connection)
        }
    }
}

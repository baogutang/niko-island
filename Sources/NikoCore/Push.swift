import Foundation

// A line to the user's own phone, through a push service they set up
// themselves (SPEC §5: "user-configured push, off"). Nothing here runs unless
// the user switched it on and gave it a key; what is sent is a title and one
// short line, to the one server they chose.

/// The services a line can be sent through.
public enum PushService: String, Sendable, CaseIterable {
    /// Bark: an iPhone app with a public server and a self-hosted one.
    case bark
    /// ntfy: topics on ntfy.sh or on a server of one's own.
    case ntfy

    public var defaultServer: String { self == .bark ? "https://api.day.app" : "https://ntfy.sh" }
}

public struct PushMessage: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum PushRequest {
    /// Where a line may be sent: https anywhere, plain http only to this Mac or
    /// the local network (a server of one's own on the home network).
    public static func endpoint(server: String, service: PushService) -> URL? {
        let text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: text.isEmpty ? service.defaultServer : text), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil else { return nil }
        switch parts.scheme?.lowercased() {
        case "https": break
        case "http": guard isLocal(host) else { return nil }
        default: return nil
        }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        // Both services take the whole message as JSON: nothing of it goes into the address.
        parts.path = service == .bark ? path + "/push" : path
        return parts.url
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1]))
    }

    /// `key` is Bark's device key or ntfy's topic.
    public static func make(server: String, service: PushService, key: String, message: PushMessage) -> URLRequest? {
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, let url = endpoint(server: server, service: service) else { return nil }
        var body = JSONObject()
        switch service {
        case .bark:
            body["device_key"] = .string(secret)
            body["title"] = .string(message.title)
            body["body"] = .string(message.body)
            body["group"] = .string(NikoVersion.displayName)
        case .ntfy:
            body["topic"] = .string(secret)
            body["title"] = .string(message.title)
            body["message"] = .string(message.body)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = JSONValue.object(body).serializedData(.compact)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// Sends the lines, a few at most, and remembers how the last one went.
public actor PushClient {
    public enum Outcome: Sendable, Equatable {
        case sent
        /// No key, or a server address that is not allowed.
        case notSetUp
        /// The server said no (a wrong key, an unknown topic).
        case refused(Int)
        case unreachable
    }

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    /// The Keychain account the key is kept under.
    public static let account = "push-key"
    /// The same thing is not said twice within this many seconds.
    static let repeatAfter: TimeInterval = 30

    private let transport: Transport
    private let key: @Sendable () -> String?
    private let clock: @Sendable () -> Date
    private var lastSent: [String: Date] = [:]

    public init(transport: Transport? = nil, key: @escaping @Sendable () -> String? = { ProviderKeychain.read(PushClient.account) },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport ?? PushClient.network
        self.key = key
        self.clock = clock
    }

    /// `subject` names what the line is about (a session and a kind), so that a burst about the same thing is one line.
    @discardableResult
    public func send(_ message: PushMessage, server: String, service: PushService, subject: String? = nil) async -> Outcome {
        let now = clock()
        if let subject {
            if let last = lastSent[subject], now.timeIntervalSince(last) < Self.repeatAfter { return .sent }
            lastSent[subject] = now
            lastSent = lastSent.filter { now.timeIntervalSince($0.value) < 600 }
        }
        guard let key = key(), let request = PushRequest.make(server: server, service: service, key: key, message: message) else { return .notSetUp }
        do {
            let (_, status) = try await transport(request)
            return (200..<300).contains(status) ? .sent : .refused(status)
        } catch {
            return .unreachable
        }
    }

    /// No cookies, no cache, no following a redirect to somewhere else.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    public static let network: Transport = { request in
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

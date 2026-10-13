import Foundation
import Security

// Limits that only the provider knows (SPEC §5: "usage APIs the user explicitly
// enables, their own credentials, direct to vendor"). Everything here is off
// until the user switches it on, talks to exactly one host per provider, and
// writes nothing but percentages and times to disk.

/// Anthropic's answer to "how much of my plan have I used": the same numbers
/// Claude Code shows for `/usage`.
public enum ClaudeUsageAPI {
    public static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func request(token: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static let known = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]

    /// Reads both shapes this endpoint has had: one object per window
    /// (`five_hour: {utilization, resets_at}`) and a list of limits.
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil else { return nil }
        var windows: [RateLimitWindow] = []
        func add(id: String, _ window: JSONValue) {
            guard window.objectValue != nil, !windows.contains(where: { $0.id == id }),
                  let used = (window["utilization"] ?? window["used_percentage"] ?? window["percent"] ?? window["used_percent"])?.doubleValue,
                  used.isFinite else { return }
            let resets = ISOTime.flexible(window["resets_at"] ?? window["reset_at"] ?? window["resetsAt"]).map(Date.init(timeIntervalSince1970:))
            windows.append(RateLimitWindow(id: id, usedPercent: min(max(used, 0), 100), resetsAt: resets))
        }
        for key in known { if let window = root[key] { add(id: key, window) } }
        // The list says the same things under other names; it is only needed when the named windows are gone.
        if windows.isEmpty {
            let names = ["session": "five_hour", "five_hour": "five_hour", "weekly": "seven_day", "week": "seven_day", "seven_day": "seven_day"]
            for item in (root["limits"] ?? root["windows"])?.arrayValue ?? [] {
                guard let kind = (item["kind"] ?? item["type"] ?? item["id"] ?? item["name"])?.stringValue, !kind.isEmpty else { continue }
                if item["is_active"]?.boolValue == false { continue }
                add(id: names[kind.lowercased()] ?? kind, item)
            }
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(windows: windows, capturedAt: now, source: .provider)
    }
}

/// The GLM Coding Plan's quota, as BigModel (bigmodel.cn) and Z.ai (z.ai)
/// report it for the plan a key belongs to. ZCode draws on this plan.
public enum GLMQuotaAPI {
    public enum Region: String, Sendable, CaseIterable {
        case bigmodel, zai

        public var host: String { self == .bigmodel ? "open.bigmodel.cn" : "api.z.ai" }
    }

    public static func url(_ region: Region) -> URL {
        URL(string: "https://\(region.host)/api/monitor/usage/quota/limit")!
    }

    public static func request(key: String, region: Region) -> URLRequest {
        var request = URLRequest(url: url(region), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Which of the two services ZCode itself is set to, from its (non-secret) settings file.
    public static func regionZCodeUses(home: URL) -> Region? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".zcode/v2/setting.json")),
              let name = (try? JSONValue.parse(data))?["providerFamilyDomain"]?.stringValue else { return nil }
        return Region(rawValue: name.lowercased())
    }

    /// `data.limits[]`: token windows are told apart by `unit` and `number`
    /// (3 × 5 = five hours, 6 × 1 = a week); `TIME_LIMIT` is the monthly
    /// allowance of tool calls. A window that has not been touched may come
    /// without a reset time.
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), let body = root["data"], body.objectValue != nil,
              let items = body["limits"]?.arrayValue else { return nil }
        var windows: [RateLimitWindow] = []
        for item in items {
            let type = item["type"]?.stringValue ?? ""
            let unit = item["unit"]?.intValue
            let number = item["number"]?.intValue ?? 1
            var minutes: Int?
            switch unit {
            case 3: minutes = number * 60
            case 4: minutes = number * 1440
            case 6: minutes = number * 10080
            default: minutes = nil
            }
            let id: String
            if type == "TIME_LIMIT" {
                id = "tools_month"
                minutes = nil
            } else if type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT" {
                switch minutes {
                case 300: id = "five_hour"
                case 10080: id = "seven_day"
                default: id = "window_\(unit ?? 0)_\(number)"
                }
            } else {
                continue
            }
            var used = item["percentage"]?.doubleValue
            if used == nil, let total = item["usage"]?.doubleValue, total > 0, let spent = item["currentValue"]?.doubleValue {
                used = spent / total * 100
            }
            guard let used, used.isFinite, !windows.contains(where: { $0.id == id }) else { continue }
            let resets = item["nextResetTime"]?.doubleValue.map { Date(timeIntervalSince1970: $0 > 100_000_000_000 ? $0 / 1000 : $0) }
            windows.append(RateLimitWindow(id: id, usedPercent: min(max(used, 0), 100), resetsAt: resets, windowMinutes: minutes))
        }
        guard !windows.isEmpty else { return nil }
        // The windows people watch first.
        let order = ["five_hour": 0, "seven_day": 1, "tools_month": 3]
        windows.sort { (order[$0.id] ?? 2) < (order[$1.id] ?? 2) }
        var limits = ProviderLimits(windows: windows, capturedAt: now, plan: body["level"]?.stringValue, source: .provider)
        // Not part of any published answer so far; shown if the service ever includes it.
        limits.resetsLeft = (body["resetCount"] ?? body["remainingResetCount"] ?? body["resetOpportunities"])?.intValue
        return limits
    }
}

/// Claude Code's own login, where Claude Code keeps it. Read at the moment of a
/// lookup, held in memory until it expires, never written anywhere by us and
/// never refreshed: renewing it is Claude Code's business.
public enum ClaudeCodeLogin {
    public struct Login: Sendable, Equatable {
        public var token: String
        public var expiresAt: Date?
        public var plan: String?

        public init(token: String, expiresAt: Date? = nil, plan: String? = nil) {
            self.token = token
            self.expiresAt = expiresAt
            self.plan = plan
        }
    }

    public enum Outcome: Sendable, Equatable {
        case found(Login)
        case missing
        /// macOS asked, and the answer was no.
        case denied
    }

    static let keychainService = "Claude Code-credentials"

    public static func parse(_ data: Data) -> Login? {
        guard let root = try? JSONValue.parse(data), let oauth = root["claudeAiOauth"], oauth.objectValue != nil,
              let token = oauth["accessToken"]?.stringValue, !token.isEmpty else { return nil }
        let expires = oauth["expiresAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0 > 100_000_000_000 ? $0 / 1000 : $0) }
        return Login(token: token, expiresAt: expires, plan: oauth["subscriptionType"]?.stringValue)
    }

    public static func read(home: URL) -> Outcome {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let login = parse(data) { return .found(login) }
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { return .denied }
        // Outside the Keychain (other platforms' layout, or a login moved by hand).
        if let data = try? Data(contentsOf: home.appendingPathComponent(".claude/.credentials.json")), let login = parse(data) {
            return .found(login)
        }
        return .missing
    }
}

/// A key the user typed into Settings, kept in the login Keychain under this app's own name.
public enum ProviderKeychain {
    static let service = "app.nikoisland.macos.provider-key"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public static func read(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    public static func exists(_ account: String) -> Bool {
        var query = base(account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// `nil` or an empty string removes the key.
    @discardableResult
    public static func store(_ key: String?, account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return true }
        var item = base(account)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Niko Island: \(account) key"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Asks the providers the user has switched on, at a polite pace.
public actor ProviderLimitsClient {
    public struct Config: Sendable, Equatable {
        public var claude = false
        public var glm = false
        public var glmRegion = GLMQuotaAPI.Region.bigmodel

        public init(claude: Bool = false, glm: Bool = false, glmRegion: GLMQuotaAPI.Region = .bigmodel) {
            self.claude = claude
            self.glm = glm
            self.glmRegion = glmRegion
        }
    }

    public enum State: Sendable, Equatable {
        case ok
        /// Claude Code has never logged in on this Mac (or keeps its login somewhere else).
        case noLogin
        /// The login is there but past its date; Claude Code renews it the next time it runs.
        case loginExpired
        /// The Keychain question was answered with "Deny".
        case denied
        case noKey
        /// The provider did not accept the login or key.
        case unauthorized
        case rateLimited
        case unreachable
        /// An answer came back in a form this version does not read.
        case unreadable
    }

    public struct Result: Sendable, Equatable {
        public var limits: ProviderLimits?
        public var state: State
        public var checkedAt: Date

        public init(limits: ProviderLimits? = nil, state: State, checkedAt: Date) {
            self.limits = limits
            self.state = state
            self.checkedAt = checkedAt
        }
    }

    public struct Secrets: Sendable {
        public var claudeLogin: @Sendable () -> ClaudeCodeLogin.Outcome
        public var glmKey: @Sendable () -> String?

        public init(claudeLogin: @escaping @Sendable () -> ClaudeCodeLogin.Outcome, glmKey: @escaping @Sendable () -> String?) {
            self.claudeLogin = claudeLogin
            self.glmKey = glmKey
        }

        public static func system(home: URL) -> Secrets {
            Secrets(claudeLogin: { ClaudeCodeLogin.read(home: home) }, glmKey: { ProviderKeychain.read(ProviderLimitsClient.glmAccount) })
        }
    }

    /// Returns the body and the HTTP status.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let claude = "claude"
    /// The GLM Coding Plan is what ZCode spends, so its limits are shown with ZCode.
    public static let glm = "zcode"
    public static let glmAccount = "glm-coding-plan"
    /// The only hosts a request may go to.
    public static let hosts: Set<String> = ["api.anthropic.com", "open.bigmodel.cn", "api.z.ai"]

    static let interval: [String: TimeInterval] = [claude: 300, glm: 180]
    static let forcedInterval: TimeInterval = 30

    private let cacheFile: URL
    private let transport: Transport
    private let secrets: Secrets
    private let onChange: @Sendable ([String: Result]) -> Void
    private let clock: @Sendable () -> Date
    private var config = Config()
    private var results: [String: Result] = [:]
    private var claudeLogin: ClaudeCodeLogin.Login?
    private var loop: Task<Void, Never>?
    /// Providers being asked right now: a second caller does not ask again.
    private var asking: Set<String> = []

    public init(paths: NikoPaths, secrets: Secrets, transport: Transport? = nil, clock: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable ([String: Result]) -> Void) {
        cacheFile = paths.cache.appendingPathComponent("provider-limits.json")
        self.secrets = secrets
        self.transport = transport ?? ProviderLimitsClient.network
        self.clock = clock
        self.onChange = onChange
        results = ProviderLimitsClient.load(cacheFile)
    }

    /// The last answers, from this run or the one before.
    public func current() -> [String: Result] { results }

    public func configure(_ new: Config) {
        let old = config
        config = new
        if !new.claude {
            results[Self.claude] = nil
            claudeLogin = nil
        }
        if !new.glm { results[Self.glm] = nil }
        if new.glmRegion != old.glmRegion { results[Self.glm] = nil }
        if old != new {
            save()
            onChange(results)
        }
        loop?.cancel()
        loop = nil
        guard new.claude || new.glm else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let client = self else { return }
                await client.refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    /// Asks whoever is due. `force` is the user pressing "Check now".
    public func refresh(force: Bool = false) async {
        let now = clock()
        var changed = false
        for provider in [Self.claude, Self.glm] {
            guard provider == Self.claude ? config.claude : config.glm else { continue }
            let wait = force ? Self.forcedInterval : (Self.interval[provider] ?? 300)
            if let last = results[provider]?.checkedAt, now.timeIntervalSince(last) < wait { continue }
            // A "no" at the Keychain stands until the user asks again.
            if !force, results[provider]?.state == .denied { continue }
            guard asking.insert(provider).inserted else { continue }
            var result = provider == Self.claude ? await askClaude(now: now) : await askGLM(now: now)
            asking.remove(provider)
            // Switched off while the answer was on its way: it is not wanted any more.
            guard provider == Self.claude ? config.claude : config.glm else { continue }
            // A failed check does not erase what was known a moment ago.
            if result.limits == nil, let known = results[provider]?.limits?.current(now: now), !known.windows.isEmpty {
                result.limits = known
            }
            if results[provider] != result {
                results[provider] = result
                changed = true
            }
        }
        if changed {
            save()
            onChange(results)
        }
    }

    private func askClaude(now: Date) async -> Result {
        if claudeLogin == nil || (claudeLogin?.expiresAt).map({ $0 <= now }) == true {
            switch secrets.claudeLogin() {
            case .found(let login): claudeLogin = login
            case .missing: return Result(state: .noLogin, checkedAt: now)
            case .denied: return Result(state: .denied, checkedAt: now)
            }
        }
        guard let login = claudeLogin else { return Result(state: .noLogin, checkedAt: now) }
        if let expires = login.expiresAt, expires <= now {
            claudeLogin = nil
            return Result(state: .loginExpired, checkedAt: now)
        }
        let (state, limits) = await ask(ClaudeUsageAPI.request(token: login.token)) { ClaudeUsageAPI.parse($0, now: now) }
        if state == .unauthorized { claudeLogin = nil }
        var out = limits
        if out != nil, out?.plan == nil { out?.plan = login.plan }
        return Result(limits: out, state: state, checkedAt: now)
    }

    private func askGLM(now: Date) async -> Result {
        guard let key = secrets.glmKey(), !key.isEmpty else { return Result(state: .noKey, checkedAt: now) }
        let (state, limits) = await ask(GLMQuotaAPI.request(key: key, region: config.glmRegion)) { GLMQuotaAPI.parse($0, now: now) }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    private func ask(_ request: URLRequest, parse: (Data) -> ProviderLimits?) async -> (State, ProviderLimits?) {
        guard let host = request.url?.host, Self.hosts.contains(host), request.url?.scheme == "https" else { return (.unreachable, nil) }
        do {
            let (data, status) = try await transport(request)
            switch status {
            case 200..<300:
                guard let limits = parse(data) else { return (.unreadable, nil) }
                return (.ok, limits)
            case 401, 403: return (.unauthorized, nil)
            case 429: return (.rateLimited, nil)
            default: return (.unreachable, nil)
            }
        } catch {
            return (.unreachable, nil)
        }
    }

    // MARK: Network

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
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    public static let network: Transport = { request in
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: Cache (percentages and times only)

    private func save() {
        var root = JSONObject()
        for (provider, result) in results {
            var item = JSONObject(["checked_at": .number(String(result.checkedAt.timeIntervalSince1970)), "state": .string(String(describing: result.state))])
            if let limits = result.limits { item["limits"] = (try? JSONValue.parse(limits.json)) ?? .null }
            root[provider] = .object(item)
        }
        _ = AtomicFile.write(JSONValue.object(root).serializedData(.pretty), to: cacheFile.path, mode: 0o600)
    }

    private static func load(_ file: URL) -> [String: Result] {
        guard let data = try? Data(contentsOf: file), let root = (try? JSONValue.parse(data))?.objectValue else { return [:] }
        var out: [String: Result] = [:]
        for member in root.members {
            guard let checked = member.value["checked_at"]?.doubleValue,
                  let limits = member.value["limits"].flatMap({ ProviderLimits(json: $0.serialized(.compact)) }), !limits.windows.isEmpty else { continue }
            // Old answers are shown as what they are; the first check replaces them.
            out[member.key] = Result(limits: limits, state: .ok, checkedAt: Date(timeIntervalSince1970: checked))
        }
        return out
    }
}

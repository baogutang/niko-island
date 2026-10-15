import CryptoKit
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

    /// Reads the shapes this endpoint has had: one object per window
    /// (`five_hour: {utilization, resets_at}`), a list of limits, and in the
    /// list a weekly allowance per model (`kind: weekly_scoped`).
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), let object = root.objectValue else { return nil }
        var windows: [RateLimitWindow] = []
        func window(id: String, _ value: JSONValue) -> RateLimitWindow? {
            guard value.objectValue != nil,
                  let used = (value["utilization"] ?? value["used_percentage"] ?? value["percent"] ?? value["used_percent"])?.doubleValue,
                  used.isFinite else { return nil }
            let resets = ISOTime.flexible(value["resets_at"] ?? value["reset_at"] ?? value["resetsAt"]).map(Date.init(timeIntervalSince1970:))
            return RateLimitWindow(id: id, usedPercent: min(max(used, 0), 100), resetsAt: resets)
        }
        func add(id: String, _ value: JSONValue) {
            guard !windows.contains(where: { $0.id == id }), let window = window(id: id, value) else { return }
            windows.append(window)
        }
        for key in known { if let value = root[key] { add(id: key, value) } }
        // A week or a five-hour window this version has no name for is still a window. (The answer also
        // carries entries under code names; what those count is not known, so they are not shown.)
        for member in object.members where !known.contains(member.key)
            && (member.key.hasPrefix("seven_day_") || member.key.hasPrefix("five_hour_")) {
            if member.value["utilization"]?.doubleValue != nil { add(id: member.key, member.value) }
        }
        let list = (root["limits"] ?? root["windows"])?.arrayValue ?? []
        // The weekly allowance of one model. Newer than the named windows, so it wins where both speak.
        for item in list where item["kind"]?.stringValue == "weekly_scoped" && item["group"]?.stringValue == "weekly" {
            // A share set aside for one way of using the model is not the model's week.
            if let surface = item["scope"]?["surface"], !surface.isNull { continue }
            guard let name = item["scope"]?["model"]?["display_name"]?.stringValue?.trimmingCharacters(in: .whitespaces).lowercased(),
                  !name.isEmpty, let scoped = window(id: "seven_day_" + name.replacingOccurrences(of: " ", with: "_"), item) else { continue }
            windows.removeAll { $0.id == scoped.id }
            windows.append(scoped)
        }
        // The list says the same things under other names; it is only needed when the named windows are gone.
        if !windows.contains(where: { $0.id == "five_hour" || $0.id == "seven_day" }) {
            // `is_active` says which limit is the one that bites right now, not which exist.
            let names = ["session": "five_hour", "five_hour": "five_hour", "weekly": "seven_day", "weekly_all": "seven_day",
                         "week": "seven_day", "seven_day": "seven_day"]
            for item in list {
                guard let kind = (item["kind"] ?? item["type"] ?? item["id"] ?? item["name"])?.stringValue, let id = names[kind.lowercased()] else { continue }
                add(id: id, item)
            }
        }
        // Paid use beyond the plan, where the account has switched it on.
        if let extra = root["extra_usage"], extra["is_enabled"]?.boolValue == true { add(id: "extra_usage", extra) }
        guard !windows.isEmpty else { return nil }
        let order = ["five_hour": 0, "seven_day": 1, "extra_usage": 9]
        windows = windows.enumerated().sorted {
            let (l, r) = (order[$0.element.id] ?? 2, order[$1.element.id] ?? 2)
            return l == r ? $0.offset < $1.offset : l < r
        }.map(\.element)
        return ProviderLimits(windows: windows, capturedAt: now, source: .provider)
    }

    /// The last answer Claude Code itself got and kept in `~/.claude.json`
    /// (`cachedUsageUtilization`). It needs no sign-in to read, and is as old
    /// as the last time Claude Code looked: windows that have reset since are
    /// dropped by whoever shows it.
    public static func cached(home: URL, includingReset: Bool = false) -> ProviderLimits? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")), data.count < 8_000_000,
              let root = try? JSONValue.parse(data, skipping: ["projects", "cachedGrowthBookFeatures", "cachedExperimentData", "cachedArtifactRoster"]),
              let cache = root["cachedUsageUtilization"], let answer = cache["utilization"], answer.objectValue != nil,
              let fetched = cache["fetchedAtMs"]?.doubleValue else { return nil }
        guard let at = ISOTime.date(fetched) else { return nil }
        guard var limits = parse(answer.serializedData(.compact), now: at) else {
            // Nothing in it that can be shown; when it was fetched is still worth knowing.
            return includingReset ? ProviderLimits(windows: [], capturedAt: at, source: .agentCache) : nil
        }
        limits.source = .agentCache
        return limits
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

    /// `data.limits[]`: token windows are told apart by `unit` (3 = hours, so
    /// 3 × 5 is the five-hour window; 6 = the week, whatever `number` says: the
    /// service has sent both 1 and 7 for it); `TIME_LIMIT` is the monthly
    /// allowance of tool calls. A window that has not been touched may come
    /// without a reset time.
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), let body = root["data"], body.objectValue != nil,
              let items = body["limits"]?.arrayValue else { return nil }
        var windows: [RateLimitWindow] = []
        /// Token windows that do not say which they are.
        var unnamed: [(used: Double, resets: Date?)] = []
        for item in items {
            let type = (item["type"]?.stringValue ?? "").uppercased()
            let unit = item["unit"]?.intValue
            let number = item["number"]?.intValue ?? 1
            var used = item["percentage"]?.doubleValue
            if used == nil, let total = item["usage"]?.doubleValue, total > 0, let spent = item["currentValue"]?.doubleValue {
                used = spent / total * 100
            }
            guard let used, used.isFinite else { continue }
            let resets = ISOTime.date(item["nextResetTime"]?.doubleValue)
            let id: String
            var minutes: Int?
            if type == "TIME_LIMIT" {
                id = "tools_month"
            } else if type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT" {
                switch unit {
                case 3:
                    minutes = number * 60
                    id = number == 5 ? "five_hour" : "window_3_\(number)"
                case 6:
                    minutes = 10080
                    id = "seven_day"
                case 4:
                    minutes = number * 1440
                    id = number == 7 ? "seven_day" : "window_4_\(number)"
                case nil:
                    unnamed.append((used, resets))
                    continue
                default:
                    id = "window_\(unit ?? 0)_\(number)"
                }
            } else {
                continue
            }
            guard !windows.contains(where: { $0.id == id }) else { continue }
            windows.append(RateLimitWindow(id: id, usedPercent: min(max(used, 0), 100), resetsAt: resets, windowMinutes: minutes))
        }
        // No `unit` at all: the shorter window is the one that resets first, or has not started counting.
        unnamed.sort { ($0.resets ?? .distantPast) < ($1.resets ?? .distantPast) }
        for (entry, id) in zip(unnamed, ["five_hour", "seven_day"].filter { id in !windows.contains { $0.id == id } }) {
            windows.append(RateLimitWindow(id: id, usedPercent: min(max(entry.used, 0), 100), resetsAt: entry.resets))
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

/// What ChatGPT says about a Codex plan: the windows Codex also writes into
/// its session files, current even when Codex has not run for a while, and the
/// resets an account has saved up.
public enum CodexUsageAPI {
    public static let usage = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let savedResets = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    public static func request(_ url: URL, login: CodexLogin.Login) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        if let account = login.account, !account.isEmpty { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// `rate_limit.{primary_window, secondary_window}.{used_percent, limit_window_seconds, reset_at}`.
    /// The windows keep the names Codex's own files use, so both sources describe the same rows.
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), let limit = root["rate_limit"], limit.objectValue != nil else { return nil }
        var windows: [RateLimitWindow] = []
        for (id, key) in [("primary", "primary_window"), ("secondary", "secondary_window")] {
            guard let window = limit[key], window.objectValue != nil,
                  let used = window["used_percent"]?.doubleValue, used.isFinite else { continue }
            var resets = ISOTime.date(window["reset_at"]?.doubleValue)
            if resets == nil, let after = window["reset_after_seconds"]?.doubleValue, after.isFinite, after >= 0, after < 400 * 86_400 {
                resets = now.addingTimeInterval(after)
            }
            windows.append(RateLimitWindow(id: id, usedPercent: min(max(used, 0), 100), resetsAt: resets,
                                           windowMinutes: window["limit_window_seconds"]?.intValue.map { $0 / 60 }))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(windows: windows, capturedAt: now, plan: root["plan_type"]?.stringValue, source: .provider)
    }

    /// How many saved resets can still be spent. Counted from the list itself:
    /// one that is used up or past its date does not count.
    public static func savedResets(_ data: Data, now: Date = Date()) -> Int? {
        guard let root = try? JSONValue.parse(data), let credits = root["credits"]?.arrayValue else { return nil }
        return credits.filter { credit in
            guard credit["status"]?.stringValue == "available" else { return false }
            guard let expires = ISOTime.flexible(credit["expires_at"]) else { return true }
            return expires > now.timeIntervalSince1970
        }.count
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
        guard let root = try? JSONValue.parse(data), let oauth = root["claudeAiOauth"] ?? root["claude.ai_oauth"], oauth.objectValue != nil,
              let token = oauth["accessToken"]?.stringValue, !token.isEmpty else { return nil }
        let expires = ISOTime.date(oauth["expiresAt"]?.doubleValue)
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

/// Codex's own sign-in with a ChatGPT plan, where Codex keeps it: `auth.json`
/// in its folder, or the Keychain when Codex is set to use that. Read at the
/// moment of a lookup, never written and never renewed by us.
public enum CodexLogin {
    public struct Login: Sendable, Equatable {
        public var token: String
        public var account: String?

        public init(token: String, account: String? = nil) {
            self.token = token
            self.account = account
        }
    }

    public enum Outcome: Sendable, Equatable {
        case found(Login)
        case missing
        case denied
    }

    static let keychainService = "Codex Auth"

    /// An API key has no plan to ask about: only a ChatGPT sign-in counts.
    public static func parse(_ data: Data) -> Login? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil else { return nil }
        if let mode = root["auth_mode"]?.stringValue, mode.lowercased() != "chatgpt" { return nil }
        guard let token = root["tokens"]?["access_token"]?.stringValue, !token.isEmpty else { return nil }
        return Login(token: token, account: root["tokens"]?["account_id"]?.stringValue)
    }

    /// The name Codex files its sign-in under in the Keychain: `cli|` and the
    /// first 16 hex digits of the SHA-256 of its folder's real path.
    static func keychainAccount(folder: URL) -> String {
        let path = folder.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "cli|" + digest.prefix(16)
    }

    public static func read(home: URL) -> Outcome {
        let folder = home.appendingPathComponent(".codex")
        // The file is where Codex puts it unless told otherwise, and reading it asks nobody.
        if let data = try? Data(contentsOf: folder.appendingPathComponent("auth.json")), let login = parse(data) { return .found(login) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount(folder: folder),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let login = parse(data) { return .found(login) }
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { return .denied }
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
        public var codex = false
        public var kimi = false
        public var minimax = false
        public var minimaxRegion = MiniMaxQuotaAPI.Region.cn
        public var gemini = false
        public var copilot = false

        public init(claude: Bool = false, glm: Bool = false, glmRegion: GLMQuotaAPI.Region = .bigmodel, codex: Bool = false,
                    kimi: Bool = false, minimax: Bool = false, minimaxRegion: MiniMaxQuotaAPI.Region = .cn, gemini: Bool = false,
                    copilot: Bool = false) {
            self.claude = claude
            self.glm = glm
            self.glmRegion = glmRegion
            self.codex = codex
            self.kimi = kimi
            self.minimax = minimax
            self.minimaxRegion = minimaxRegion
            self.gemini = gemini
            self.copilot = copilot
        }

        public func asks(_ provider: String) -> Bool {
            switch provider {
            case ProviderLimitsClient.claude: return claude
            case ProviderLimitsClient.glm: return glm
            case ProviderLimitsClient.codex: return codex
            case ProviderLimitsClient.kimi: return kimi
            case ProviderLimitsClient.minimax: return minimax
            case ProviderLimitsClient.gemini: return gemini
            case ProviderLimitsClient.copilot: return copilot
            default: return false
            }
        }

        public var asksAnyone: Bool { ProviderLimitsClient.providers.contains(where: asks) }
    }

    public enum State: Sendable, Equatable {
        case ok
        /// The agent has never logged in on this Mac (or keeps its login somewhere else).
        case noLogin
        /// The login is there but the provider no longer takes it; the agent renews it the next time it runs.
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
        public var codexLogin: @Sendable () -> CodexLogin.Outcome
        public var kimiKey: @Sendable () -> String?
        public var minimaxKey: @Sendable () -> String?
        public var geminiLogin: @Sendable () -> GeminiLogin.Outcome
        public var githubLogin: @Sendable () -> GitHubLogin.Outcome

        public init(claudeLogin: @escaping @Sendable () -> ClaudeCodeLogin.Outcome, glmKey: @escaping @Sendable () -> String?,
                    codexLogin: @escaping @Sendable () -> CodexLogin.Outcome = { .missing },
                    kimiKey: @escaping @Sendable () -> String? = { nil }, minimaxKey: @escaping @Sendable () -> String? = { nil },
                    geminiLogin: @escaping @Sendable () -> GeminiLogin.Outcome = { .missing },
                    githubLogin: @escaping @Sendable () -> GitHubLogin.Outcome = { .missing }) {
            self.claudeLogin = claudeLogin
            self.glmKey = glmKey
            self.codexLogin = codexLogin
            self.kimiKey = kimiKey
            self.minimaxKey = minimaxKey
            self.geminiLogin = geminiLogin
            self.githubLogin = githubLogin
        }

        public static func system(home: URL) -> Secrets {
            Secrets(claudeLogin: { ClaudeCodeLogin.read(home: home) }, glmKey: { ProviderKeychain.read(ProviderLimitsClient.glmAccount) },
                    codexLogin: { CodexLogin.read(home: home) },
                    kimiKey: { ProviderKeychain.read(ProviderLimitsClient.kimiAccount) },
                    minimaxKey: { ProviderKeychain.read(ProviderLimitsClient.minimaxAccount) },
                    geminiLogin: { GeminiLogin.read(home: home) },
                    githubLogin: { GitHubLogin.read(home: home) })
        }
    }

    /// Returns the body and the HTTP status.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let claude = "claude"
    /// The GLM Coding Plan is what ZCode spends, so its limits are shown with ZCode.
    public static let glm = "zcode"
    public static let glmAccount = "glm-coding-plan"
    public static let codex = "codex"
    public static let kimi = "kimi"
    public static let kimiAccount = "kimi-code-plan"
    public static let minimax = "minimax"
    public static let minimaxAccount = "minimax-coding-plan"
    public static let gemini = "gemini"
    public static let copilot = "copilot"
    public static let providers = [claude, glm, codex, kimi, minimax, gemini, copilot]
    /// The only hosts a request may go to.
    public static let hosts: Set<String> = ["api.anthropic.com", "open.bigmodel.cn", "api.z.ai", "chatgpt.com", "api.kimi.com",
                                            "api.minimaxi.com", "api.minimax.io", GeminiQuotaAPI.host, "api.github.com"]

    static let interval: [String: TimeInterval] = [claude: 300, glm: 180, codex: 300, kimi: 180, minimax: 180, gemini: 300, copilot: 600]
    static let forcedInterval: TimeInterval = 30

    private let cacheFile: URL
    private let transport: Transport
    private let secrets: Secrets
    private let onChange: @Sendable ([String: Result]) -> Void
    private let clock: @Sendable () -> Date
    private var config = Config()
    private var results: [String: Result] = [:]
    private var claudeLogin: ClaudeCodeLogin.Login?
    /// Sign-ins a provider has turned down: asking again with the same one would only be turned down again.
    private var refused: [String: String] = [:]
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
        for provider in Self.providers where !new.asks(provider) {
            results[provider] = nil
            refused[provider] = nil
        }
        if !new.claude { claudeLogin = nil }
        if new.glmRegion != old.glmRegion { results[Self.glm] = nil }
        if new.minimaxRegion != old.minimaxRegion { results[Self.minimax] = nil }
        if old != new {
            save()
            onChange(results)
        }
        loop?.cancel()
        loop = nil
        guard new.asksAnyone else { return }
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
        for provider in Self.providers {
            guard config.asks(provider) else { continue }
            let wait = force ? Self.forcedInterval : (Self.interval[provider] ?? 300)
            if let last = results[provider]?.checkedAt, now.timeIntervalSince(last) < wait { continue }
            // A "no" at the Keychain stands until the user asks again.
            if !force, results[provider]?.state == .denied { continue }
            guard asking.insert(provider).inserted else { continue }
            var result: Result
            switch provider {
            case Self.claude: result = await askClaude(now: now)
            case Self.glm: result = await askGLM(now: now)
            case Self.kimi: result = await askKimi(now: now)
            case Self.minimax: result = await askMiniMax(now: now)
            case Self.gemini: result = await askGemini(now: now)
            case Self.copilot: result = await askCopilot(now: now)
            default: result = await askCodex(now: now)
            }
            asking.remove(provider)
            // Switched off while the answer was on its way: it is not wanted any more.
            guard config.asks(provider) else { continue }
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
        let pastItsDate = login.expiresAt.map { $0 <= now } ?? false
        // The date in the Keychain is Claude Code's note to itself; whether the sign-in still works is
        // Anthropic's call. One that was turned down is not offered again until Claude Code replaces it.
        if refused[Self.claude] == login.token {
            claudeLogin = nil
            return Result(state: pastItsDate ? .loginExpired : .unauthorized, checkedAt: now)
        }
        var (state, limits) = await ask(ClaudeUsageAPI.request(token: login.token)) { ClaudeUsageAPI.parse($0, now: now) }
        if state == .unauthorized || (pastItsDate && state != .ok) {
            // Past its date and not answered: whatever the refusal was called, the date is the reason.
            refused[Self.claude] = login.token
            claudeLogin = nil
            if pastItsDate { state = .loginExpired }
        }
        var out = limits
        if out != nil, out?.plan == nil { out?.plan = login.plan }
        return Result(limits: out, state: state, checkedAt: now)
    }

    private func askCodex(now: Date) async -> Result {
        let login: CodexLogin.Login
        switch secrets.codexLogin() {
        case .found(let found): login = found
        case .missing: return Result(state: .noLogin, checkedAt: now)
        case .denied: return Result(state: .denied, checkedAt: now)
        }
        if refused[Self.codex] == login.token { return Result(state: .loginExpired, checkedAt: now) }
        var (state, limits) = await ask(CodexUsageAPI.request(CodexUsageAPI.usage, login: login)) { CodexUsageAPI.parse($0, now: now) }
        if state == .unauthorized {
            // Codex renews its sign-in when it runs; until then this one is spent.
            refused[Self.codex] = login.token
            state = .loginExpired
        }
        if state == .ok, limits != nil {
            // A second question, and one that may go unanswered without harm.
            let request = CodexUsageAPI.request(CodexUsageAPI.savedResets, login: login)
            if let (data, status) = try? await send(request), (200..<300).contains(status) {
                limits?.resetsLeft = CodexUsageAPI.savedResets(data, now: now)
            }
        }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    private func askGLM(now: Date) async -> Result {
        guard let key = secrets.glmKey(), !key.isEmpty else { return Result(state: .noKey, checkedAt: now) }
        let (state, limits) = await ask(GLMQuotaAPI.request(key: key, region: config.glmRegion)) { GLMQuotaAPI.parse($0, now: now) }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    private func askKimi(now: Date) async -> Result {
        guard let key = secrets.kimiKey(), !key.isEmpty else { return Result(state: .noKey, checkedAt: now) }
        let (state, limits) = await ask(KimiUsageAPI.request(key: key)) { KimiUsageAPI.parse($0, now: now) }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    private func askMiniMax(now: Date) async -> Result {
        guard let key = secrets.minimaxKey(), !key.isEmpty else { return Result(state: .noKey, checkedAt: now) }
        var answer = MiniMaxQuotaAPI.Answer.unreadable
        let (state, _) = await ask(MiniMaxQuotaAPI.request(key: key, region: config.minimaxRegion)) { data in
            answer = MiniMaxQuotaAPI.parse(data, now: now)
            // Only a well-formed answer counts as one; a refusal in the body is told apart below.
            if case .limits(let limits) = answer { return limits }
            return answer == .refused ? ProviderLimits(windows: [], capturedAt: now, source: .provider) : nil
        }
        switch (state, answer) {
        case (.ok, .limits(let limits)): return Result(limits: limits, state: .ok, checkedAt: now)
        case (.ok, .refused): return Result(state: .unauthorized, checkedAt: now)
        default: return Result(state: state == .ok ? .unreadable : state, checkedAt: now)
        }
    }

    private func askGemini(now: Date) async -> Result {
        let login: GeminiLogin.Login
        switch secrets.geminiLogin() {
        case .found(let found): login = found
        case .missing: return Result(state: .noLogin, checkedAt: now)
        case .denied: return Result(state: .denied, checkedAt: now)
        }
        // The token is Gemini CLI's; once it has run out, Gemini CLI renews it, never this app.
        if let expiry = login.expiresAt, expiry <= now { return Result(state: .loginExpired, checkedAt: now) }
        if refused[Self.gemini] == login.token { return Result(state: .loginExpired, checkedAt: now) }
        var project: (id: String?, plan: String?) = (nil, nil)
        let (first, _) = await ask(GeminiQuotaAPI.projectRequest(token: login.token)) { data in
            project = GeminiQuotaAPI.project(data)
            return ProviderLimits(windows: [], capturedAt: now, source: .provider)
        }
        guard first == .ok else {
            if first == .unauthorized { refused[Self.gemini] = login.token }
            return Result(state: first == .unauthorized ? .loginExpired : first, checkedAt: now)
        }
        var (state, limits) = await ask(GeminiQuotaAPI.quotaRequest(token: login.token, project: project.id)) {
            GeminiQuotaAPI.parse($0, now: now)
        }
        if state == .unauthorized {
            refused[Self.gemini] = login.token
            state = .loginExpired
        }
        if limits != nil, let plan = project.plan, plan.count <= 24 { limits?.plan = plan }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    private func askCopilot(now: Date) async -> Result {
        let token: String
        switch secrets.githubLogin() {
        case .found(let found): token = found
        case .missing: return Result(state: .noLogin, checkedAt: now)
        case .denied: return Result(state: .denied, checkedAt: now)
        }
        // A sign-in GitHub turned down is not offered again until gh replaces it.
        if refused[Self.copilot] == token { return Result(state: .loginExpired, checkedAt: now) }
        var (state, limits) = await ask(CopilotQuotaAPI.request(token: token)) { CopilotQuotaAPI.parse($0, now: now) }
        if state == .unauthorized {
            refused[Self.copilot] = token
            state = .loginExpired
        }
        return Result(limits: limits, state: state, checkedAt: now)
    }

    /// The one door to the network: https, and only to a host on the list.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let host = request.url?.host, Self.hosts.contains(host), request.url?.scheme == "https" else { throw URLError(.unsupportedURL) }
        return try await transport(request)
    }

    private func ask(_ request: URLRequest, parse: (Data) -> ProviderLimits?) async -> (State, ProviderLimits?) {
        do {
            let (data, status) = try await send(request)
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

import Foundation
import Security

// Three more plans whose limits only the provider knows. The shapes are the
// ones cc-switch reads for the same plans; each lookup is opt-in and goes only
// to its own provider.

/// A number that may come as a number or as text ("100").
private func number(_ value: JSONValue?) -> Double? {
    guard let value else { return nil }
    if let double = value.doubleValue, double.isFinite { return double }
    return value.stringValue.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite ? $0 : nil }
}

/// A reset time as ISO text, or as seconds or milliseconds since 1970.
private func moment(_ value: JSONValue?) -> Date? {
    ISOTime.flexible(value).map(Date.init(timeIntervalSince1970:))
}

private func percent(_ value: Double) -> Double { min(max(value, 0), 100) }

/// Kimi Code's plan (Kimi For Coding), asked with a key of that plan. Each
/// window says how much of `limit` is still `remaining`: `limits[].detail` are
/// the short windows (five hours, unless `window` says otherwise), `usage` is
/// the week.
public enum KimiUsageAPI {
    public static let url = URL(string: "https://api.kimi.com/coding/v1/usages")!

    public static func request(key: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func used(_ item: JSONValue) -> Double? {
        guard let limit = number(item["limit"]), limit > 0 else { return nil }
        let remaining = number(item["remaining"]) ?? limit
        return percent((limit - remaining) / limit * 100)
    }

    /// `window: {duration, timeUnit}` → minutes.
    static func minutes(_ window: JSONValue?) -> Int? {
        guard let duration = number(window?["duration"]), duration > 0 else { return nil }
        let unit = (window?["timeUnit"]?.stringValue ?? "").uppercased()
        if unit.contains("HOUR") { return Int(duration) * 60 }
        if unit.contains("DAY") { return Int(duration) * 1440 }
        if unit.contains("SECOND") { return Int(duration) / 60 }
        return Int(duration)
    }

    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil else { return nil }
        var windows: [RateLimitWindow] = []
        for item in root["limits"]?.arrayValue ?? [] {
            guard let detail = item["detail"], let used = used(detail) else { continue }
            let length = minutes(item["window"]) ?? 300
            let id = length == 300 ? "five_hour" : "window_\(length)m"
            guard !windows.contains(where: { $0.id == id }) else { continue }
            windows.append(RateLimitWindow(id: id, usedPercent: used, resetsAt: moment(detail["resetTime"]), windowMinutes: length))
        }
        if let week = root["usage"], let used = used(week) {
            windows.append(RateLimitWindow(id: "seven_day", usedPercent: used, resetsAt: moment(week["resetTime"]), windowMinutes: 10080))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(windows: windows, capturedAt: now, source: .provider)
    }
}

/// MiniMax's Coding Plan, asked with a key of that plan. The answer gives what
/// is left, in percent; the week only counts on plans that have one
/// (`current_weekly_status` 1).
public enum MiniMaxQuotaAPI {
    public enum Region: String, Sendable, CaseIterable {
        /// minimaxi.com, the service in mainland China.
        case cn
        /// minimax.io.
        case global

        public var host: String { self == .cn ? "api.minimaxi.com" : "api.minimax.io" }
    }

    public static func url(_ region: Region) -> URL {
        URL(string: "https://\(region.host)/v1/api/openplatform/coding_plan/remains")!
    }

    public static func request(key: String, region: Region) -> URLRequest {
        var request = URLRequest(url: url(region), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public enum Answer: Equatable {
        case limits(ProviderLimits)
        /// The service said no in its own words (`base_resp`): usually the key.
        case refused
        case unreadable
    }

    public static func parse(_ data: Data, now: Date = Date()) -> Answer {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil else { return .unreadable }
        if let code = root["base_resp"]?["status_code"]?.intValue, code != 0 { return .refused }
        let models = root["model_remains"]?.arrayValue ?? []
        // The coding models; video and speech have buckets of their own.
        guard let item = models.first(where: { $0["model_name"]?.stringValue == "general" }) ?? (models.count == 1 ? models.first : nil)
        else { return .unreadable }
        var windows: [RateLimitWindow] = []
        if let left = number(item["current_interval_remaining_percent"]) {
            windows.append(RateLimitWindow(id: "five_hour", usedPercent: percent(100 - left), resetsAt: moment(item["end_time"]),
                                           windowMinutes: 300))
        }
        if item["current_weekly_status"]?.intValue == 1, let left = number(item["current_weekly_remaining_percent"]) {
            windows.append(RateLimitWindow(id: "seven_day", usedPercent: percent(100 - left), resetsAt: moment(item["weekly_end_time"]),
                                           windowMinutes: 10080))
        }
        guard !windows.isEmpty else { return .unreadable }
        return .limits(ProviderLimits(windows: windows, capturedAt: now, source: .provider))
    }
}

/// Gemini CLI's daily quotas, per model family, asked the way Gemini CLI asks:
/// first which Code Assist project the sign-in belongs to, then that
/// project's quota buckets. Only ever with the access token Gemini CLI saved,
/// while it is still good: it is never renewed here.
public enum GeminiQuotaAPI {
    static let base = "https://cloudcode-pa.googleapis.com/v1internal"
    public static let host = "cloudcode-pa.googleapis.com"

    static func post(_ method: String, token: String, body: JSONValue) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(base):\(method)")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.httpBody = body.serializedData(.compact)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func projectRequest(token: String) -> URLRequest {
        post("loadCodeAssist", token: token,
             body: .object(["metadata": .object(["ideType": .string("GEMINI_CLI"), "pluginType": .string("GEMINI")])]))
    }

    public static func quotaRequest(token: String, project: String?) -> URLRequest {
        post("retrieveUserQuota", token: token, body: .object(project.map { ["project": .string($0)] } ?? JSONObject()))
    }

    /// The project id (text, or an object with `id` / `projectId`) and the plan's name.
    public static func project(_ data: Data) -> (id: String?, plan: String?) {
        guard let root = try? JSONValue.parse(data) else { return (nil, nil) }
        let field = root["cloudaicompanionProject"]
        let id = field?.stringValue ?? (field?["id"] ?? field?["projectId"])?.stringValue
        return (id, root["currentTier"]?["name"]?.stringValue)
    }

    /// The family a model id belongs to: the windows are named after it.
    static func family(_ model: String) -> String {
        let id = model.lowercased()
        if id.contains("flash-lite") { return "flash_lite" }
        if id.contains("flash") { return "flash" }
        if id.contains("pro") { return "pro" }
        return id.replacingOccurrences(of: "-", with: "_")
    }

    /// `buckets[{modelId, remainingFraction, resetTime}]`: per family, the bucket with least left.
    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let buckets = (try? JSONValue.parse(data))?["buckets"]?.arrayValue else { return nil }
        var families: [String: (left: Double, resets: Date?)] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"]?.stringValue, let left = number(bucket["remainingFraction"]) else { continue }
            let name = family(model)
            let fraction = min(max(left, 0), 1)
            if let known = families[name], known.left <= fraction { continue }
            families[name] = (fraction, moment(bucket["resetTime"]))
        }
        guard !families.isEmpty else { return nil }
        let order = ["pro": 0, "flash": 1, "flash_lite": 2]
        let windows = families.sorted { (order[$0.key] ?? 3, $0.key) < (order[$1.key] ?? 3, $1.key) }.map {
            RateLimitWindow(id: "daily_\($0.key)", usedPercent: percent((1 - $0.value.left) * 100), resetsAt: $0.value.resets,
                            windowMinutes: 1440)
        }
        return ProviderLimits(windows: windows, capturedAt: now, source: .provider)
    }
}

/// The sign-in Gemini CLI saved: `~/.gemini/oauth_creds.json`, or its Keychain
/// item when it keeps it there. Read only while the user's switch is on.
public enum GeminiLogin {
    public struct Login: Sendable, Equatable {
        public var token: String
        public var expiresAt: Date?

        public init(token: String, expiresAt: Date?) {
            self.token = token
            self.expiresAt = expiresAt
        }
    }

    public enum Outcome: Sendable, Equatable {
        case found(Login)
        case missing
        case denied
    }

    static let keychainService = "gemini-cli-oauth"
    static let keychainAccount = "main-account"

    /// `{access_token, expiry_date (ms)}`, or the Keychain's `{token: {accessToken, expiresAt}}`.
    public static func parse(_ data: Data) -> Login? {
        guard let root = try? JSONValue.parse(data) else { return nil }
        let token = root["token"] ?? root
        guard let access = (token["accessToken"] ?? token["access_token"])?.stringValue, !access.isEmpty else { return nil }
        let expiry = moment(token["expiresAt"] ?? token["expiry_date"])
        return Login(token: access, expiresAt: expiry)
    }

    public static func read(home: URL) -> Outcome {
        if let data = try? Data(contentsOf: home.appendingPathComponent(".gemini/oauth_creds.json")), let login = parse(data) {
            return .found(login)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
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

/// Copilot's monthly allowances, as GitHub tells its own editors: premium requests,
/// chat messages, code completions. A counter that is unlimited, or not part of the
/// plan, is left out.
public enum CopilotQuotaAPI {
    public static let url = URL(string: "https://api.github.com/copilot_internal/user")!

    public static func request(token: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static let order = ["premium_interactions", "chat", "completions"]

    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), let snapshots = root["quota_snapshots"]?.objectValue else { return nil }
        let fallbackReset = moment(root["quota_reset_date_utc"] ?? root["quota_reset_date"])
        var windows: [RateLimitWindow] = []
        let keys = snapshots.members.map(\.key).sorted { (order.firstIndex(of: $0) ?? 9, $0) < (order.firstIndex(of: $1) ?? 9, $1) }
        for key in keys {
            guard let item = snapshots[key], item["unlimited"]?.boolValue != true, item["has_quota"]?.boolValue != false else { continue }
            var used: Double?
            if let left = number(item["percent_remaining"]) {
                used = 100 - left
            } else if let total = number(item["entitlement"]), total > 0, let left = number(item["remaining"] ?? item["quota_remaining"]) {
                used = (total - left) / total * 100
            }
            guard let used else { continue }
            let name = key == "premium_interactions" ? "premium" : key
            windows.append(RateLimitWindow(id: "copilot_" + name, usedPercent: percent(used),
                                           resetsAt: moment(item["quota_reset_at"]) ?? fallbackReset))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(windows: windows, capturedAt: now, plan: root["copilot_plan"]?.stringValue, source: .provider)
    }
}

/// The sign-in the GitHub CLI (`gh`) keeps: `oauth_token` for github.com in its
/// `hosts.yml`, or its Keychain item (`gh:github.com`). Read only while the user's
/// switch is on; used in memory and never written anywhere.
public enum GitHubLogin {
    public enum Outcome: Sendable, Equatable {
        case found(String)
        case missing
        case denied
    }

    static let keychainService = "gh:github.com"

    /// The `oauth_token` under the `github.com:` block of a `hosts.yml`.
    public static func token(inHosts text: String) -> String? {
        var inGitHub = false
        for raw in text.components(separatedBy: "\n") {
            let indented = raw.hasPrefix(" ") || raw.hasPrefix("\t")
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !indented { inGitHub = line == "github.com:" || line == "\"github.com\":"; continue }
            guard inGitHub, line.hasPrefix("oauth_token:") else { continue }
            let value = line.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// The Keychain keeps it as written by gh's keyring library, sometimes base64-wrapped.
    public static func unwrap(_ stored: String) -> String? {
        let prefix = "go-keyring-base64:"
        guard stored.hasPrefix(prefix) else { return stored.isEmpty ? nil : stored }
        return Data(base64Encoded: String(stored.dropFirst(prefix.count))).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func read(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Outcome {
        for name in ["GH_TOKEN", "GITHUB_TOKEN"] {
            if let token = environment[name], !token.isEmpty { return .found(token) }
        }
        let folder = environment["GH_CONFIG_DIR"].map(URL.init(fileURLWithPath:))
            ?? environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("gh") }
            ?? home.appendingPathComponent(".config/gh")
        if let text = try? String(contentsOf: folder.appendingPathComponent("hosts.yml"), encoding: .utf8),
           let token = token(inHosts: text) {
            return .found(token)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let stored = String(data: data, encoding: .utf8),
           let token = unwrap(stored) {
            return .found(token)
        }
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { return .denied }
        return .missing
    }
}

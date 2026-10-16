import Foundation

/// Kiro's plan: how many credits of this month's allowance are spent, the free
/// trial and bonus credits on top, and when it renews; the same call Kiro's own
/// app makes for its usage panel (`GET management.<region>.kiro.dev/getUsageLimits`).
/// Asked with the sign-in Kiro keeps on this Mac, only while it is still good;
/// off until the user switches it on.
public enum KiroQuotaAPI {
    public static func host(region: String) -> String { "management.\(region).kiro.dev" }
    public static let regions: Set<String> = ["us-east-1", "eu-central-1"]

    public static func request(login: KiroLogin.Login) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host(region: login.region)
        components.path = "/getUsageLimits"
        components.queryItems = [
            URLQueryItem(name: "origin", value: "AI_EDITOR"),
            URLQueryItem(name: "profileArn", value: login.profileArn),
            URLQueryItem(name: "resourceType", value: "AGENTIC_REQUEST"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        // How Kiro says which kind of sign-in the token is (IAM Identity Center or a social one).
        if let type = login.tokenType { request.setValue(type, forHTTPHeaderField: "TokenType") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value, let double = value.doubleValue ?? value.stringValue.flatMap(Double.init), double.isFinite else { return nil }
        return double
    }

    /// A reset as seconds since 1970 or ISO text.
    private static func moment(_ value: JSONValue?) -> Date? {
        ISOTime.flexible(value).map(Date.init(timeIntervalSince1970:))
    }

    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil else { return nil }
        let reset = moment(root["nextDateReset"])
        var windows: [RateLimitWindow] = []
        var items = root["usageBreakdownList"]?.arrayValue ?? []
        if items.isEmpty, let single = root["usageBreakdown"], single.objectValue != nil { items = [single] }
        for item in items {
            let kind = (item["resourceType"]?.stringValue ?? "credit").lowercased()
            let id = kind == "credit" || kind == "agentic_request" ? "kiro_credits" : "kiro_" + kind
            if let limit = number(item["usageLimitWithPrecision"] ?? item["usageLimit"]), limit > 0,
               let used = number(item["currentUsageWithPrecision"] ?? item["currentUsage"]), !windows.contains(where: { $0.id == id }) {
                windows.append(RateLimitWindow(id: id, usedPercent: min(max(used / limit * 100, 0), 100),
                                               resetsAt: moment(item["nextDateReset"]) ?? reset))
            }
            // A free trial runs beside the plan with its own allowance and end.
            let trial = item["freeTrialInfo"]
            if trial?["freeTrialStatus"]?.stringValue?.uppercased() == "ACTIVE",
               let limit = number(trial?["usageLimitWithPrecision"] ?? trial?["usageLimit"]), limit > 0,
               let used = number(trial?["currentUsageWithPrecision"] ?? trial?["currentUsage"]) {
                windows.append(RateLimitWindow(id: "kiro_trial", usedPercent: min(max(used / limit * 100, 0), 100),
                                               resetsAt: moment(trial?["freeTrialExpiry"])))
            }
            for bonus in item["bonuses"]?.arrayValue ?? [] where (bonus["status"]?.stringValue ?? "ACTIVE").uppercased() == "ACTIVE" {
                guard let limit = number(bonus["usageLimitWithPrecision"] ?? bonus["usageLimit"]), limit > 0,
                      let used = number(bonus["currentUsageWithPrecision"] ?? bonus["currentUsage"]),
                      !windows.contains(where: { $0.id == "kiro_bonus" }) else { continue }
                windows.append(RateLimitWindow(id: "kiro_bonus", usedPercent: min(max(used / limit * 100, 0), 100),
                                               resetsAt: moment(bonus["expiresAt"])))
            }
        }
        guard !windows.isEmpty else { return nil }
        let info = root["subscriptionInfo"]
        let plan = (info?["subscriptionTitle"] ?? info?["type"])?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        return ProviderLimits(windows: windows, capturedAt: now, plan: plan, source: .provider)
    }
}

/// The sign-in Kiro keeps on this Mac: `~/.aws/sso/cache/kiro-auth-token.json`
/// (`accessToken`, `expiresAt`, `authMethod`, `region`, sometimes `profileArn`) and,
/// for organisation sign-ins, the profile in Kiro's own storage
/// (`kiro.kiroagent/profile.json`, `arn`). Read only while the switch is on, used in
/// memory, never renewed and never written anywhere.
public enum KiroLogin {
    public struct Login: Sendable, Equatable {
        public var token: String
        public var profileArn: String
        public var region: String
        public var tokenType: String?
        public var expiresAt: Date?
    }

    public enum Outcome: Sendable, Equatable {
        case found(Login)
        case missing
        case expired
    }

    public static func tokenPath(home: URL) -> URL { home.appendingPathComponent(".aws/sso/cache/kiro-auth-token.json") }
    public static func profilePath(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json")
    }

    public static func read(home: URL, now: Date = Date()) -> Outcome {
        guard let data = try? Data(contentsOf: tokenPath(home: home)), data.count < 1_000_000,
              let root = try? JSONValue.parse(data), let token = root["accessToken"]?.stringValue, !token.isEmpty else { return .missing }
        let expires = ISOTime.flexible(root["expiresAt"]).map(Date.init(timeIntervalSince1970:))
        // Kiro renews its own sign-in while it runs; one past its date is left for Kiro.
        if let expires, expires <= now { return .expired }
        var arn = root["profileArn"]?.stringValue
        if arn?.isEmpty ?? true, let profile = try? Data(contentsOf: profilePath(home: home)), profile.count < 100_000 {
            arn = (try? JSONValue.parse(profile))?["arn"]?.stringValue
        }
        guard let arn, !arn.isEmpty else { return .missing }
        let parts = arn.split(separator: ":")
        let region = parts.count > 3 && KiroQuotaAPI.regions.contains(String(parts[3])) ? String(parts[3])
            : (root["region"]?.stringValue).flatMap { KiroQuotaAPI.regions.contains($0) ? $0 : nil } ?? "us-east-1"
        let tokenType: String?
        switch root["authMethod"]?.stringValue {
        case "IdC"?: tokenType = "SSO_OIDC"
        case "external_idp"?: tokenType = "EXTERNAL_IDP"
        default: tokenType = nil
        }
        return .found(Login(token: token, profileArn: arn, region: region, tokenType: tokenType, expiresAt: expires))
    }
}

/// What Kiro spent, in its own unit (credits), from the `usage_summary` record it writes
/// at the end of each turn in its session folders. Read-only; each file is read again
/// only when it has changed.
public final class KiroCredits {
    private struct Spent { var at: Date; var credits: Double }
    private var cache: [String: (stamp: (Date, UInt64), spent: [Spent])] = [:]
    private let root: URL

    public init(home: URL) { root = home.appendingPathComponent(".kiro/sessions") }

    public func totals(now: Date = Date(), calendar: Calendar = .current) -> UsageSnapshot.Credits? {
        let manager = FileManager.default
        var all: [Spent] = []
        var seen: Set<String> = []
        let monthAgo = now.addingTimeInterval(-31 * 86_400)
        for workspace in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for folder in (try? manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
            where folder.lastPathComponent.hasPrefix("sess_") {
                let file = folder.appendingPathComponent("messages.jsonl")
                guard let attributes = try? manager.attributesOfItem(atPath: file.path),
                      let modified = attributes[.modificationDate] as? Date, modified >= monthAgo,
                      let size = (attributes[.size] as? NSNumber)?.uint64Value else { continue }
                seen.insert(file.path)
                if let cached = cache[file.path], cached.stamp == (modified, size) {
                    all += cached.spent
                    continue
                }
                let spent = Self.read(file)
                cache[file.path] = ((modified, size), spent)
                all += spent
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        guard !all.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        func sum(since start: Date) -> Double { all.filter { $0.at >= start && $0.at <= now }.reduce(0) { $0 + $1.credits } }
        var credits = UsageSnapshot.Credits(unit: "credits")
        credits.fiveHours = sum(since: now.addingTimeInterval(-5 * 3600))
        credits.today = sum(since: today)
        credits.week = sum(since: calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        credits.month = sum(since: now.addingTimeInterval(-30 * 86_400))
        credits.days = (0..<7).reversed().map { back in
            let start = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return all.filter { $0.at >= start && $0.at < end }.reduce(0) { $0 + $1.credits }
        }
        guard credits.month > 0 else { return nil }
        return credits
    }

    private static func read(_ file: URL) -> [Spent] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        let needle = Data("usage_summary".utf8)
        var out: [Spent] = []
        for line in data.split(separator: 0x0A) where line.range(of: needle) != nil {
            guard let record = try? JSONValue.parse(Data(line)), record["payload"]?["type"]?.stringValue == "usage_summary",
                  let at = record["timestamp"]?.stringValue.flatMap(ISOTime.parse).map(Date.init(timeIntervalSince1970:)) else { continue }
            let used = (record["payload"]?["promptTurnSummaries"]?.arrayValue ?? []).reduce(0.0) { total, turn in
                guard let value = turn["usage"]?.doubleValue, value.isFinite, value >= 0, value < 100_000 else { return total }
                return total + value
            }
            if used > 0 { out.append(Spent(at: at, credits: used)) }
        }
        return out
    }
}

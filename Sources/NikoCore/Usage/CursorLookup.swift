import Foundation

/// Cursor's plan for the current billing cycle, as its own Spending page shows it
/// (`cursor.com/api/usage-summary`): how much of the included usage is spent, split
/// into Auto and the named (API) models, and on-demand spending when it is on.
/// Asked with the sign-in Cursor keeps on this Mac; off until the user switches it on.
public enum CursorQuotaAPI {
    public static let host = "cursor.com"
    public static let url = URL(string: "https://cursor.com/api/usage-summary")!

    public static func request(login: CursorLogin.Login) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        // The web app's session is "<user id>::<access token>", URL-encoded.
        request.setValue("WorkosCursorSessionToken=\(login.userID)%3A%3A\(login.token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value, let double = value.doubleValue ?? value.stringValue.flatMap(Double.init), double.isFinite else { return nil }
        return double
    }

    public static func parse(_ data: Data, now: Date = Date()) -> ProviderLimits? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil, root["isUnlimited"]?.boolValue != true else { return nil }
        let start = ISOTime.flexible(root["billingCycleStart"]).map(Date.init(timeIntervalSince1970:))
        let end = ISOTime.flexible(root["billingCycleEnd"]).map(Date.init(timeIntervalSince1970:))
        let minutes = start.flatMap { start in end.map { Int(($0.timeIntervalSince(start) / 60).rounded()) } }.flatMap { $0 > 0 ? $0 : nil }
        func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
        var windows: [RateLimitWindow] = []
        let plan = root["individualUsage"]?["plan"]
        if let plan, plan["enabled"]?.boolValue != false {
            var total = number(plan["totalPercentUsed"])
            if total == nil, let used = number(plan["used"]), let limit = number(plan["limit"]), limit > 0 { total = used / limit * 100 }
            if let total { windows.append(RateLimitWindow(id: "cursor_total", usedPercent: clamp(total), resetsAt: end, windowMinutes: minutes)) }
            if let auto = number(plan["autoPercentUsed"]) {
                windows.append(RateLimitWindow(id: "cursor_auto", usedPercent: clamp(auto), resetsAt: end, windowMinutes: minutes))
            }
            if let api = number(plan["apiPercentUsed"]) {
                windows.append(RateLimitWindow(id: "cursor_api", usedPercent: clamp(api), resetsAt: end, windowMinutes: minutes))
            }
        }
        if let onDemand = root["individualUsage"]?["onDemand"], onDemand["enabled"]?.boolValue == true,
           let used = number(onDemand["used"]), let limit = number(onDemand["limit"]), limit > 0 {
            windows.append(RateLimitWindow(id: "cursor_on_demand", usedPercent: clamp(used / limit * 100), resetsAt: end, windowMinutes: minutes))
        }
        guard !windows.isEmpty else { return nil }
        let membership = root["membershipType"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        return ProviderLimits(windows: windows, capturedAt: now, plan: membership, source: .provider)
    }
}

/// The sign-in Cursor's app keeps in its own state database
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, key
/// `cursorAuth/accessToken`), opened read-only. Read only while the switch is on,
/// used in memory and never written anywhere.
public enum CursorLogin {
    public struct Login: Sendable, Equatable {
        public var token: String
        public var userID: String
        public var expiresAt: Date?
    }

    public enum Outcome: Sendable, Equatable {
        case found(Login)
        case missing
    }

    public static func databasePath(home: URL) -> String {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
    }

    public static func read(home: URL) -> Outcome {
        let path = databasePath(home: home)
        guard FileManager.default.fileExists(atPath: path), let db = try? SQLiteDB(path: path, readOnly: true) else { return .missing }
        defer { db.close() }
        guard let rows = try? db.query("SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"),
              let token = rows.first?.first?.stringValue, let login = login(token: token) else { return .missing }
        return .found(login)
    }

    /// The user id and expiry come from the token itself (a JWT: `sub` is "auth0|user_…").
    public static func login(token raw: String) -> Login? {
        let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload), let claims = try? JSONValue.parse(data),
              let subject = claims["sub"]?.stringValue, !subject.isEmpty else { return nil }
        let user = subject.split(separator: "|").last.map(String.init) ?? subject
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return Login(token: token, userID: user, expiresAt: claims["exp"]?.doubleValue.map(Date.init(timeIntervalSince1970:)))
    }
}

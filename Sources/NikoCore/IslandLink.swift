import Foundation

/// What a `nikoisland://` link asks for. Any app or web page can open such a link, so
/// it can only ever do harmless things: be quiet for a while (at most a day), stop
/// being quiet, open the island or a settings page. It never answers a request.
public enum IslandLink: Equatable, Sendable {
    /// Quiet for this many minutes; nil until switched off by hand (at most a day).
    case quiet(minutes: Int?)
    case quietOff
    case open
    case switcher
    case settings(page: String?)

    public static let scheme = "nikoisland"
    static let longest = 24 * 60

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name.lowercased() == name }?.value }
        switch host {
        case "quiet":
            if path.first == "off" || value("off") != nil {
                self = .quietOff
            } else if let text = value("minutes") ?? value("for") {
                guard let minutes = Int(text), minutes >= 0 else { return nil }
                self = minutes == 0 ? .quietOff : .quiet(minutes: min(minutes, Self.longest))
            } else if let text = value("hours") {
                guard let hours = Double(text), hours.isFinite, hours >= 0 else { return nil }
                let minutes = Int((min(hours, 24) * 60).rounded())
                self = minutes == 0 ? .quietOff : .quiet(minutes: min(minutes, Self.longest))
            } else {
                self = .quiet(minutes: nil)
            }
        case "open", "island": self = .open
        case "switcher", "switch": self = .switcher
        case "settings": self = .settings(page: path.first)
        default: return nil
        }
    }
}

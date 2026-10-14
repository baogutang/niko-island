import CryptoKit
import Foundation

// A new version, if the user asked to be told (off by default; approved by the
// owner as an addition to SPEC §5). Once a day the app asks GitHub which
// release is the latest; that request carries nothing but this app's name and
// version. Installing one downloads that release's package for this Mac's
// architecture, checks it against the release's SHA256SUMS and its bundle, and
// only then puts it where the running app is.

/// A published release, as GitHub describes it.
public struct ReleaseInfo: Sendable, Equatable {
    public var version: String
    public var page: URL
    /// Asset name → download address.
    public var assets: [String: URL]

    public init(version: String, page: URL, assets: [String: URL]) {
        self.version = version
        self.page = page
        self.assets = assets
    }

    /// "apple-silicon" or "intel": the label the packages carry.
    public static var architectureLabel: String {
        #if arch(arm64)
        return "apple-silicon"
        #else
        return "intel"
        #endif
    }

    /// The zip for this Mac.
    public func package(label: String = ReleaseInfo.architectureLabel) -> URL? {
        assets["Niko-Island-\(version)-\(label).zip"]
    }

    /// The disk image for this Mac, for the browser.
    public func diskImage(label: String = ReleaseInfo.architectureLabel) -> URL? {
        assets["Niko-Island-\(version)-\(label).dmg"]
    }

    public var checksums: URL? { assets["SHA256SUMS"] }
}

public enum UpdateCheck {
    public static let repository = "baogutang/niko-island"
    public static let latest = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// Where a request of the updater may go: the API, and the hosts GitHub sends downloads to.
    public static let hosts: Set<String> = ["api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]
    public static let interval: TimeInterval = 86_400

    public static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("niko-island/\(NikoVersion.current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// `releases/latest`: drafts and pre-releases are not offered.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let root = try? JSONValue.parse(data), root.objectValue != nil,
              root["draft"]?.boolValue != true, root["prerelease"]?.boolValue != true,
              let tag = root["tag_name"]?.stringValue, let version = normalized(tag),
              let page = root["html_url"]?.stringValue.flatMap(URL.init(string:)), page.scheme == "https" else { return nil }
        var assets: [String: URL] = [:]
        for asset in root["assets"]?.arrayValue ?? [] {
            guard let name = asset["name"]?.stringValue, let url = asset["browser_download_url"]?.stringValue.flatMap(URL.init(string:)),
                  url.scheme == "https", let host = url.host, hosts.contains(host) else { continue }
            assets[name] = url
        }
        return ReleaseInfo(version: version, page: page, assets: assets)
    }

    /// "v0.9.1" → "0.9.1"; anything that is not dotted numbers is no version.
    public static func normalized(_ tag: String) -> String? {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0.count <= 6 }) else { return nil }
        return text
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The line for `file` in a SHA256SUMS listing.
    public static func checksum(for file: String, in listing: String) -> String? {
        for line in listing.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, String(fields.last!).trimmingCharacters(in: CharacterSet(charactersIn: "*")) == file else { continue }
            let digest = fields[0].lowercased()
            return digest.count == 64 && digest.allSatisfy(\.isHexDigit) ? digest : nil
        }
        return nil
    }

    public static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Asks, and installs when told to.
public actor Updater {
    public enum Failure: Error, Equatable, Sendable {
        case unreachable
        case noPackage
        case checksumMismatch
        case notOurApp
        case cannotReplace(String)
    }

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    public typealias Download = @Sendable (URLRequest, URL) async throws -> Int

    private let transport: Transport
    private let download: Download

    public init(transport: Transport? = nil, download: Download? = nil) {
        self.transport = transport ?? Updater.network
        self.download = download ?? Updater.fileDownload
    }

    /// The latest release, or nil when GitHub could not be asked or answered in a form not understood.
    public func latest() async -> ReleaseInfo? {
        guard let (data, status) = try? await transport(UpdateCheck.request(UpdateCheck.latest)), (200..<300).contains(status) else { return nil }
        return UpdateCheck.parse(data)
    }

    /// Downloads, checks and unpacks the release; returns the new app, not yet in place.
    public func prepare(_ release: ReleaseInfo, in folder: URL) async throws -> URL {
        guard let package = release.package(), let sums = release.checksums else { throw Failure.noPackage }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(package.lastPathComponent)
        guard let (listing, status) = try? await transport(UpdateCheck.request(sums)), (200..<300).contains(status),
              let expected = UpdateCheck.checksum(for: package.lastPathComponent, in: String(decoding: listing, as: UTF8.self)) else { throw Failure.unreachable }
        guard let code = try? await download(UpdateCheck.request(package), zip), (200..<300).contains(code) else { throw Failure.unreachable }
        guard UpdateCheck.sha256(of: zip) == expected else { throw Failure.checksumMismatch }
        let unpacked = folder.appendingPathComponent("unpacked")
        guard Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw Failure.notOurApp }
        let app = unpacked.appendingPathComponent("\(NikoVersion.displayName).app")
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == NikoVersion.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == release.version,
              Updater.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { throw Failure.notOurApp }
        return app
    }

    /// Puts the new app where the old one is; the old one goes to the Trash, so nothing is lost.
    /// `trash` returns where the old app went, so it can be put back if the new one cannot take its place.
    public nonisolated static func replace(_ current: URL, with new: URL, trash: (URL) throws -> URL? = Updater.trash) throws {
        let manager = FileManager.default
        guard current.pathExtension == "app", manager.fileExists(atPath: current.path),
              manager.fileExists(atPath: new.appendingPathComponent("Contents/Info.plist").path) else {
            throw Failure.cannotReplace("not an app bundle")
        }
        let trashed: URL?
        do {
            trashed = try trash(current)
        } catch {
            throw Failure.cannotReplace(error.localizedDescription)
        }
        do {
            try manager.moveItem(at: new, to: current)
        } catch {
            // Never leave the user without an app: the old one goes back where it was.
            if let trashed { try? manager.moveItem(at: trashed, to: current) }
            throw Failure.cannotReplace(error.localizedDescription)
        }
    }

    public nonisolated static func trash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: Network

    /// No cookies, no cache; a redirect is followed only to GitHub's own download hosts.
    private final class GitHubOnly: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard request.url?.scheme == "https", let host = request.url?.host, UpdateCheck.hosts.contains(host) else { return nil }
            return request
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: GitHubOnly(), delegateQueue: nil)
    }()

    private static func allowed(_ request: URLRequest) -> Bool {
        request.url?.scheme == "https" && request.url?.host.map(UpdateCheck.hosts.contains) == true
    }

    public static let network: Transport = { request in
        guard allowed(request) else { throw URLError(.unsupportedURL) }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public static let fileDownload: Download = { request, destination in
        guard allowed(request) else { throw URLError(.unsupportedURL) }
        let (file, response) = try await session.download(for: request)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

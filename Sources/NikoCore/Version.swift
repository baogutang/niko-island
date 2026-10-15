import Foundation

public enum NikoVersion {
    /// Marketing version. `scripts/make-app.sh` stamps the same value into Info.plist.
    public static let current = "0.11.0"
    public static let bundleIdentifier = "app.nikoisland.macos"
    public static let displayName = "Niko Island"
    /// Substring that tags every hook entry we own. Install/uninstall key off this and nothing else.
    public static let hookMarker = "niko-bridge"
    public static let statuslineMarker = "niko-statusline"
    public static let releasesURL = "https://github.com/baogutang/niko-island/releases/latest"
    public static let repositoryURL = "https://github.com/baogutang/niko-island"
}

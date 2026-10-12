import Foundation
import NikoCore

public enum NikoCLI {
    /// Returns an exit status when `arguments` name a CLI subcommand, or `nil`
    /// when the process should carry on and launch the menu-bar app.
    public static func run(arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "--version", "-v", "version":
            print("niko-island \(NikoVersion.current)")
            return 0
        case "--help", "-h", "help":
            print(usage)
            return 0
        default:
            // Finder/LaunchServices may pass `-psn_…`/`-NS…` style arguments: that is an app launch.
            if command.hasPrefix("-") { return nil }
            FileHandle.standardError.write(Data("niko-island: unknown command '\(command)'\n\n\(usage)\n".utf8))
            return 64
        }
    }

    static let usage = """
    Niko Island \(NikoVersion.current) — menu-bar companion for AI coding agents

    USAGE
      niko-island                 launch the menu-bar app
      niko-island --version       print the version
      niko-island --help          show this help
    """
}

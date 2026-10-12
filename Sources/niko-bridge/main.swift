import Foundation
import NikoCore

// Placeholder until M2: the bridge must already honour its one hard rule.
if CommandLine.arguments.contains("--version") {
    print("niko-bridge \(NikoVersion.current)")
}
exit(0)

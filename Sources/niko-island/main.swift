import Foundation
import NikoCore
import NikoIslandApp

// One binary, two personalities: `niko-island <subcommand>` is the CLI
// (install / uninstall / scan / …); with no subcommand it is the menu-bar app.
let arguments = Array(CommandLine.arguments.dropFirst())
if let status = NikoCLI.run(arguments: arguments) {
    exit(status)
}
runNikoIslandApp()

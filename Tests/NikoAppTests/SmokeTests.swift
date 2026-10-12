import XCTest
@testable import NikoIslandApp
import NikoCore

final class SmokeTests: XCTestCase {
    func testCLIVersionAndAppFallthrough() {
        XCTAssertEqual(NikoCLI.run(arguments: ["--version"]), 0)
        XCTAssertNil(NikoCLI.run(arguments: []))
        XCTAssertNil(NikoCLI.run(arguments: ["-psn_0_12345"]))
        XCTAssertEqual(NikoCLI.run(arguments: ["bogus"]), 64)
    }
}

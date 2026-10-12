import XCTest
@testable import NikoCore

final class JSONValueTests: XCTestCase {
    func testRoundTripPreservesOrderNumbersAndStyle() throws {
        let text = "{\n  \"b\": 1.0,\n  \"a\": [\n    1e3,\n    \"x/y\",\n    null,\n    true\n  ],\n  \"empty\": {},\n  \"list\": [],\n  \"u\": \"café ☕\"\n}\n"
        let value = try JSONValue.parse(text)
        XCTAssertEqual(value.objectValue?.keys, ["b", "a", "empty", "list", "u"])
        XCTAssertEqual(value.serialized(.detect(from: text)), text)
    }

    func testCompactRoundTrip() throws {
        let text = #"{"a":1,"b":[1,2,{"c":"d\n"}]}"#
        XCTAssertEqual(try JSONValue.parse(text).serialized(.detect(from: text)), text)
    }

    func testFourSpaceAndTabIndentDetected() throws {
        let four = "{\n    \"a\": 1\n}"
        XCTAssertEqual(try JSONValue.parse(four).serialized(.detect(from: four)), four)
        let tab = "{\n\t\"a\": {\n\t\t\"b\": 2\n\t}\n}\n"
        XCTAssertEqual(try JSONValue.parse(tab).serialized(.detect(from: tab)), tab)
    }

    func testEscapesAndSurrogates() throws {
        let value = try JSONValue.parse(#"{"s":"a\"b\\cé😀\t"}"#)
        XCTAssertEqual(value["s"]?.stringValue, "a\"b\\cé😀\t")
    }

    func testRejectsMalformed() {
        for bad in ["", "{", "{\"a\":}", "[1,]", "{\"a\":1,}", "nul", "\"abc", "{\"a\":1} x", "01", "1.", "[\"\u{01}\"]"] {
            XCTAssertThrowsError(try JSONValue.parse(bad), bad)
        }
    }

    func testDepthLimit() {
        let deep = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        XCTAssertThrowsError(try JSONValue.parse(deep))
    }

    func testBOMTolerated() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("{\"a\":1}".utf8))
        XCTAssertEqual(try JSONValue.parse(data)["a"]?.intValue, 1)
    }

    func testSemanticEquality() throws {
        let a = try JSONValue.parse(#"{"a":1,"b":[1.0,2]}"#)
        let b = try JSONValue.parse(#"{"b":[1,2],"a":1.0}"#)
        XCTAssertTrue(a.semanticallyEquals(b))
        XCTAssertNotEqual(a, b)
    }
}

import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// SPEC §4: English primary, zh-Hans secondary via a string catalog.
final class LocalizationTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func catalog() throws -> JSONObject {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Assets/Localizable.xcstrings"))
        return try XCTUnwrap(JSONValue.parse(data)["strings"]?.objectValue)
    }

    /// Every `L("…")` literal in the app sources.
    private func keysInSources() throws -> Set<String> {
        let directory = repoRoot.appendingPathComponent("Sources/NikoIslandApp")
        let regex = try NSRegularExpression(pattern: #"\bL\(\s*"((?:[^"\\]|\\.)*)""#)
        var keys: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(atPath: directory.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        return keys
    }

    private func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(@|lld|d|ld)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }.sorted()
    }

    func testEveryStringInTheAppIsTranslated() throws {
        let strings = try catalog()
        let verbs: Set<String> = ["starting", "thinking", "running", "reading", "editing", "finding", "fetching", "delegating",
                                  "working", "compacting", "waiting for you", "needs permission", "has a question"]
        let needed = try keysInSources().union(verbs)
        XCTAssertGreaterThan(needed.count, 60)
        for key in needed.sorted() {
            let translation = strings[key]?.at("localizations", "zh-Hans", "stringUnit", "value")?.stringValue
            XCTAssertNotNil(translation, "missing zh-Hans for “\(key)”")
            XCTAssertFalse(translation?.isEmpty ?? true, key)
            XCTAssertEqual(specifiers(translation ?? ""), specifiers(key), "format specifiers differ for “\(key)”")
        }
        let stale = Set(strings.keys).subtracting(needed)
        XCTAssertTrue(stale.isEmpty, "catalog entries no longer used: \(stale.sorted())")
    }

    func testActivityVerbsAreAClosedSet() {
        // The catalog can only translate verbs it knows about.
        let tools = ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "WebFetch", "Task", "mcp__x", "apply_patch", "shell"]
        let known: Set<String> = ["running", "reading", "editing", "finding", "fetching", "delegating", "working"]
        for tool in tools { XCTAssertTrue(known.contains(Activity.verb(forTool: tool)), tool) }
    }

    func testFormatHelperSubstitutesArguments() {
        XCTAssertEqual(L("Always allow %@", "Bash"), "Always allow Bash")
        XCTAssertEqual(L("Question %lld of %lld", 2, 5), "Question 2 of 5")
        XCTAssertEqual(L("%@ wants to edit %@", "Claude Code", "a.swift"), "Claude Code wants to edit a.swift")
    }
}

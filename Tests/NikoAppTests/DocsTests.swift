import XCTest
@testable import NikoCore
@testable import NikoIslandApp

/// Keeps the documentation honest with respect to the code (REVIEW "Docs honesty", "Release").
final class DocsTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    func testRelativeLinksInReadmesResolve() throws {
        for readme in ["README.md", "README.zh-CN.md"] {
            let text = try read(readme)
            let targets = matches(##"\]\(([^)#\s]+)\)"##, in: text) + matches(##"(?:src|href)="([^"#]+)""##, in: text)
            XCTAssertGreaterThan(targets.count, 10, readme)
            for target in targets where !target.hasPrefix("http") && !target.hasPrefix("mailto:") {
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(target).path), "\(readme) links to missing \(target)")
            }
            XCTAssertTrue(text.contains("https://github.com/baogutang/niko-island/releases/latest"), "\(readme): download must point at releases/latest")
            XCTAssertTrue(text.contains("xattr -cr"), "\(readme): Gatekeeper instructions")
            XCTAssertTrue(text.contains("uninstall"), "\(readme): uninstall instructions")
            XCTAssertTrue(text.contains("docs/ROADMAP.md"), "\(readme): roadmap link")
        }
    }

    func testReadmeAgentTableMatchesTheRegistry() throws {
        for readme in ["README.md", "README.zh-CN.md"] {
            let text = try read(readme)
            for agent in AgentRegistry.installable {
                // Every agent the installer can wire is listed together with the file it touches.
                let file = agent.files.first ?? ""
                let shown = file.hasSuffix("/hooks.json") && agent.id == "gemini" ? ".gemini/config/plugins/niko/" : file
                XCTAssertTrue(text.contains("~/" + shown), "\(readme) does not mention ~/\(shown) for \(agent.id)")
            }
            // Only the stable adapter may be described as such.
            XCTAssertEqual(AgentRegistry.defaultIDs, ["claude"])
            let stableWord = readme == "README.md" ? "| Stable |" : "| 稳定 |"
            XCTAssertEqual(text.components(separatedBy: stableWord).count - 1, 1, "\(readme): exactly one agent is stable")
        }
    }

    func testCommandsShownInDocsExist() throws {
        let help = NikoCLI.usage
        let docs = try ["README.md", "README.zh-CN.md", "docs/TESTPLAN.md", "website/index.html"].map(read).joined()
        for flag in ["--dry-run", "--purge", "--agents", "--all"] {
            XCTAssertTrue(help.contains(flag), "documented flag \(flag) is not in the CLI help")
            XCTAssertTrue(docs.contains(flag) || flag == "--all", flag)
        }
        for command in ["install", "uninstall", "pricing refresh"] {
            XCTAssertTrue(help.contains(command), command)
        }
        XCTAssertEqual(NikoCLI.run(arguments: ["help"]), 0)
    }

    func testWebsiteIsSelfContainedAndConsistent() throws {
        let html = try read("website/index.html")
        // No third-party scripts, fonts, trackers or stylesheets: only links the reader clicks.
        XCTAssertTrue(matches(#"<script[^>]*\ssrc="([^"]+)""#, in: html).isEmpty)
        XCTAssertTrue(matches(#"<link[^>]*rel="stylesheet"[^>]*href="([^"]+)""#, in: html).isEmpty)
        XCTAssertFalse(html.contains("@import"))
        XCTAssertFalse(html.contains("fonts.googleapis"))
        for source in matches(#"<img[^>]*\ssrc="([^"]+)""#, in: html) {
            XCTAssertFalse(source.hasPrefix("http"), "images are served with the page")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("website/" + source).path), source)
        }
        XCTAssertTrue(html.contains("https://github.com/baogutang/niko-island/releases/latest"))
        XCTAssertTrue(html.contains("width=device-width"))
        XCTAssertTrue(html.contains("not affiliated with"))
        XCTAssertTrue(html.contains("MIT"))
        // Every translatable element has a Chinese counterpart.
        let keys = Set(matches(#"data-i18n(?:-alt)?="([^"]+)""#, in: html))
        let translated = Set(matches(#"\n\s+"([a-z0-9.]+)":\s"#, in: html) + matches(#",\s"([a-z0-9.]+)":\s"#, in: html))
        XCTAssertTrue(keys.isSubset(of: translated), "untranslated: \(keys.subtracting(translated).sorted())")
    }

    func testLicenseAndNotices() throws {
        let license = try read("LICENSE")
        XCTAssertTrue(license.hasPrefix("MIT License"))
        XCTAssertTrue(license.contains("Permission is hereby granted, free of charge"))
        XCTAssertTrue(try read("Assets/LITELLM-NOTICE.txt").contains("Copyright (c) 2023 Berri AI"))
        XCTAssertTrue(try read("CHANGELOG.md").contains("## [\(NikoVersion.current)]"), "the release workflow reads this section")
    }

    func testVersionIsConsistent() throws {
        XCTAssertTrue(try read("scripts/make-app.sh").contains("Sources/NikoCore/Version.swift"))
        XCTAssertTrue(NikoVersion.releasesURL.hasSuffix("/releases/latest"))
        XCTAssertEqual(NikoVersion.bundleIdentifier, "app.nikoisland.macos")
    }
}

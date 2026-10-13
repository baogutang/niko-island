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
            // The pictures are the island, and the page says they are renders, not captures.
            XCTAssertTrue(text.contains("docs/images/island-sessions.png"), "\(readme): hero image")
            XCTAssertTrue(text.contains("docs/images/island-demo.gif"), "\(readme): demo")
            XCTAssertFalse(text.contains("panel-"), "\(readme): pictures of the old panel")
            XCTAssertTrue(text.contains("scripts/make-assets.sh"), "\(readme): where the pictures come from")
        }
    }

    func testReadmesDescribeSoundsAsTheyAre() throws {
        XCTAssertFalse(NikoSettings().soundsEnabled, "the READMEs say sounds are off by default")
        XCTAssertEqual(SoundEvent.allCases.filter { !$0.enabledByDefault }, [.started], "the READMEs say only 'work started' stays off")
        for readme in ["README.md", "README.zh-CN.md"] {
            let text = try read(readme)
            // File names and manifest categories a user is told to use must be the ones the code looks for.
            for event in SoundEvent.allCases {
                XCTAssertTrue(text.contains("`\(event.rawValue)`"), "\(readme): file name for \(event.rawValue)")
                XCTAssertTrue(SoundPack.categories(for: event).allSatisfy { text.contains("`\($0)`") }, "\(readme): pack categories for \(event.rawValue)")
            }
            for ext in ["wav", "aiff", "mp3", "m4a"] {
                XCTAssertTrue(UserSoundFiles.extensions.contains(ext), ext)
                XCTAssertTrue(text.contains("`.\(ext)`"), "\(readme): .\(ext)")
            }
            XCTAssertTrue(text.contains(SoundPack.manifestName), readme)
            XCTAssertTrue(text.contains("~/.niko-island/sounds/packs/"), readme)
            // Every creature shown has its picture.
            for name in ["starfish", "whale", "boat", "gull", "jellyfish", "turtle", "octopus", "puffer", "island"] {
                XCTAssertTrue(text.contains("docs/images/mascots/\(name).gif"), "\(readme): \(name)")
            }
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
        XCTAssertGreaterThan(keys.count, 100)
        for old in ["panel-sessions", "panel-question", "panel-usage"] { XCTAssertFalse(html.contains(old), old) }
        XCTAssertTrue(html.contains("https://baogutang.github.io/niko-island/island-sessions.png"), "share image")
    }

    /// The play buttons on the website run a JavaScript port of `SoundSynth`.
    /// This keeps the two scores identical, so the page plays what the app plays.
    func testWebsiteSoundPreviewsUseTheAppsScores() throws {
        let html = try read("website/index.html")
        let cue = try NSRegularExpression(pattern: #"(started|attention|completed|error|limit): \{ (?:duty: ([0-9.]+), )?notes: \[(.*?)\] \}"#)
        let note = try NSRegularExpression(pattern: #"\[([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\]"#)
        func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        let found = cue.matches(in: html, range: NSRange(html.startIndex..., in: html))
        // Island first, then 8-bit: five cues each.
        XCTAssertEqual(found.count, SoundEvent.allCases.count * BuiltInSoundSet.allCases.count)
        for (index, match) in found.enumerated() {
            let set = BuiltInSoundSet.allCases[index / SoundEvent.allCases.count]
            let event = try XCTUnwrap(group(match, 1, in: html).flatMap(SoundEvent.init(rawValue:)))
            XCTAssertEqual(event, SoundEvent.allCases[index % SoundEvent.allCases.count], "cue order")
            let (voice, notes) = SoundSynth.score(for: event, set: set)
            let duty = group(match, 2, in: html).flatMap(Double.init)
            switch voice {
            case .mallet: XCTAssertNil(duty, "\(set).\(event) is a mallet cue")
            case .square(let expected): XCTAssertEqual(duty, expected, "\(set).\(event) duty")
            }
            let body = try XCTUnwrap(group(match, 3, in: html))
            let listed = note.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { item in
                (1...4).compactMap { group(item, $0, in: body).flatMap(Double.init) }
            }
            XCTAssertEqual(listed.count, notes.count, "\(set).\(event) note count")
            for (shown, expected) in zip(listed, notes) where shown.count == 4 {
                XCTAssertEqual(440 * pow(2, (shown[0] - 69) / 12), expected.frequency, accuracy: 1e-9, "\(set).\(event) pitch")
                XCTAssertEqual(shown[1], expected.start, accuracy: 1e-9, "\(set).\(event) start")
                XCTAssertEqual(shown[2], expected.duration, accuracy: 1e-9, "\(set).\(event) duration")
                XCTAssertEqual(shown[3], expected.gain, accuracy: 1e-9, "\(set).\(event) gain")
            }
        }
        // The envelope constants of the port, as written in `SoundSynth.samples`.
        for constant in ["0.004", "0.28", "0.08", "7.5", "0.012", "0.55", "0.5 / peak"] {
            XCTAssertTrue(html.contains(constant), "synth constant \(constant)")
        }
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

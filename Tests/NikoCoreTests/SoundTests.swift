import XCTest
@testable import NikoCore

final class SoundSynthTests: XCTestCase {
    private func parse(_ wav: Data) -> (rate: Int, channels: Int, bits: Int, samples: [Int16])? {
        guard wav.count > 44, String(decoding: wav[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ", String(decoding: wav[36..<40], as: UTF8.self) == "data" else { return nil }
        func u16(_ at: Int) -> Int { Int(wav[at]) | Int(wav[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard u32(4) == wav.count - 8, u32(40) == wav.count - 44, u16(20) == 1 else { return nil }
        var samples: [Int16] = []
        var index = 44
        while index + 1 < wav.count {
            samples.append(Int16(bitPattern: UInt16(wav[index]) | UInt16(wav[index + 1]) << 8))
            index += 2
        }
        return (u32(24), u16(22), u16(34), samples)
    }

    func testEveryCueIsAValidShortAudibleWAV() throws {
        for set in BuiltInSoundSet.allCases {
            for event in SoundEvent.allCases {
                let wav = SoundSynth.wav(for: event, set: set)
                let audio = try XCTUnwrap(parse(wav), "\(set)/\(event)")
                XCTAssertEqual(audio.rate, 44_100)
                XCTAssertEqual(audio.channels, 1)
                XCTAssertEqual(audio.bits, 16)
                let seconds = Double(audio.samples.count) / 44_100
                XCTAssertGreaterThan(seconds, 0.15, "\(set)/\(event)")
                XCTAssertLessThan(seconds, 1.3, "\(set)/\(event): a cue, not a tune")
                XCTAssertEqual(seconds, SoundSynth.duration(of: event, set: set), accuracy: 0.001)
                let peak = audio.samples.map { abs(Int($0)) }.max() ?? 0
                XCTAssertGreaterThan(peak, 12_000, "\(set)/\(event) is audible")
                XCTAssertLessThan(peak, 20_000, "\(set)/\(event) leaves headroom")
                XCTAssertLessThan(abs(Int(audio.samples.first ?? 0)), 600, "\(set)/\(event) starts without a click")
                XCTAssertLessThan(abs(Int(audio.samples.last ?? 0)), 2_500, "\(set)/\(event) ends quietly")
            }
        }
    }

    func testCuesAreDeterministicAndDistinct() {
        var seen: Set<Data> = []
        for set in BuiltInSoundSet.allCases {
            for event in SoundEvent.allCases {
                let first = SoundSynth.wav(for: event, set: set)
                XCTAssertEqual(first, SoundSynth.wav(for: event, set: set), "same input, same bytes")
                XCTAssertTrue(seen.insert(first).inserted, "\(set)/\(event) duplicates another cue")
            }
        }
        XCTAssertEqual(seen.count, 10)
    }

    func testSourceRoundTripsThroughItsStoredForm() {
        let sources: [SoundSource] = [.builtIn(.island), .builtIn(.chiptune), .system, .files, .pack("my pack")]
        for source in sources { XCTAssertEqual(SoundSource(rawValue: source.rawValue), source) }
        XCTAssertEqual(SoundSource(rawValue: "nonsense"), .builtIn(.island))
        XCTAssertEqual(SoundEvent.allCases.filter(\.enabledByDefault), [.attention, .completed, .error, .limit])
    }
}

final class SoundPackTests: XCTestCase {
    private func makePack(_ scratch: Scratch, at relative: String, manifest: String, files: [String]) -> URL {
        scratch.write(relative + "/openpeon.json", manifest)
        for file in files {
            let url = scratch.file(relative + "/" + file)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? SoundSynth.wav(for: .completed, set: .island).write(to: url)
        }
        return scratch.file(relative)
    }

    private let manifest = """
    {"cesp_version":"1.0","name":"sample","display_name":"Sample Pack","categories":{
      "task.acknowledge":{"sounds":[{"file":"start.wav","label":"Start"}]},
      "input.required":{"sounds":[{"file":"need-1.wav"},{"file":"need-2.wav"}]},
      "task.complete":{"sounds":[{"file":"sub/done.mp3"}]},
      "task.error":{"sounds":[{"file":"../escape.wav"},{"file":"/etc/hosts"},{"file":"missing.wav"},{"file":"fail.ogg"}]},
      "resource.limit":{"sounds":[{"file":"limit.aiff"}]},
      "unrelated":"not an object"}}
    """

    func testLoadsAManifestAndMapsEvents() throws {
        let scratch = Scratch()
        let directory = makePack(scratch, at: "packs/sample", manifest: manifest,
                                 files: ["start.wav", "need-1.wav", "need-2.wav", "sub/done.mp3", "limit.aiff", "fail.ogg"])
        scratch.write("escape.wav", "outside the pack")
        let pack = try XCTUnwrap(SoundPack.load(directory: directory))
        XCTAssertEqual(pack.id, "sample")
        XCTAssertEqual(pack.displayName, "Sample Pack")
        XCTAssertEqual(pack.file(for: .started)?.lastPathComponent, "start.wav")
        XCTAssertEqual(pack.file(for: .attention, pick: { _ in 1 })?.lastPathComponent, "need-2.wav")
        XCTAssertEqual(pack.file(for: .attention, pick: { $0 + 5 })?.lastPathComponent, "need-2.wav", "an out-of-range pick is clamped")
        XCTAssertEqual(pack.file(for: .completed)?.path, directory.path + "/sub/done.mp3")
        XCTAssertEqual(pack.file(for: .limit)?.lastPathComponent, "limit.aiff")
        XCTAssertNil(pack.file(for: .error), "paths outside the pack, missing files and formats we cannot play are all dropped")
        XCTAssertNil(pack.categories["task.error"])
    }

    func testSessionStartIsTheFallbackForStarted() throws {
        let scratch = Scratch()
        let directory = makePack(scratch, at: "p", manifest: #"{"name":"p","categories":{"session.start":{"sounds":[{"file":"hello.wav"}]}}}"#,
                                 files: ["hello.wav"])
        let pack = try XCTUnwrap(SoundPack.load(directory: directory))
        XCTAssertEqual(pack.displayName, "p")
        XCTAssertEqual(pack.file(for: .started)?.lastPathComponent, "hello.wav")
        XCTAssertEqual(SoundPack.categories(for: .started), ["task.acknowledge", "session.start"])
    }

    func testRejectsFoldersThatAreNotPacks() {
        let scratch = Scratch()
        XCTAssertNil(SoundPack.load(directory: scratch.file("nothing-here")))
        XCTAssertNil(SoundPack.load(directory: makePack(scratch, at: "a", manifest: "not json", files: [])))
        XCTAssertNil(SoundPack.load(directory: makePack(scratch, at: "b", manifest: #"{"name":"b"}"#, files: [])))
        XCTAssertNil(SoundPack.load(directory: makePack(scratch, at: "c", manifest: #"{"categories":{"task.complete":{"sounds":[{"file":"gone.wav"}]}}}"#, files: [])),
                     "a pack with nothing playable is not offered")
    }

    func testDiscoversPacksInOurFolderAndTheSharedOne() {
        let scratch = Scratch()
        let paths = scratch.paths
        let home = scratch.file("home")
        _ = makePack(scratch, at: "ni/sounds/packs/mine", manifest: #"{"display_name":"Mine","categories":{"task.complete":{"sounds":[{"file":"a.wav"}]}}}"#, files: ["a.wav"])
        _ = makePack(scratch, at: "home/.openpeon/packs/shared", manifest: #"{"categories":{"task.complete":{"sounds":[{"file":"a.wav"}]}}}"#, files: ["a.wav"])
        _ = makePack(scratch, at: "home/.openpeon/packs/mine", manifest: #"{"display_name":"Shadowed","categories":{"task.complete":{"sounds":[{"file":"a.wav"}]}}}"#, files: ["a.wav"])
        _ = makePack(scratch, at: "ni/sounds/packs/broken", manifest: "{", files: [])
        let packs = SoundPack.discover(paths: paths, home: home)
        XCTAssertEqual(packs.map(\.id), ["mine", "shared"])
        XCTAssertEqual(packs.first?.displayName, "Mine", "our own folder wins over the shared one")
        XCTAssertTrue(SoundPack.discover(paths: Scratch().paths, home: home.appendingPathComponent("nope")).isEmpty)
    }

    func testUserFilesByEventName() throws {
        let scratch = Scratch()
        XCTAssertFalse(UserSoundFiles.hasAny(paths: scratch.paths))
        XCTAssertNil(UserSoundFiles.file(for: .attention, paths: scratch.paths))
        scratch.write("ni/sounds/attention.mp3", "x")
        scratch.write("ni/sounds/completed.txt", "not audio")
        XCTAssertTrue(UserSoundFiles.hasAny(paths: scratch.paths))
        XCTAssertEqual(UserSoundFiles.file(for: .attention, paths: scratch.paths)?.lastPathComponent, "attention.mp3")
        XCTAssertNil(UserSoundFiles.file(for: .completed, paths: scratch.paths))
    }
}

final class SoundSettingsTests: XCTestCase {
    func testDefaultsAreSilent() {
        let settings = NikoSettings()
        XCTAssertFalse(settings.soundsEnabled)
        for event in SoundEvent.allCases { XCTAssertFalse(settings.shouldPlay(event), "\(event)") }
        XCTAssertEqual(settings.soundSource, .builtIn(.island))
        XCTAssertEqual(settings.soundVolume, 0.7)
        XCTAssertEqual(settings.systemSound(for: .completed), "Glass")
        XCTAssertTrue(settings.expandOnHover && settings.expandOnAttention && settings.showCompletionToast && settings.showIslandWhenIdle)
    }

    func testMasterSwitchAndPerEventSwitches() {
        var settings = NikoSettings()
        settings.soundsEnabled = true
        XCTAssertEqual(SoundEvent.allCases.filter(settings.shouldPlay), [.attention, .completed, .error, .limit])
        settings.setSound(true, for: .started)
        settings.setSound(false, for: .limit)
        XCTAssertEqual(SoundEvent.allCases.filter(settings.shouldPlay), [.started, .attention, .completed, .error])
        settings.soundsEnabled = false
        XCTAssertTrue(SoundEvent.allCases.filter(settings.shouldPlay).isEmpty)
    }

    func testValuesPersistAndAreClamped() throws {
        let scratch = Scratch()
        var settings = NikoSettings()
        settings.soundSource = .pack("retro")
        settings.soundVolume = 3
        settings.setSystemSound("Hero", for: .attention)
        settings.expandOnHover = false
        XCTAssertTrue(settings.save(paths: scratch.paths))
        let loaded = NikoSettings.load(paths: scratch.paths)
        XCTAssertEqual(loaded.soundSource, .pack("retro"))
        XCTAssertEqual(loaded.soundVolume, 1)
        XCTAssertEqual(loaded.systemSound(for: .attention), "Hero")
        XCTAssertEqual(loaded.systemSound(for: .error), "Basso")
        XCTAssertFalse(loaded.expandOnHover)
        XCTAssertEqual(mode(of: scratch.paths.settingsFile), 0o600)
    }

    func testSettingsWrittenByTheFirstReleaseStillMeanTheSame() throws {
        // 0.1.0 had three per-event switches and no master switch.
        let old = try XCTUnwrap(JSONValue.parse(#"{"sounds":{"permission":true,"idle":false},"futureKey":42}"#).objectValue)
        let settings = NikoSettings(raw: old)
        XCTAssertTrue(settings.soundsEnabled, "a sound that was on stays on")
        XCTAssertTrue(settings.shouldPlay(.attention))
        XCTAssertFalse(settings.shouldPlay(.completed))
        XCTAssertFalse(settings.shouldPlay(.started))
        XCTAssertEqual(settings.raw["futureKey"]?.intValue, 42, "unknown keys survive")
        XCTAssertFalse(NikoSettings(raw: try XCTUnwrap(JSONValue.parse(#"{"sounds":{"idle":false}}"#).objectValue)).soundsEnabled)
    }
}

final class SessionPresentationTests: XCTestCase {
    private func session(_ fields: JSONObject) -> Session? {
        var store = SessionStore()
        var object = JSONObject(["source": .string("claude"), "hook_event_name": .string("PreToolUse"), "session_id": .string("s")])
        for member in fields.members { object[member.key] = member.value }
        guard let event = try? AgentEvent(json: .object(object)) else { return nil }
        store.apply(event)
        return store.ordered.first
    }

    func testHostNamesForCommonTerminals() {
        let cases: [(JSONObject, String?)] = [
            (["term_program": .string("iTerm.app")], "iTerm2"),
            (["iterm_session_id": .string("w0t0p0:GUID")], "iTerm2"),
            (["term_program": .string("Apple_Terminal")], "Terminal"),
            (["term_program": .string("ghostty")], "Ghostty"),
            (["term_program": .string("vscode")], "VS Code"),
            (["term_program": .string("vscode"), "bundle_id": .string("com.todesktop.230313mzl4w4u92")], "Cursor"),
            (["term_program": .string("WarpTerminal")], "Warp"),
            (["term_program": .string("iTerm.app"), "tmux": .string("/tmp/tmux-501/default,1,0"), "tmux_pane": .string("%2")], "iTerm2 · tmux"),
            (["term_program": .string("tmux"), "tmux": .string("/tmp/t,1,0"), "tmux_pane": .string("%0")], "tmux"),
            (["term_program": .string("something-new")], nil),
            ([:], nil),
        ]
        for (meta, expected) in cases {
            let made = session(["_niko": .object(meta)])
            XCTAssertEqual(made?.hostName, expected, "\(meta)")
        }
    }

    func testPromptsStartedAndFailedChanges() throws {
        var store = SessionStore()
        func apply(_ name: String, _ extra: JSONObject = [:]) throws -> SessionStore.Change {
            var object = JSONObject(["source": .string("claude"), "hook_event_name": .string(name), "session_id": .string("s"), "cwd": .string("/w/app")])
            for member in extra.members { object[member.key] = member.value }
            return store.apply(try AgentEvent(json: .object(object)))
        }
        let key = SessionKey(source: "claude", sessionID: "s")
        XCTAssertEqual(try apply("UserPromptSubmit", ["prompt": .string("first ask")]), .started(key))
        XCTAssertEqual(store[key]?.lastPrompt, "first ask")
        XCTAssertEqual(try apply("UserPromptSubmit", ["prompt": .string("second ask")]), .started(key))
        XCTAssertEqual(store[key]?.firstPrompt, "first ask")
        XCTAssertEqual(store[key]?.lastPrompt, "second ask")
        XCTAssertEqual(store[key]?.title, "app · first ask")
        XCTAssertEqual(try apply("StopFailure", ["error": .string("rate limited\nretry later")]), .failed(key))
        XCTAssertEqual(store[key]?.phase, .waiting)
        XCTAssertEqual(store[key]?.activity, Activity(verb: "hit an error", detail: "rate limited"))
        XCTAssertEqual(try apply("UserPromptSubmit"), .started(key))
        XCTAssertEqual(try apply("Stop"), .becameIdle(key))
    }

    func testClaudeWiringIncludesTheFailureHook() {
        XCTAssertTrue(AgentRegistry.claudeEvents.contains { $0.event == HookEvent.stopFailure })
        XCTAssertEqual(AgentRegistry.claudeEvents.count, 12)
        XCTAssertFalse(AgentRegistry.monitorEvents.contains { $0.event == HookEvent.stopFailure },
                       "experimental adapters keep to the common event names")
    }
}

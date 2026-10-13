import Foundation

/// The moments a sound can mark. Deliberately few: each one should mean something.
public enum SoundEvent: String, Sendable, CaseIterable {
    /// The agent picked up a prompt and started working.
    case started
    /// The agent is blocked on you: a permission request or a question.
    case attention
    /// The agent finished its turn.
    case completed
    /// The turn ended in an error.
    case error
    /// A rate-limit window is nearly used up.
    case limit

    /// Whether the cue is on once the master switch is on. "Started" fires on
    /// every prompt, so it stays opt-in.
    public var enabledByDefault: Bool { self != .started }

    /// macOS system sound used in "system" mode unless the user picks another.
    public var defaultSystemSound: String {
        switch self {
        case .started: return "Pop"
        case .attention: return "Ping"
        case .completed: return "Glass"
        case .error: return "Basso"
        case .limit: return "Sosumi"
        }
    }
}

/// Where sounds come from.
public enum SoundSource: Sendable, Equatable {
    /// Built-in cues, synthesised in code (no audio files ship with the app).
    case builtIn(BuiltInSoundSet)
    /// macOS system sounds, one per event.
    case system
    /// The user's own files: `~/.niko-island/sounds/<event>.<ext>`.
    case files
    /// A sound pack directory with an `openpeon.json` manifest.
    case pack(String)

    public init(rawValue: String) {
        switch rawValue {
        case "chiptune": self = .builtIn(.chiptune)
        case "system": self = .system
        case "files": self = .files
        case let value where value.hasPrefix("pack:"): self = .pack(String(value.dropFirst(5)))
        default: self = .builtIn(.island)
        }
    }

    public var rawValue: String {
        switch self {
        case .builtIn(let set): return set.rawValue
        case .system: return "system"
        case .files: return "files"
        case .pack(let id): return "pack:" + id
        }
    }
}

public enum BuiltInSoundSet: String, Sendable, CaseIterable {
    /// Soft mallet-like tones.
    case island
    /// Square-wave arpeggios in the spirit of old game consoles.
    case chiptune
}

/// Synthesises the built-in cues. Everything here is generated from a few
/// notes and an envelope, so the sounds are original and the output is
/// deterministic (which also makes it testable).
public enum SoundSynth {
    public static let sampleRate = 44_100

    struct Note {
        var frequency: Double
        /// Seconds from the start of the cue.
        var start: Double
        var duration: Double
        var gain: Double = 1
    }

    enum Voice {
        /// Sine with a touch of the octave and a fast exponential decay.
        case mallet
        /// Band-limited-ish square wave with the given duty cycle and a short release.
        case square(duty: Double)
    }

    private static func midi(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }

    /// The score for each cue. MIDI note numbers: 60 = middle C.
    static func score(for event: SoundEvent, set: BuiltInSoundSet) -> (voice: Voice, notes: [Note]) {
        switch (set, event) {
        case (.island, .started):
            return (.mallet, [Note(frequency: midi(72), start: 0, duration: 0.22, gain: 0.8),
                              Note(frequency: midi(79), start: 0.09, duration: 0.30)])
        case (.island, .attention):
            return (.mallet, [Note(frequency: midi(76), start: 0, duration: 0.28),
                              Note(frequency: midi(81), start: 0.13, duration: 0.28),
                              Note(frequency: midi(88), start: 0.26, duration: 0.55)])
        case (.island, .completed):
            return (.mallet, [Note(frequency: midi(72), start: 0, duration: 0.30, gain: 0.85),
                              Note(frequency: midi(76), start: 0.10, duration: 0.30, gain: 0.9),
                              Note(frequency: midi(79), start: 0.20, duration: 0.34),
                              Note(frequency: midi(84), start: 0.32, duration: 0.70)])
        case (.island, .error):
            return (.mallet, [Note(frequency: midi(64), start: 0, duration: 0.30),
                              Note(frequency: midi(63), start: 0.02, duration: 0.30, gain: 0.5),
                              Note(frequency: midi(57), start: 0.20, duration: 0.55)])
        case (.island, .limit):
            return (.mallet, [Note(frequency: midi(57), start: 0, duration: 0.24),
                              Note(frequency: midi(57), start: 0.22, duration: 0.24),
                              Note(frequency: midi(52), start: 0.44, duration: 0.50)])
        case (.chiptune, .started):
            return (.square(duty: 0.5), [Note(frequency: midi(72), start: 0, duration: 0.06),
                                         Note(frequency: midi(76), start: 0.06, duration: 0.06),
                                         Note(frequency: midi(79), start: 0.12, duration: 0.12)])
        case (.chiptune, .attention):
            return (.square(duty: 0.25), [Note(frequency: midi(81), start: 0, duration: 0.08),
                                          Note(frequency: midi(88), start: 0.09, duration: 0.08),
                                          Note(frequency: midi(81), start: 0.22, duration: 0.08),
                                          Note(frequency: midi(88), start: 0.31, duration: 0.16)])
        case (.chiptune, .completed):
            return (.square(duty: 0.5), [Note(frequency: midi(72), start: 0, duration: 0.07),
                                         Note(frequency: midi(76), start: 0.07, duration: 0.07),
                                         Note(frequency: midi(79), start: 0.14, duration: 0.07),
                                         Note(frequency: midi(84), start: 0.21, duration: 0.07),
                                         Note(frequency: midi(88), start: 0.28, duration: 0.24)])
        case (.chiptune, .error):
            return (.square(duty: 0.125), [Note(frequency: midi(67), start: 0, duration: 0.10),
                                           Note(frequency: midi(63), start: 0.11, duration: 0.10),
                                           Note(frequency: midi(60), start: 0.22, duration: 0.26)])
        case (.chiptune, .limit):
            return (.square(duty: 0.25), [Note(frequency: midi(57), start: 0, duration: 0.09),
                                          Note(frequency: midi(57), start: 0.14, duration: 0.09),
                                          Note(frequency: midi(52), start: 0.28, duration: 0.22)])
        }
    }

    /// Mono samples in -1…1.
    static func samples(for event: SoundEvent, set: BuiltInSoundSet) -> [Float] {
        let (voice, notes) = score(for: event, set: set)
        let rate = Double(sampleRate)
        let length = (notes.map { $0.start + $0.duration }.max() ?? 0) + 0.05
        var buffer = [Double](repeating: 0, count: Int(length * rate))
        for note in notes {
            let first = Int(note.start * rate)
            let count = Int(note.duration * rate)
            for index in 0..<count where first + index < buffer.count {
                let t = Double(index) / rate
                let phase = t * note.frequency
                let attack = min(1, t / 0.004)
                let value: Double
                switch voice {
                case .mallet:
                    let decay = exp(-t * 7.5)
                    let tone = sin(2 * .pi * phase) + 0.28 * sin(4 * .pi * phase) * exp(-t * 14) + 0.08 * sin(6 * .pi * phase) * exp(-t * 22)
                    value = tone * decay * attack
                case .square(let duty):
                    let cycle = phase - phase.rounded(.down)
                    let release = min(1, (note.duration - t) / 0.012)
                    value = (cycle < duty ? 1.0 : -1.0) * 0.55 * attack * max(0, release)
                }
                buffer[first + index] += value * note.gain
            }
        }
        // Normalise to a fixed peak so both sets sit at the same level.
        let peak = buffer.map(abs).max() ?? 0
        guard peak > 0 else { return buffer.map { _ in 0 } }
        let scale = 0.5 / peak
        return buffer.map { Float($0 * scale) }
    }

    /// A complete 16-bit mono WAV file.
    public static func wav(for event: SoundEvent, set: BuiltInSoundSet) -> Data {
        let pcm = samples(for: event, set: set)
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)                                  // PCM
        append16(1)                                  // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))             // byte rate
        append16(2)                                  // block align
        append16(16)                                 // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(byteCount)
        for sample in pcm {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * 32_767)))
        }
        return data
    }

    public static func duration(of event: SoundEvent, set: BuiltInSoundSet) -> Double {
        Double(samples(for: event, set: set).count) / Double(sampleRate)
    }
}

/// A folder of sounds described by an `openpeon.json` manifest:
/// `{ "name", "display_name", "categories": { "<category>": { "sounds": [ { "file" } ] } } }`.
public struct SoundPack: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var directory: String
    /// Category name → file names inside `directory`.
    public var categories: [String: [String]]

    public static let manifestName = "openpeon.json"
    /// Formats the system player can decode. (Ogg files in a pack are skipped.)
    public static let playableExtensions: Set<String> = ["wav", "aiff", "aif", "mp3", "m4a", "caf"]

    /// Manifest categories consulted for each event, in order.
    public static func categories(for event: SoundEvent) -> [String] {
        switch event {
        case .started: return ["task.acknowledge", "session.start"]
        case .attention: return ["input.required"]
        case .completed: return ["task.complete"]
        case .error: return ["task.error"]
        case .limit: return ["resource.limit"]
        }
    }

    public static func load(directory: URL) -> SoundPack? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName)), data.count < 1 << 20,
              let root = (try? JSONValue.parse(data))?.objectValue,
              let entries = root["categories"]?.objectValue else { return nil }
        var categories: [String: [String]] = [:]
        for member in entries.members {
            let files = (member.value["sounds"]?.arrayValue ?? []).compactMap { $0["file"]?.stringValue }.filter { name in
                // Stay inside the pack: plain relative names only, and only formats we can play.
                !name.hasPrefix("/") && !name.split(separator: "/").contains("..")
                    && playableExtensions.contains((name as NSString).pathExtension.lowercased())
                    && FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
            }
            if !files.isEmpty { categories[member.key] = files }
        }
        guard !categories.isEmpty else { return nil }
        let id = directory.lastPathComponent
        let name = (root["display_name"] ?? root["name"])?.stringValue ?? id
        return SoundPack(id: id, displayName: name, directory: directory.path, categories: categories)
    }

    /// Packs under `~/.niko-island/sounds/packs/` and, if present, `~/.openpeon/packs/`.
    public static func discover(paths: NikoPaths, home: URL = NikoPaths.userHome()) -> [SoundPack] {
        var found: [SoundPack] = []
        var seen: Set<String> = []
        for root in [paths.sounds.appendingPathComponent("packs"), home.appendingPathComponent(".openpeon/packs")] {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
            for name in names where !name.hasPrefix(".") {
                guard let pack = load(directory: root.appendingPathComponent(name)), seen.insert(pack.id).inserted else { continue }
                found.append(pack)
            }
        }
        return found
    }

    /// The file to play for an event, or nil when the pack has nothing for it.
    /// `pick` chooses among several candidates (random in the app, fixed in tests).
    public func file(for event: SoundEvent, pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> URL? {
        for category in SoundPack.categories(for: event) {
            guard let files = categories[category], !files.isEmpty else { continue }
            let index = min(max(pick(files.count), 0), files.count - 1)
            return URL(fileURLWithPath: directory).appendingPathComponent(files[index])
        }
        return nil
    }
}

public enum UserSoundFiles {
    /// File types looked for, in order of preference.
    public static let extensions = ["wav", "aiff", "aif", "mp3", "m4a", "caf"]

    /// `~/.niko-island/sounds/<event>.<ext>`: a single file per event.
    public static func file(for event: SoundEvent, paths: NikoPaths) -> URL? {
        for ext in extensions {
            let url = paths.sounds.appendingPathComponent("\(event.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    public static func hasAny(paths: NikoPaths) -> Bool {
        SoundEvent.allCases.contains { file(for: $0, paths: paths) != nil }
    }
}

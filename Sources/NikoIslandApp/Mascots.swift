import NikoCore
import SwiftUI

/// A tiny two-frame pixel creature. All sprites are original to this project
/// and live here as text: one character per pixel, looked up in a palette.
struct MascotSprite: Equatable {
    var name: String
    /// Two frames of equal size; rows of equal length. `.` is transparent.
    var frames: [[String]]
    var palette: [Character: Color]

    var columns: Int { frames.first?.first?.count ?? 0 }
    var rows: Int { frames.first?.count ?? 0 }

    func recolored(_ changes: [Character: Color]) -> MascotSprite {
        var copy = self
        for (key, value) in changes { copy.palette[key] = value }
        return copy
    }
}

enum Mascots {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    private static let ink = rgb(22, 24, 30)
    private static let white = rgb(246, 247, 250)

    /// A sea star with a small smile.
    static let starfish = MascotSprite(name: "starfish", frames: [[
        ".....aa.....",
        ".....aa.....",
        "....acaa....",
        "aaaaaaaaaaaa",
        ".aaaeaaeaaa.",
        "..aaabbaaa..",
        "...aaaaaa...",
        "..aaaaaaaa..",
        "..aaa..aaa..",
        ".aaa....aaa.",
        ".aa......aa.",
        "............",
    ], [
        ".....aa.....",
        ".....aa.....",
        "....acaa....",
        ".aaaaaaaaaa.",
        "aaaaeaaeaaaa",
        "..aaabbaaa..",
        "...aaaaaa...",
        "..aaaaaaaa..",
        ".aaa....aaa.",
        ".aa......aa.",
        "............",
        "............",
    ]], palette: ["a": rgb(245, 148, 104), "b": rgb(196, 96, 66), "c": rgb(255, 205, 170), "e": ink])

    /// A small whale with a spout.
    static let whale = MascotSprite(name: "whale", frames: [[
        "...c.c......",
        "....c.......",
        "............",
        "...aaaaa....",
        "..aaaaaaa..a",
        ".aaaaaaaaaaa",
        "aaeaaaaaaaaa",
        "aaaaaaaaaa.a",
        "awwwwwaaa...",
        ".wwwwwwa....",
        "............",
        "............",
    ], [
        "....c.......",
        "...c.c......",
        "....c.......",
        "...aaaaa....",
        "..aaaaaaa...",
        ".aaaaaaaaa.a",
        "aaeaaaaaaaaa",
        "aaaaaaaaaaaa",
        "awwwwwaaa..a",
        ".wwwwwwa....",
        "............",
        "............",
    ]], palette: ["a": rgb(98, 162, 240), "w": rgb(220, 236, 255), "c": rgb(170, 214, 255), "e": ink])

    /// A jellyfish whose tentacles sway.
    static let jellyfish = MascotSprite(name: "jellyfish", frames: [[
        "...aaaaaa...",
        "..aacaaaaa..",
        ".aacaaaaaaa.",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        ".aaaaaaaaaa.",
        "..b.b..b.b..",
        "..b.b..b.b..",
        ".b..b..b..b.",
        ".b.b....b.b.",
        "...b....b...",
        "............",
    ], [
        "...aaaaaa...",
        "..aacaaaaa..",
        ".aacaaaaaaa.",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        ".aaaaaaaaaa.",
        "..b.b..b.b..",
        ".b..b..b..b.",
        ".b.b....b.b.",
        "..b......b..",
        "..b......b..",
        "............",
    ]], palette: ["a": rgb(170, 160, 250), "b": rgb(126, 116, 214), "c": rgb(220, 214, 255), "e": ink])

    /// A turtle on a stroll.
    static let turtle = MascotSprite(name: "turtle", frames: [[
        "............",
        "............",
        "...bbbbb....",
        "..bbabbabb..",
        ".bbabbbbabb.",
        ".bbbbbbbbbaa",
        "abbbbabbbbae",
        "..aaaaaaaaa.",
        "..aa....aa..",
        "..aa....aa..",
        "............",
        "............",
    ], [
        "............",
        "............",
        "...bbbbb....",
        "..bbabbabb..",
        ".bbabbbbabb.",
        ".bbbbbbbbbaa",
        "abbbbabbbbae",
        "..aaaaaaaaa.",
        ".aa......aa.",
        ".aa......aa.",
        "............",
        "............",
    ]], palette: ["a": rgb(150, 214, 150), "b": rgb(72, 150, 96), "e": ink])

    /// A gull that flaps now and then.
    static let gull = MascotSprite(name: "gull", frames: [[
        "............",
        "....wwww....",
        "...wwwwww...",
        "...wewwew...",
        "...wwoowww..",
        "..wwwwwwww..",
        ".gwwwwwwwwg.",
        ".ggwwwwwwgg.",
        "..gwwwwwwg..",
        "...wwwwww...",
        "....o..o....",
        "............",
    ], [
        "............",
        "....wwww....",
        "...wwwwww...",
        "...wewwew...",
        "g..wwoowww.g",
        "gg.wwwwww.gg",
        ".ggwwwwwwgg.",
        "..gwwwwwwg..",
        "...wwwwww...",
        "...wwwwww...",
        "....o..o....",
        "............",
    ]], palette: ["w": white, "g": rgb(160, 170, 186), "o": rgb(245, 170, 70), "e": ink])

    /// A little boat riding the swell.
    static let boat = MascotSprite(name: "boat", frames: [[
        ".....w......",
        ".....ww.....",
        ".....www....",
        ".....wwww...",
        ".....wwwww..",
        ".....m......",
        "bbbbbbbbbbbb",
        ".bbebbbbebb.",
        "..bbbbbbbb..",
        "c.cc.cc.cc.c",
        "............",
        "............",
    ], [
        "............",
        ".....w......",
        ".....ww.....",
        ".....www....",
        ".....wwww...",
        ".....wwwww..",
        ".....m......",
        "bbbbbbbbbbbb",
        ".bbebbbbebb.",
        ".cbbbbbbbbc.",
        "cc.cc.cc.cc.",
        "............",
    ]], palette: ["w": white, "m": rgb(150, 156, 170), "b": rgb(120, 134, 160), "c": rgb(110, 190, 240), "e": ink])

    /// An octopus with curly arms.
    static let octopus = MascotSprite(name: "octopus", frames: [[
        "...aaaaaa...",
        "..aacaaaaa..",
        ".aacaaaaaaa.",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        ".aaaabbaaaa.",
        "..aaaaaaaa..",
        ".aaaaaaaaaa.",
        "aa.aa..aa.aa",
        "a..a....a..a",
        "............",
        "............",
    ], [
        "...aaaaaa...",
        "..aacaaaaa..",
        ".aacaaaaaaa.",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        ".aaaabbaaaa.",
        "..aaaaaaaa..",
        ".aaaaaaaaaa.",
        ".aa.aa.aa.a.",
        ".a...a..a.aa",
        "............",
        "............",
    ]], palette: ["a": rgb(250, 150, 190), "b": rgb(200, 96, 140), "c": rgb(255, 208, 226), "e": ink])

    /// A pufferfish, mildly alarmed.
    static let puffer = MascotSprite(name: "puffer", frames: [[
        "....a..a....",
        "..a.aaaa.a..",
        "...aacaaa...",
        "a.aaeaaeaa.a",
        "..aaaaaaaa..",
        "..aaawwaaa.b",
        "a.aaaaaaaabb",
        "...aaaaaa..b",
        "..a.aaaa.a..",
        "....a..a....",
        "............",
        "............",
    ], [
        "............",
        "....aaaa....",
        "...aacaaa...",
        "..aaeaaeaa..",
        "..aaaaaaaa..",
        "..aaawwaaab.",
        "..aaaaaaaabb",
        "...aaaaaa.b.",
        "....aaaa....",
        "............",
        "............",
        "............",
    ]], palette: ["a": rgb(246, 210, 96), "b": rgb(214, 160, 60), "c": rgb(255, 240, 180), "w": white, "e": ink])

    /// A crab waving its claws.
    static let crab = MascotSprite(name: "crab", frames: [[
        "............",
        "a..a....a..a",
        "aa.a....a.aa",
        ".aa......aa.",
        "..aaaaaaaa..",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        "..aabbbbaa..",
        ".a.aaaaaa.a.",
        "a..a....a..a",
        "............",
        "............",
    ], [
        "a..a....a..a",
        "aa.a....a.aa",
        ".aa......aa.",
        "..a......a..",
        "..aaaaaaaa..",
        ".aaeaaaaeaa.",
        ".aaaaaaaaaa.",
        "..aabbbbaa..",
        "a..aaaaaa..a",
        ".a.a....a.a.",
        "............",
        "............",
    ]], palette: ["a": rgb(236, 98, 92), "b": rgb(178, 60, 62), "e": ink])

    /// The island itself: used for unknown agents and for the app's own states.
    static let island = MascotSprite(name: "island", frames: [[
        "....gg.gg...",
        "...gggggg...",
        "..gg.tt.gg..",
        ".....tt.....",
        ".....tt.....",
        "....tt......",
        "....tt......",
        "..ssssssss..",
        ".ssssssssss.",
        "cc.cc.cc.cc.",
        "............",
        "............",
    ], [
        "...gg.gg....",
        "..gggggg.g..",
        "..g..tt.gg..",
        ".....tt.....",
        ".....tt.....",
        "....tt......",
        "....tt......",
        "..ssssssss..",
        ".ssssssssss.",
        ".cc.cc.cc.cc",
        "............",
        "............",
    ]], palette: ["g": rgb(110, 214, 150), "t": rgb(176, 124, 84), "s": rgb(240, 214, 150), "c": rgb(110, 190, 240)])

    /// Every creature, for the picker in Settings.
    static let all: [MascotSprite] = [starfish, whale, jellyfish, turtle, gull, boat, octopus, puffer, crab, island]

    static func named(_ name: String) -> MascotSprite? { all.first { $0.name == name } }

    /// The creature for an agent, honouring what the user picked.
    static func sprite(for source: String, choices: [String: String]) -> MascotSprite {
        choices[source].flatMap(named) ?? sprite(for: source)
    }

    /// Which creature stands for which agent.
    static func sprite(for source: String) -> MascotSprite {
        switch source {
        case "claude": return starfish
        case "codex": return whale
        case "cursor": return boat
        case "copilot": return gull
        case "zcode": return crab
        case "codebuddy":
            return gull.recolored(["a": rgb(150, 196, 255), "b": rgb(96, 140, 214)])
        case "gemini": return jellyfish
        case "qwen", "qwenwork":
            return jellyfish.recolored(["a": rgb(120, 212, 226), "b": rgb(74, 160, 180), "c": rgb(206, 244, 250)])
        case "grok": return puffer
        case "factory":
            return puffer.recolored(["a": rgb(246, 170, 104), "b": rgb(206, 120, 66), "c": rgb(255, 220, 190)])
        case "opencode", "mimocode": return turtle
        case "trae", "trae-cn": return octopus
        case "kiro":
            return octopus.recolored(["a": rgb(190, 160, 250), "b": rgb(136, 104, 206), "c": rgb(228, 214, 255)])
        case "windsurf":
            return boat.recolored(["w": rgb(160, 236, 220), "b": rgb(70, 150, 150)])
        case "qoder", "qoder-cn", "qoderwork":
            return turtle.recolored(["a": rgb(120, 220, 196), "b": rgb(52, 150, 132)])
        case "kimi":
            return whale.recolored(["a": rgb(120, 120, 140), "c": rgb(196, 198, 214)])
        case "minimax":
            return starfish.recolored(["a": rgb(240, 110, 150), "b": rgb(190, 70, 110), "c": rgb(255, 196, 214)])
        case "devin":
            return crab.recolored(["a": rgb(110, 170, 250), "b": rgb(64, 116, 200)])
        case "amp":
            return puffer.recolored(["a": rgb(250, 130, 90), "b": rgb(204, 86, 56), "c": rgb(255, 206, 186)])
        default: return island
        }
    }
}

/// An agent's creature. In vector by default: soft shading, a face that shows
/// the mood, the species' own movement; the Pixel style keeps the pixel sprites.
/// Animated only while `animated` is true, so idle rows cost nothing.
struct MascotView: View {
    /// Set when the view stands for an agent: the user's choice of creature applies.
    var source: String?
    private var fixed: MascotSprite
    var size: CGFloat = 30
    var animated = false
    /// How it feels; by default at work while animated, at rest otherwise.
    var mood: CreatureMood?
    /// Keeps creatures of different sessions out of step.
    var seed: String?
    /// Fixed frame for documentation images.
    var frame: Int?
    @Environment(\.isStaticPreview) private var isStaticPreview
    @Environment(\.mascotFrame) private var mascotFrame
    @Environment(\.look) private var look

    init(source: String, size: CGFloat = 30, animated: Bool = false, mood: CreatureMood? = nil, seed: String? = nil, frame: Int? = nil) {
        self.source = source
        self.fixed = Mascots.sprite(for: source)
        self.size = size
        self.animated = animated
        self.mood = mood
        self.seed = seed
        self.frame = frame
    }

    init(sprite: MascotSprite, size: CGFloat = 30, animated: Bool = false, mood: CreatureMood? = nil, seed: String? = nil, frame: Int? = nil) {
        self.fixed = sprite
        self.size = size
        self.animated = animated
        self.mood = mood
        self.seed = seed
        self.frame = frame
    }

    private var sprite: MascotSprite {
        source.map { Mascots.sprite(for: $0, choices: look.mascots) } ?? fixed
    }

    private var feeling: CreatureMood { mood ?? (animated ? .working : .idle) }

    var body: some View {
        Group {
            if let source, !look.showMascots {
                // Creatures switched off: a plain dot in the agent's colour.
                Circle().fill(AgentTint.color(for: source)).frame(width: size * 0.42, height: size * 0.42)
            } else if look.style == .pixel {
                pixels
            } else {
                // Documentation images pick the moment; creatures that would not be moving stay still.
                let picture = frame ?? (isStaticPreview ? (animated ? mascotFrame : nil) : nil)
                CreatureCanvas(sprite: sprite, mood: feeling, lively: animated && !isStaticPreview, seed: Self.seed(seed ?? source ?? sprite.name),
                               moment: picture.map { 0.18 + Double($0) * 0.31 }, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 0…1 from any text, the same on every run.
    static func seed(_ text: String) -> Double {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Double(hash % 10_000) / 10_000
    }

    @ViewBuilder
    private var pixels: some View {
        if animated, frame == nil, !isStaticPreview {
            TimelineView(.periodic(from: .now, by: 0.55)) { context in
                canvas(frame: Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2)
            }
        } else {
            canvas(frame: frame ?? (animated ? mascotFrame : 0))
        }
    }

    private func canvas(frame index: Int) -> some View {
        let rows = sprite.frames[index % sprite.frames.count]
        let palette = sprite.palette
        let columns = sprite.columns
        let rowCount = sprite.rows
        return Canvas { context, canvasSize in
            // Whole-pixel cells keep the edges crisp at any size.
            let cell = floor(min(canvasSize.width / CGFloat(columns), canvasSize.height / CGFloat(rowCount)) * 2) / 2
            let originX = (canvasSize.width - cell * CGFloat(columns)) / 2
            let originY = (canvasSize.height - cell * CGFloat(rowCount)) / 2
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = palette[character] else { continue }
                    let rect = CGRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell, width: cell + 0.3, height: cell + 0.3)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

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

    static let all: [MascotSprite] = [starfish, whale, jellyfish, turtle, gull, boat, octopus, puffer, island]

    /// Which creature stands for which agent.
    static func sprite(for source: String) -> MascotSprite {
        switch source {
        case "claude": return starfish
        case "codex": return whale
        case "cursor": return boat
        case "copilot": return gull
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
        default: return island
        }
    }
}

/// Draws a sprite on a pixel grid. Animated only while `animated` is true, so
/// idle rows cost nothing.
struct MascotView: View {
    var sprite: MascotSprite
    var size: CGFloat = 30
    var animated = false
    /// Fixed frame for documentation images.
    var frame: Int?
    @Environment(\.isStaticPreview) private var isStaticPreview
    @Environment(\.mascotFrame) private var mascotFrame

    init(source: String, size: CGFloat = 30, animated: Bool = false, frame: Int? = nil) {
        self.sprite = Mascots.sprite(for: source)
        self.size = size
        self.animated = animated
        self.frame = frame
    }

    init(sprite: MascotSprite, size: CGFloat = 30, animated: Bool = false, frame: Int? = nil) {
        self.sprite = sprite
        self.size = size
        self.animated = animated
        self.frame = frame
    }

    var body: some View {
        Group {
            if animated, frame == nil, !isStaticPreview {
                TimelineView(.periodic(from: .now, by: 0.55)) { context in
                    canvas(frame: Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2)
                }
            } else {
                // Documentation images pick the frame; creatures that would not be moving stay on the first.
                canvas(frame: frame ?? (animated ? mascotFrame : 0))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

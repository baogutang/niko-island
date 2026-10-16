import NikoCore
import SwiftUI

/// A tiny two-frame pixel creature. All sprites are original to this project
/// and live here as text: one character per pixel, looked up in a palette.
struct MascotSprite: Equatable {
    var name: String
    /// Two frames of equal size; rows of equal length. `.` is transparent.
    var frames: [[String]]
    var palette: [Character: Color]
    /// The pet this figure draws (every figure has one; the frames are its plain picture).
    var pet: PixelPet?

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

    /// The island itself, our own drawing: the app's mascot, and the pet of agents it does not know.
    static let islandArt = MascotSprite(name: "island", frames: [[
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

    static let island = figure(PixelPets.island)

    /// A pet as the figure the views draw.
    static func figure(_ pet: PixelPet) -> MascotSprite {
        MascotSprite(name: pet.name, frames: [pet.rows], palette: pet.palette, pet: pet)
    }

    /// Every pet, for the picker in Settings.
    static let all: [MascotSprite] = PixelPets.all.map(figure)

    static func named(_ name: String) -> MascotSprite? { PixelPets.named(name).map(figure) }

    /// The pet for an agent, honouring what the user picked.
    static func sprite(for source: String, choices: [String: String]) -> MascotSprite {
        choices[source].flatMap(named) ?? sprite(for: source)
    }

    /// Which pet stands for which agent: its own.
    static func sprite(for source: String) -> MascotSprite { figure(PixelPets.pet(for: source)) }
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


}

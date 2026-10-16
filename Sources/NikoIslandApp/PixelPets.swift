import SwiftUI

/// An agent's pet: the agent's own mascot or mark, as pixels. Clawd is drawn from the
/// glyphs Claude Code draws him with; every other pet was pixelated from the agent's
/// official icon or logo (the source is named on each). The marks belong to their
/// owners and are shown only to say which agent a session is.
struct PixelPet: Equatable {
    var name: String
    /// One character per pixel, looked up in `palette`; `.` is transparent.
    var rows: [String]
    var palette: [Character: Color]
    /// The pixels that are eyes, closed for a blink.
    var eye: Character?
    /// Other poses of the same pet (Clawd's), by name.
    var poses: [String: [String]] = [:]

    init(name: String, rows: [String], palette: [Character: Color], eye: Character? = nil, poses: [String: [String]] = [:]) {
        self.name = name
        // One box around every pose, so changing pose never shifts the pet.
        let box = PixelPet.box(of: [rows] + Array(poses.values))
        self.rows = PixelPet.cropped(rows, to: box)
        self.palette = palette
        self.eye = eye
        self.poses = poses.mapValues { PixelPet.cropped($0, to: box) }
    }

    var columns: Int { rows.map(\.count).max() ?? 0 }

    /// The rows and columns that hold anything, across several drawings of the same size.
    static func box(of drawings: [[String]]) -> (top: Int, bottom: Int, left: Int, right: Int)? {
        var top = Int.max, bottom = -1, left = Int.max, right = -1
        for rows in drawings {
            for (r, line) in rows.enumerated() {
                for (c, ch) in line.enumerated() where ch != "." && ch != " " {
                    top = min(top, r); bottom = max(bottom, r); left = min(left, c); right = max(right, c)
                }
            }
        }
        return bottom < 0 ? nil : (top, bottom, left, right)
    }

    static func cropped(_ rows: [String], to box: (top: Int, bottom: Int, left: Int, right: Int)?) -> [String] {
        guard let box else { return rows }
        let lines = rows.map(Array.init)
        return (box.top...box.bottom).map { r in
            String((box.left...box.right).map { c in r < lines.count && c < lines[r].count ? lines[r][c] : "." })
        }
    }
}

private func hex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

enum PixelPets {
    // MARK: Clawd

    /// Claude Code's Clawd, built the way Claude Code builds him: a top row of arm,
    /// eyes and arm, a body row, and a row of feet, in quarter-block characters
    /// (the tables below are Claude Code 2.1's own).
    enum Clawd {
        static let body = hex(0xD77757)          // Claude Code's clawd_body, rgb(215,119,87)
        static let arms: [String: (r1L: String, r1R: String, r2L: String, r2R: String)] = [
            "down": (" ▐", "", "▝▜", "█▀"),
            "up": ("▗▟", "▄", " ▜", "█▘"),
            "one-up": (" ▐", "▄", "▝▜", "█▘"),
        ]
        static let eyes: [String: String] = ["open": "▛███▛█", "left": "▟███▟█", "right": "█▟███▟"]
        static let feet: [String: String] = ["both": " ▝▝   ▝▝ ", "left": " ▝▝      ", "right": "      ▝▝ "]

        /// Which quarters of a character cell are filled: upper left, upper right, lower left, lower right.
        static func quarters(_ glyph: Character) -> (Bool, Bool, Bool, Bool) {
            switch glyph {
            case "█": return (true, true, true, true)
            case "▐": return (false, true, false, true)
            case "▌": return (true, false, true, false)
            case "▛": return (true, true, true, false)
            case "▜": return (true, true, false, true)
            case "▙": return (true, false, true, true)
            case "▟": return (false, true, true, true)
            case "▝": return (false, true, false, false)
            case "▘": return (true, false, false, false)
            case "▗": return (false, false, false, true)
            case "▖": return (false, false, true, false)
            case "▀": return (true, true, false, false)
            case "▄": return (false, false, true, true)
            default: return (false, false, false, false)
            }
        }

        /// A pose as pixels: `a` body, `e` the dark of the eyes, `.` nothing.
        static func pose(arms: String = "down", eyes: String = "open", feet: String = "both", closed: Bool = false) -> [String] {
            let arm = self.arms[arms] ?? self.arms["down"]!
            let eyeGlyphs = self.eyes[eyes] ?? self.eyes["open"]!
            func padded(_ text: String) -> [Character] {
                let characters = Array(text)
                return characters.count >= 9 ? Array(characters.prefix(9)) : characters + Array(repeating: " ", count: 9 - characters.count)
            }
            let lines = [padded(arm.r1L + eyeGlyphs + arm.r1R), padded(arm.r2L + "█████" + arm.r2R), padded(self.feet[feet] ?? self.feet["both"]!)]
            // Which characters of the top row hold an eye: the two of the eye glyphs that are not whole blocks.
            let eyeStart = arm.r1L.count
            let eyeCells = Set(Array(eyeGlyphs).enumerated().filter { $0.element != "█" }.map { eyeStart + $0.offset })
            // A terminal cell is twice as tall as it is wide: each quarter is one pixel wide and two tall.
            var pixels = Array(repeating: Array(repeating: Character("."), count: 18), count: 12)
            for (row, line) in lines.enumerated() {
                for (column, glyph) in line.enumerated() {
                    let (ul, ur, ll, lr) = quarters(glyph)
                    let isEye = row == 0 && eyeCells.contains(column)
                    for (dy, dx, on) in [(0, 0, ul), (0, 1, ur), (1, 0, ll), (1, 1, lr)] {
                        for half in 0..<2 {
                            pixels[row * 4 + dy * 2 + half][column * 2 + dx] = on ? "a" : (isEye ? "e" : ".")
                        }
                    }
                    if isEye, closed {
                        // Shut: the eye is a line along the bottom of its cell.
                        for y in 0..<3 { pixels[y][column * 2] = "a"; pixels[y][column * 2 + 1] = "a" }
                        pixels[3][column * 2] = "e"; pixels[3][column * 2 + 1] = "e"
                    }
                }
            }
            return pixels.map { String($0) }
        }

        static let pet = PixelPet(name: "clawd", rows: pose(), palette: ["a": body, "e": hex(0x000000)], eye: "e", poses: [
            "closed": pose(closed: true),
            "look-left": pose(eyes: "left"), "look-right": pose(eyes: "right"),
            "walk-left": pose(feet: "left"), "walk-right": pose(feet: "right"),
            "arms-up": pose(arms: "up"), "one-up": pose(arms: "one-up"),
            "closed-arms-up": pose(arms: "up", closed: true),
        ])
    }

    // MARK: Official marks, pixelated

    /// Pixelated from Kiro.app's icon (the ghost).
    static let kiro = PixelPet(name: "kiro", rows: [
        ".....oooo....",
        "....oaaaao...",
        "...oaaaaaao..",
        "..oaaaaaaaao.",
        ".oaaaaaaaaaao",
        ".oaaaaeaaeaao",
        ".oaaaaeaaeaao",
        ".oaaaaaaaaaao",
        ".oaaaaaaaaaao",
        ".oaaaaaaaaaao",
        "oaaaaaaaaaaao",
        "oaaaaaaaaaaao",
        ".ooaaaaaaaao.",
        "..oaaaaaaaao.",
        "..oaaaoaaao..",
        "...ooo.ooo...",
    ], palette: ["a": hex(0xFDFCFD), "e": hex(0x4D4D4D), "o": hex(0x9747FF)], eye: "e")

    /// Pixelated from the Codex app's icon (icon-codex-dark-color.png).
    static let codex = PixelPet(name: "codex", rows: [
        "................",
        ".....aaaa.......",
        "....aaaaaaaa....",
        "....aaaaaaaaa...",
        "..baaaaaaaaaab..",
        ".bbbbbbbbabbbb..",
        ".bbbwwbbbbbbbb..",
        ".bbbbwwbbbbbbbb.",
        ".bbbbwwbbbbbbbb.",
        "..bbwwbbwwwwbbb.",
        "..ccbbbbwwwabbb.",
        "..ccccccccbbbb..",
        "...cccccccccb...",
        "....cccccccc....",
        ".......cccc.....",
        "................",
    ], palette: ["a": hex(0xAEA6FD), "b": hex(0x6D85FD), "c": hex(0x4040FD), "w": hex(0xFAFAFC)])

    /// Pixelated from Cursor.app's logo.png (the cube).
    static let cursor = PixelPet(name: "cursor", rows: [
        ".....bc.....",
        "...bbcccc...",
        "..bbbccccc..",
        "babbbbbbbbbb",
        "cbaaaaaaaaab",
        "cccbaaaaaaac",
        "cccccaaaaacc",
        "ccccccaaabcc",
        "ccccbbaaaccc",
        "cccbbbaaabcc",
        "bbbbbbaabbbb",
        "..bbbbaaaaa.",
        "...bbbaaa...",
        ".....ba.....",
    ], palette: ["a": hex(0xE6E6E6), "b": hex(0x979797), "c": hex(0x444444)])

    /// Pixelated from ZCode.app's icon.
    static let zcode = PixelPet(name: "zcode", rows: [
        "aaaaaaaaaaaaa",
        "aaaaaa.aaaaa.",
        "......aaaaa..",
        ".....aaaaaa..",
        ".....aaaaa...",
        "....aaaaa....",
        "...aaaaaa....",
        "..aaaaaa.....",
        "..aaaaa......",
        ".aaaaa.aaaaaa",
        "aaaaaa.aaaaaa",
    ], palette: ["a": hex(0xFCFCFC)])

    /// Pixelated from OpenCode.app's icon.
    static let opencode = PixelPet(name: "opencode", rows: [
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aab....baa",
        "bab....baa",
        "babccccbab",
        "babccccbab",
        "bbb....bbb",
        "bbb....bbb",
        "bbb....bbb",
        "bbbbbbbbbb",
        "bbbbbbbbbb",
    ], palette: ["a": hex(0xE5E4E4), "b": hex(0xBDBDBD), "c": hex(0x50504D)])

    /// Pixelated from Gemini's sparkle (gstatic.com, as gemini.google.com uses it).
    static let gemini = PixelPet(name: "gemini", rows: [
        ".......a.......",
        ".......a.......",
        "......aac......",
        "......acc......",
        ".....accdd.....",
        "....accdddd....",
        "..aaccddddddd..",
        "aaaacbddddddddd",
        "..aacbbdddddd..",
        "....cbbdddd....",
        ".....cbbdd.....",
        "......bbb......",
        "......bbb......",
        ".......b.......",
        ".......b.......",
    ], palette: ["a": hex(0xE28C43), "b": hex(0x41B095), "c": hex(0xA0948A), "d": hex(0x3E8BF4)])

    /// Pixelated from GitHub's Octicons, copilot-24.svg.
    static let copilot = PixelPet(name: "copilot", rows: [
        ".....aaaaaa.....",
        "....aaaaaaaa....",
        "..aa...aa...aa..",
        "..a....aa....a..",
        "..a....aa....a..",
        "..aa...aa...aa..",
        ".aaaaaa..aaaaaa.",
        "aaa..........aaa",
        "aaa...a..a...aaa",
        "aaa...a..a...aaa",
        ".aa...a..a...aa.",
        "..aaa......aaa..",
        "....aaaaaaaa....",
    ], palette: ["a": hex(0xE6E8EE)])

    /// Pixelated from the QwenLM GitHub organisation's logo.
    static let qwen = PixelPet(name: "qwen", rows: [
        "......aa.......",
        ".....aaaa......",
        "....aaaaaaaaaa.",
        "....aaaaaaaaaa.",
        ".aa.aaaaaaaaaa.",
        "aaaa...........",
        "aaaaa......aa..",
        ".aaaa.....aaaa.",
        ".aaaaa....aaaa.",
        "..aaaa...aaaaaa",
        ".aaaaaa.aaaaaaa",
        ".aaaaaa.aaaaaa.",
        "..aaaa.aaaaa...",
        ".......aaaa....",
        "........aa.....",
    ], palette: ["a": hex(0x082DFF)])

    /// Pixelated from the Trae-AI GitHub organisation's logo.
    static let trae = PixelPet(name: "trae", rows: [
        "aaaaaaaaaaaaaaa",
        "aaaaaaaaaaaaaaa",
        "aaa..........aa",
        "aa...........aa",
        "aa...aa...a..aa",
        "aa...aa..aaa.aa",
        "aa...aa...a..aa",
        "aa...........aa",
        "aa...........aa",
        "..aaaaaaaaaaaaa",
        "..aaaaaaaaaaaaa",
    ], palette: ["a": hex(0x31EA89)])

    /// Pixelated from windsurf.com's favicon.svg.
    static let windsurf = PixelPet(name: "windsurf", rows: [
        "a.....aa......a",
        "a.....aaa....aa",
        "aa....aaaa...aa",
        "aaa...a.aa...a.",
        ".aa.....aaa....",
        "..aa.a...aaa.a.",
        "..aaaa....aaaa.",
        "...aaa....aaaa.",
        "....aa.....aa..",
    ], palette: ["a": hex(0xF9F3E9)])

    /// Pixelated from x.ai's favicon.
    static let grok = PixelPet(name: "grok", rows: [
        ".............aa",
        ".aaa.......aaa.",
        ".aaaa....aaa...",
        "...aaa.aaaa....",
        ".....aaaa......",
        "....aaaa.......",
        "..aaaa.aaaa....",
        ".aaaa...aaaa...",
        "aaaa.....aaaa..",
    ], palette: ["a": hex(0xF0F0F0)])

    /// Pixelated from the Factory-AI GitHub organisation's logo.
    static let factory = PixelPet(name: "factory", rows: [
        "....a...aa....",
        "...aaaaa.a....",
        "...a.a...aa...",
        "..a..a..a..aa.",
        "aaa...a.a...aa",
        "a..aa.aa..aaa.",
        ".a...aaaaa..a.",
        ".a..aaaaa...a.",
        ".aaa..aa.aa..a",
        "aa...a.a...aaa",
        ".aa..a..a..a..",
        "...aa...a.a...",
        "....a.aaaaa...",
        "....aa...a....",
    ], palette: ["a": hex(0xF0F0F0)])

    /// Pixelated from devin.ai's favicon.svg.
    static let devin = PixelPet(name: "devin", rows: [
        "..aa.........",
        "aaaaaa.......",
        "aaaaaa.......",
        "aaaaaa.......",
        "aaaaaaa..aa..",
        "aaaaaaaaaaaaa",
        "..aa..aaaaaaa",
        ".......aaaaaa",
        "..aa..aaaaaaa",
        "aaaaaaaaaaaaa",
        "aaaaaaa..aa..",
        "aaaaaa.......",
        "aaaaaa.......",
        "aaaaaa.......",
        "..aa.........",
    ], palette: ["a": hex(0xF0F0F0)])

    /// Pixelated from ampcode.com's app icon (the wordmark).
    static let amp = PixelPet(name: "amp", rows: [
        ".aaaaa.aa.a.aaaa.",
        "a....a.aa.aaa...a",
        "a....a.aa.aa....a",
        "a....aa.aa.a....a",
        ".a..aaa.aa.aa..a.",
        "...........a.....",
        "...........a.....",
    ], palette: ["a": hex(0xDDDDC0)])

    /// Pixelated from kimi.com's app icon.
    static let kimi = PixelPet(name: "kimi", rows: [
        "..........bb.",
        "..........bb.",
        "aa....aaa....",
        "aa...aaa.....",
        "aa..aaa......",
        "aa.aaa.......",
        "aaaaaa.......",
        "aaaaaaa......",
        "aaa.aaaa.....",
        "aa....aaaa...",
        "aa.....aaa...",
        ".........b...",
        ".............",
        ".............",
    ], palette: ["a": hex(0xF7F7F7), "b": hex(0x267EE3)])

    /// Pixelated from the MiniMax-AI GitHub organisation's logo (the waveform).
    static let minimax = PixelPet(name: "minimax", rows: [
        ".....aa.aa....",
        ".....aa.a.a...",
        ".....aa.a.a...",
        "..a..aa.a.a.aa",
        ".a.a.aa.a.a..a",
        ".a.a.aa.a.a..a",
        ".a.a.aa.a.a..a",
        "aa.a.aa.a.a..a",
        "...a.a..a.a...",
        "...a.a..a.aa..",
        "....a.a.a.....",
    ], palette: ["a": hex(0xF3526B)])

    /// Pixelated from the qoder-ai GitHub organisation's logo.
    static let qoder = PixelPet(name: "qoder", rows: [
        "...aaaaa......",
        "..aaaaaaa.....",
        ".aaaaaaaaaa...",
        "aaaaaaaaabbbb.",
        "aaaaaaa.bbbbbb",
        "aaaaaa..bbbbbb",
        "aaaaaa..bbbbbb",
        "aaaaaa..bbbbbb",
        "aaaaaa..bbbbbb",
        "aaaaaa.bbbbbbb",
        ".aaaaabbbbbbbb",
        "...aaabbbbbbbb",
        ".....abbbbbbbb",
        ".......bbbb.bb",
    ], palette: ["a": hex(0xF7FBF8), "b": hex(0x2ADA5C)])

    /// Pixelated from codebuddy.ai's logo.svg (the cat).
    static let codebuddy = PixelPet(name: "codebuddy", rows: [
        ".....eeeeee.....",
        "...eeeeeeeece...",
        "..eeeeeeeecaae..",
        ".eeeeeeeeeaaace.",
        ".eeeeeeeecaaaae.",
        "eeeeeeecaaaaaaaa",
        "eeeeeeaaaaacecaa",
        "cccccaaaaceeeeea",
        "caaaaaaceeeeeeec",
        "eaaaacddeeeaceee",
        "daaacddddeeaaeee",
        ".daadddcddeeace.",
        ".daaddcacddddbd.",
        "..aadddaadbbbb..",
        "...acdddcbbbb...",
        ".....ddddbb.....",
    ], palette: ["a": hex(0xEDECFC), "b": hex(0x35DEBC), "c": hex(0xA8A6F1), "d": hex(0x5088D0), "e": hex(0x694DF1)], eye: "e")

    /// Pixelated from the XiaomiMiMo GitHub organisation's logo (the wordmark).
    static let mimo = PixelPet(name: "mimo", rows: [
        "a...aa.a...a.aaa.",
        ".a.aaa..a.aa....a",
        "a.a.aa.a.a.aa...a",
        "a...aa.a...aa...a",
        "a...a..a...a.aaa.",
    ], palette: ["a": hex(0xE5E5E5)])

    // MARK: Our own

    /// The island, for the app itself and for agents it does not know (our own drawing).
    static let island: PixelPet = {
        let sprite = Mascots.islandArt
        return PixelPet(name: "island", rows: sprite.frames[0], palette: sprite.palette)
    }()

    /// Every pet, for the picker in Settings.
    static let all: [PixelPet] = [Clawd.pet, codex, kiro, cursor, zcode, gemini, copilot, qwen, trae, windsurf, opencode,
                                  grok, factory, devin, amp, kimi, minimax, qoder, codebuddy, mimo, island]

    static func named(_ name: String) -> PixelPet? { all.first { $0.name == name } }

    /// The agent's own pet.
    static func pet(for source: String) -> PixelPet {
        switch source {
        case "claude": return Clawd.pet
        case "codex": return codex
        case "kiro": return kiro
        case "cursor": return cursor
        case "zcode": return zcode
        case "gemini": return gemini
        case "copilot": return copilot
        case "qwen", "qwenwork": return qwen
        case "trae", "trae-cn": return trae
        case "windsurf": return windsurf
        case "opencode": return opencode
        case "grok": return grok
        case "factory": return factory
        case "devin": return devin
        case "amp": return amp
        case "kimi": return kimi
        case "minimax": return minimax
        case "qoder", "qoder-cn", "qoderwork": return qoder
        case "codebuddy": return codebuddy
        case "mimocode": return mimo
        default: return island
        }
    }
}

// MARK: - Drawing

/// Draws a pet in the pose a mood calls for, on whole device pixels.
enum PixelPetArt {
    static let amber = hex(0xF5B638)

    /// The rows for this moment of this mood.
    static func rows(_ pet: PixelPet, pose: CreaturePose) -> [String] {
        let shut = pose.blink > 0.5 || pose.mood == .sleeping || pose.mood == .failed
        if pet.name == PixelPets.Clawd.pet.name {
            func variant(_ name: String) -> [String] { pet.poses[name] ?? pet.rows }
            switch pose.mood {
            case .working: return variant(pose.action < 0.5 ? "walk-left" : "walk-right")
            case .waiting: return variant(pose.phase(pose.loop) < 0.5 ? "look-left" : "look-right")
            case .attention: return variant("arms-up")
            case .happy: return variant(pose.action < 0.5 ? "arms-up" : "one-up")
            case .failed, .sleeping: return variant("closed")
            case .idle: return shut ? variant("closed") : pet.rows
            }
        }
        guard shut, let eye = pet.eye else { return pet.rows }
        // Eyes shut: the eye pixels take the colour around them, save the lowest row of each eye.
        let lines = pet.rows.map(Array.init)
        let lowest = Dictionary(grouping: lines.indices.flatMap { r in lines[r].indices.filter { lines[r][$0] == eye }.map { (r, $0) } },
                                by: { $0.1 }).mapValues { $0.map(\.0).max() ?? 0 }
        let body = lines.joined().first { $0 != "." && $0 != eye } ?? "a"
        return lines.enumerated().map { r, line in
            String(line.enumerated().map { c, ch in ch == eye && lowest[c] != r ? body : ch })
        }
    }

    static func draw(_ pet: PixelPet, pose: CreaturePose, in context: GraphicsContext, size: CGSize, scale: CGFloat, detail: Bool) {
        let grid = rows(pet, pose: pose)
        let columns = grid.map(\.count).max() ?? 0, height = grid.count
        guard columns > 0 else { return }
        let side = min(size.width, size.height)
        // Room above for a hop and, when there is space, for a "!" or a "z" at the top right. A wide
        // pet (Clawd) fills the width: what goes above it has room over its head.
        let cells = max(columns + (detail ? 2 : 1), height + (detail ? 6 : 2))
        let cell = max(1, floor(side * scale / CGFloat(cells))) / scale
        let originX = ((size.width - cell * CGFloat(cells)) / 2 * scale).rounded() / scale
        let originY = ((size.height - cell * CGFloat(cells)) / 2 * scale).rounded() / scale
        let lift = Int((pose.hop / 6).rounded())
        let hop = min(lift, detail ? 2 : 1)
        let left = max(0, (cells - columns) / 2 - (detail && cells - columns > 4 ? 1 : 0))
        let top = cells - height - 1 - hop
        var ctx = context
        if pose.mood == .sleeping { ctx.opacity = 0.62 } else if pose.mood == .failed { ctx.opacity = 0.8 }
        for (r, line) in grid.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let color = pet.palette[ch] else { continue }
                ctx.fill(Path(CGRect(x: originX + CGFloat(left + c) * cell, y: originY + CGFloat(top + r) * cell, width: cell, height: cell)),
                         with: .color(color))
            }
        }
        guard detail else { return }
        var mark = context
        func dots(_ pattern: [String], at x: Int, _ y: Int, _ colors: [Character: Color]) {
            for (r, line) in pattern.enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let color = colors[ch] else { continue }
                    mark.fill(Path(CGRect(x: originX + CGFloat(x + c) * cell, y: originY + CGFloat(y + r) * cell, width: cell, height: cell)),
                              with: .color(color))
                }
            }
        }
        let ink = Color.black, white = Color.white
        switch pose.mood {
        case .attention:
            let bob = pose.phase(0.575) < 0.5 ? 0 : 1
            dots([".ooo.", "oo#oo", "oo#oo", "ooooo", "oo#oo", ".ooo."], at: cells - 5, bob, ["o": amber, "#": ink])
        case .waiting:
            let lit = Int(pose.phase(1.26) * 3)
            let line = (0..<3).map { $0 <= lit ? "#" : "-" }.joined(separator: "w")
            dots([".wwwwwww.", "ww" + line + "ww", "wwwwwwwww", ".w......."], at: cells - 9, 0,
                 ["w": white, "#": ink, "-": white.opacity(0.0)])
        case .happy:
            let twinkle = pose.phase(0.92) < 0.5
            dots([".y.", "yyy", ".y."], at: twinkle ? 0 : cells - 3, twinkle ? 1 : 0, ["y": twinkle ? white : amber])
            dots([".y.", "yyy", ".y."], at: twinkle ? cells - 3 : 1, twinkle ? 2 : 1, ["y": twinkle ? amber : white])
        case .failed:
            let slide = Int(pose.phase(1.8) * 3)
            dots([".b", "bb", "bb"], at: cells - 3, 1 + slide, ["b": hex(0x8CCBFF)])
        case .sleeping:
            let rise = Int(pose.phase(2.4) * 3)
            dots(["zzz", "..z", ".z.", "zzz"], at: cells - 4, 3 - rise, ["z": white.opacity(0.85)])
        case .idle, .working:
            break
        }
    }
}

import AppKit
import SwiftUI

/// How a creature feels, from what its agent is doing.
enum CreatureMood: String, CaseIterable, Sendable {
    /// Nothing going on: breathes, blinks, looks about.
    case idle
    /// At work: bounces along and does its own thing (the whale spouts, the crab snaps).
    case working
    /// Its turn is over and it waits for you: looks up at you.
    case waiting
    /// Blocked on a decision of yours: hops, with a "!".
    case attention
    /// A turn just finished well: ^ ^, a hop and a few sparkles.
    case happy
    /// Something went wrong: × eyes and a drop of sweat.
    case failed
    /// Quiet for a long time: eyes shut, a z or two.
    case sleeping
}

/// Where a creature is at one moment, from the clock, its mood and its own seed
/// (so a row of creatures never blinks in step). Units are those of the 100 × 100
/// box every creature is drawn in.
struct CreaturePose {
    var mood: CreatureMood
    var t: Double
    /// Upwards, in units.
    var hop: CGFloat = 0
    /// 1 is at rest; below it the body is flattened, above it stretched.
    var squash: CGFloat = 1
    var tilt: Double = 0
    /// 0 open, 1 shut.
    var blink: CGFloat = 0
    /// Where the eyes look, each axis -1…1.
    var look = CGPoint.zero
    /// The species' own movement: phase (0…1, repeating) and how much of it.
    var action: Double = 0
    var amount: CGFloat = 0.3
    /// Eyes a little wider or narrower than usual.
    var eyeScale: CGFloat = 1
    /// Seconds after which every movement of this mood repeats exactly, so a loop of
    /// frames played over and over has no seam.
    var loop: Double = 5.04

    static func loop(_ mood: CreatureMood) -> Double {
        switch mood {
        case .working: return 2.52
        case .attention: return 2.3
        case .happy: return 1.84
        case .failed: return 3.6
        case .sleeping: return 4.8
        case .idle, .waiting: return 5.04
        }
    }

    /// The angle of a movement that repeats about every `period` seconds, adjusted so a
    /// whole number of them fits the loop.
    func angle(_ period: Double, _ offset: Double = 0) -> Double {
        let count = max(1, (loop / period).rounded())
        return (t + offset) * 2 * .pi * count / loop
    }

    /// 0…1 through a movement that repeats about every `period` seconds, fitted to the loop.
    func phase(_ period: Double, _ offset: Double = 0) -> Double {
        let count = max(1, (loop / period).rounded())
        let value = (t + offset) * count / loop
        return value - floor(value)
    }

    static func make(mood: CreatureMood, t: Double, seed: Double, still: Bool) -> CreaturePose {
        var pose = CreaturePose(mood: mood, t: t + seed * 7.31)
        pose.loop = loop(mood)
        func wave(_ period: Double, _ offset: Double = 0) -> Double { sin(pose.angle(period, offset)) }
        switch mood {
        case .idle:
            pose.squash = 1 + 0.022 * CGFloat(wave(2.52))
            pose.look = CGPoint(x: 0.55 * wave(5.04), y: 0.18 * wave(2.52, 1))
            pose.action = pose.phase(2.52)
            pose.amount = 0.35
        case .working:
            // A bounce every 0.84 s: the fall and the rise are the two halves of a sine.
            let bounce = abs(sin(pose.angle(0.84) / 2))
            pose.hop = 3.6 * CGFloat(bounce)
            pose.squash = 0.955 + 0.075 * CGFloat(bounce)
            pose.look = CGPoint(x: 0.45 + 0.12 * wave(1.26), y: 0.12)
            pose.action = pose.phase(0.63)
            pose.amount = 1
            pose.eyeScale = 0.86
        case .waiting:
            pose.tilt = 0.075 * wave(2.52)
            pose.squash = 1 + 0.02 * CGFloat(wave(2.52, 0.65))
            pose.look = CGPoint(x: 0.15 * wave(5.04), y: -0.8)
            pose.action = pose.phase(2.52)
            pose.amount = 0.45
        case .attention:
            let cycle = pose.phase(1.15)
            if cycle < 0.42 {
                let x = cycle / 0.42
                pose.hop = CGFloat(12 * 4 * x * (1 - x))
                pose.squash = 1 + 0.07 * CGFloat(1 - abs(2 * x - 1))
            } else if cycle < 0.56 {
                pose.squash = 1 - 0.11 * CGFloat(sin((cycle - 0.42) / 0.14 * .pi))
            }
            pose.look = CGPoint(x: 0, y: -0.35)
            pose.action = pose.phase(0.575)
            pose.amount = 0.85
            pose.eyeScale = 1.16
        case .happy:
            let bounce = abs(sin(pose.angle(0.92) / 2))
            pose.hop = 7 * CGFloat(bounce)
            pose.squash = 0.94 + 0.1 * CGFloat(bounce)
            pose.tilt = 0.07 * wave(0.92)
            pose.action = pose.phase(0.46)
            pose.amount = 0.9
        case .failed:
            pose.squash = 0.93
            pose.tilt = -0.07 + 0.025 * wave(3.6)
            pose.look = CGPoint(x: -0.25, y: 0.55)
            pose.action = pose.phase(3.6)
            pose.amount = 0.15
        case .sleeping:
            pose.squash = 1 + 0.035 * CGFloat(wave(4.8))
            pose.tilt = 0.05
            pose.action = pose.phase(4.8)
            pose.amount = 0.12
        }
        if still {
            // A picture: a pleasant moment with the eyes open, standing on the ground.
            pose.hop = mood == .happy || mood == .attention ? 4 : 0
            pose.squash = 1
            pose.tilt = mood == .waiting ? 0.05 : (mood == .failed ? -0.07 : (mood == .sleeping ? 0.05 : 0))
            pose.action = 0.2
            return pose
        }
        if mood != .happy, mood != .failed, mood != .sleeping {
            // A blink once a loop, at a moment of its own; now and then two in a row.
            let cycle = pose.phase(pose.loop)
            let length = 0.15 / pose.loop
            let first = (seed * 3.3 - floor(seed * 3.3)) * (1 - 3 * length)
            let blink = { (start: Double) -> CGFloat in
                cycle >= start && cycle < start + length ? CGFloat(sin((cycle - start) / length * .pi)) : 0
            }
            let twice = seed * 5.1 - floor(seed * 5.1) > 0.55
            pose.blink = max(blink(first), twice ? blink(first + 1.6 * length) : 0)
        }
        return pose
    }
}

/// Colours of one creature, from its sprite's palette so the user's picks and
/// the recoloured creatures of the smaller agents carry over.
struct CreatureColors {
    var base: Color
    var shade: Color
    var light: Color
    var extra: Color
    var detail: Color
    var cheek = Color(red: 1, green: 0.47, blue: 0.55)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.13)

    init(_ sprite: MascotSprite) {
        let p = sprite.palette
        func pick(_ keys: String..., fallback: Color) -> Color {
            for key in keys { if let color = p[Character(key)] { return color } }
            return fallback
        }
        switch sprite.name {
        case "gull":
            base = pick("w", fallback: .white); shade = pick("g", fallback: .gray)
            light = .white; extra = pick("o", fallback: .orange); detail = pick("g", fallback: .gray)
        case "boat":
            base = pick("b", fallback: .gray); shade = pick("b", fallback: .gray).mixed(with: .black, 0.3)
            light = pick("w", fallback: .white); extra = pick("c", fallback: .blue); detail = pick("m", fallback: .gray)
        case "whale":
            base = pick("a", fallback: .blue); shade = pick("a", fallback: .blue).mixed(with: .black, 0.28)
            light = pick("w", fallback: .white); extra = pick("c", fallback: .cyan); detail = pick("w", fallback: .white)
        case "turtle":
            base = pick("a", fallback: .green); shade = pick("b", fallback: .green)
            light = pick("a", fallback: .green).mixed(with: .white, 0.35); extra = pick("b", fallback: .green); detail = pick("b", fallback: .green)
        case "island":
            base = pick("s", fallback: .yellow); shade = pick("t", fallback: .brown)
            light = pick("g", fallback: .green); extra = pick("c", fallback: .blue); detail = pick("t", fallback: .brown)
        default:
            base = pick("a", fallback: .orange)
            shade = pick("b", fallback: base.mixed(with: .black, 0.28))
            light = pick("c", fallback: base.mixed(with: .white, 0.4))
            extra = pick("w", fallback: .white)
            detail = shade
        }
    }

    func body(top: CGFloat, bottom: CGFloat, from base: Color? = nil) -> GraphicsContext.Shading {
        let main = base ?? self.base
        return .linearGradient(Gradient(stops: [
            .init(color: main.mixed(with: .white, 0.28), location: 0),
            .init(color: main, location: 0.5),
            .init(color: main.mixed(with: .black, 0.22), location: 1),
        ]), startPoint: CGPoint(x: 50, y: top), endPoint: CGPoint(x: 50, y: bottom))
    }
}

extension Color {
    /// This colour moved `amount` of the way towards another (sRGB, opaque colours).
    func mixed(with other: Color, _ amount: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let t = max(0, min(1, amount))
        return Color(.sRGB, red: Double(a.redComponent + (b.redComponent - a.redComponent) * t),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * t),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * t),
                     opacity: Double(a.alphaComponent))
    }
}

/// Draws one creature in a 100 × 100 box, in vector: soft shading, a face that
/// shows the mood, and the species' own movement.
enum CreatureArt {
    static func draw(_ sprite: MascotSprite, colors: CreatureColors, pose: CreaturePose, in context: GraphicsContext,
                     size: CGSize, detail: Bool) {
        var ctx = context
        let side = min(size.width, size.height)
        ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        ctx.scaleBy(x: side / 100, y: side / 100)

        var body = ctx
        body.translateBy(x: 50, y: 93 - pose.hop)
        body.rotate(by: .radians(pose.tilt))
        body.scaleBy(x: 1 / sqrt(pose.squash), y: pose.squash)
        body.translateBy(x: -50, y: -93)

        switch sprite.name {
        case "whale": whale(&body, colors, pose, detail)
        case "jellyfish": jellyfish(&body, colors, pose, detail)
        case "turtle": turtle(&body, colors, pose, detail)
        case "gull": gull(&body, colors, pose, detail)
        case "boat": boat(&body, ground: ctx, colors, pose, detail)
        case "octopus": octopus(&body, colors, pose, detail)
        case "puffer": puffer(&body, colors, pose, detail)
        case "crab": crab(&body, colors, pose, detail)
        case "island": island(&body, ground: ctx, colors, pose, detail)
        default: starfish(&body, colors, pose, detail)
        }
        if detail { accessory(&ctx, pose) }
    }

    // MARK: Faces

    static func eyes(_ ctx: inout GraphicsContext, _ centers: [CGPoint], r: CGFloat, pose: CreaturePose) {
        let ink = CreatureColors.ink
        for c in centers {
            switch pose.mood {
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - 0.9 * r, y: c.y + 0.4 * r))
                arc.addQuadCurve(to: CGPoint(x: c.x + 0.9 * r, y: c.y + 0.4 * r), control: CGPoint(x: c.x, y: c.y - 1.05 * r))
                ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 0.62 * r, lineCap: .round))
            case .sleeping:
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - 0.9 * r, y: c.y))
                arc.addQuadCurve(to: CGPoint(x: c.x + 0.9 * r, y: c.y), control: CGPoint(x: c.x, y: c.y + 0.85 * r))
                ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 0.5 * r, lineCap: .round))
            case .failed:
                var cross = Path()
                let d = 0.72 * r
                cross.move(to: CGPoint(x: c.x - d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
                cross.move(to: CGPoint(x: c.x + d, y: c.y - d)); cross.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
                ctx.stroke(cross, with: .color(ink), style: StrokeStyle(lineWidth: 0.5 * r, lineCap: .round))
            default:
                let width = 1.72 * r * pose.eyeScale
                let height = max(0.28 * r, 2.12 * r * pose.eyeScale * (1 - pose.blink))
                let center = CGPoint(x: c.x + pose.look.x * 0.32 * r, y: c.y + pose.look.y * 0.3 * r)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)),
                         with: .color(ink))
                if height > 1.1 * r {
                    let g = 0.36 * r
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - 0.28 * r - g, y: center.y - 0.42 * height / 2 - g, width: 2 * g, height: 2 * g)),
                             with: .color(.white))
                    let s = 0.16 * r
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x + 0.3 * r - s, y: center.y + 0.38 * height / 2 - s, width: 2 * s, height: 2 * s)),
                             with: .color(.white.opacity(0.7)))
                }
            }
        }
    }

    static func mouth(_ ctx: inout GraphicsContext, at m: CGPoint, width w: CGFloat, pose: CreaturePose) {
        let ink = CreatureColors.ink
        switch pose.mood {
        case .happy:
            var open = Path()
            open.move(to: CGPoint(x: m.x - w / 2, y: m.y - 0.6))
            open.addQuadCurve(to: CGPoint(x: m.x + w / 2, y: m.y - 0.6), control: CGPoint(x: m.x, y: m.y + 0.95 * w))
            open.closeSubpath()
            ctx.fill(open, with: .color(ink))
            var tongue = ctx
            tongue.clip(to: open)
            tongue.fill(Path(ellipseIn: CGRect(x: m.x - w * 0.3, y: m.y + w * 0.2, width: w * 0.6, height: w * 0.5)),
                        with: .color(Color(red: 1, green: 0.45, blue: 0.5)))
        case .attention:
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 0.22 * w, y: m.y - 0.1 * w, width: 0.44 * w, height: 0.52 * w)), with: .color(ink))
        case .working:
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 0.17 * w, y: m.y, width: 0.34 * w, height: 0.3 * w)), with: .color(ink))
        case .sleeping:
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 0.13 * w, y: m.y, width: 0.26 * w, height: 0.3 * w)), with: .color(ink.opacity(0.85)))
        case .failed:
            var squiggle = Path()
            squiggle.move(to: CGPoint(x: m.x - w / 2, y: m.y + 1))
            squiggle.addQuadCurve(to: CGPoint(x: m.x, y: m.y + 0.6), control: CGPoint(x: m.x - w / 4, y: m.y - 1.3))
            squiggle.addQuadCurve(to: CGPoint(x: m.x + w / 2, y: m.y + 1), control: CGPoint(x: m.x + w / 4, y: m.y + 2.5))
            ctx.stroke(squiggle, with: .color(ink), style: StrokeStyle(lineWidth: 0.24 * w, lineCap: .round))
        case .idle, .waiting:
            var smile = Path()
            smile.move(to: CGPoint(x: m.x - w / 2, y: m.y))
            smile.addQuadCurve(to: CGPoint(x: m.x + w / 2, y: m.y), control: CGPoint(x: m.x, y: m.y + 0.62 * w))
            ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 0.26 * w, lineCap: .round))
        }
    }

    static func cheeks(_ ctx: inout GraphicsContext, _ centers: [CGPoint], r: CGFloat, colors: CreatureColors, pose: CreaturePose) {
        let strength = pose.mood == .happy ? 0.7 : (pose.mood == .failed ? 0.15 : 0.42)
        for c in centers {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.3 * r, y: c.y - 0.6 * r, width: 2.6 * r, height: 1.2 * r)),
                     with: .color(colors.cheek.opacity(strength)))
        }
    }

    static func face(_ ctx: inout GraphicsContext, eyes left: CGPoint, _ right: CGPoint, r: CGFloat, mouth m: CGPoint, width w: CGFloat,
                     colors: CreatureColors, pose: CreaturePose) {
        cheeks(&ctx, [CGPoint(x: left.x - 0.5 * r, y: left.y + 1.75 * r), CGPoint(x: right.x + 0.5 * r, y: right.y + 1.75 * r)],
               r: r, colors: colors, pose: pose)
        eyes(&ctx, [left, right], r: r, pose: pose)
        mouth(&ctx, at: m, width: w, pose: pose)
    }

    /// A soft gloss on the upper left of a body.
    static func gloss(_ ctx: inout GraphicsContext, _ rect: CGRect, inside shape: Path, angle: Double = -0.35, opacity: Double = 0.32) {
        var g = ctx
        g.clip(to: shape)
        g.translateBy(x: rect.midX, y: rect.midY)
        g.rotate(by: .radians(angle))
        g.fill(Path(ellipseIn: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)),
               with: .linearGradient(Gradient(colors: [.white.opacity(opacity), .white.opacity(0)]),
                                     startPoint: CGPoint(x: 0, y: -rect.height / 2), endPoint: CGPoint(x: 0, y: rect.height / 2)))
    }

    static func outline(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color) {
        ctx.stroke(path, with: .color(color.mixed(with: .black, 0.45).opacity(0.55)), lineWidth: 1.6)
    }

    /// A rounded polygon through `points`: each corner is a curve between the edges' midpoints.
    static func rounded(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[points.count - 1], points[0]))
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: mid(points[index], next), control: points[index])
        }
        path.closeSubpath()
        return path
    }

    static func waves(_ ctx: inout GraphicsContext, y: CGFloat, color: Color, pose: CreaturePose, offset: Double, opacity: Double) {
        var path = Path()
        let shift = pose.angle(2.52) + offset
        for step in 0...40 {
            let x = CGFloat(step) * 2.5
            let point = CGPoint(x: x, y: y + 2.2 * CGFloat(sin(Double(x) * 0.17 + shift)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    // MARK: Species

    /// Claude Code: a sea star whose arms wave while it works.
    static func starfish(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let center = CGPoint(x: 50, y: 56)
        var points: [CGPoint] = []
        for k in 0..<10 {
            let arm = k / 2
            let angle = -Double.pi / 2 + Double(k) * .pi / 5
            let wiggle = pose.amount * 3.2 * CGFloat(sin(pose.action * 2 * .pi + Double(arm) * 1.3))
            let radius: CGFloat = k % 2 == 0 ? 47 + wiggle : 23
            points.append(CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)) * 0.94))
        }
        let star = rounded(points)
        ctx.fill(star, with: c.body(top: 10, bottom: 98))
        outline(&ctx, star, c.base)
        if detail {
            for arm in 0..<5 {
                let angle = -Double.pi / 2 + Double(arm) * 2 * .pi / 5
                for (distance, size) in [(29.0, 2.6), (37.0, 1.9)] {
                    let p = CGPoint(x: center.x + CGFloat(distance * cos(angle)), y: center.y + CGFloat(distance * sin(angle)) * 0.94)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: 2 * size, height: 2 * size)),
                             with: .color(c.light.opacity(0.75)))
                }
            }
        }
        gloss(&ctx, CGRect(x: 33, y: 27, width: 22, height: 10), inside: star)
        face(&ctx, eyes: CGPoint(x: 42.5, y: 52), CGPoint(x: 57.5, y: 52), r: 4.6, mouth: CGPoint(x: 50, y: 61), width: 7,
             colors: c, pose: pose)
    }

    /// Codex: a round whale that spouts while it works.
    static func whale(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        // The tail beats behind the body.
        var tail = ctx
        tail.translateBy(x: 84, y: 64)
        tail.rotate(by: .radians(-0.15 - 0.32 * Double(pose.amount) * sin(pose.action * 2 * .pi)))
        var fluke = Path()
        fluke.move(to: CGPoint(x: -4, y: 0))
        fluke.addQuadCurve(to: CGPoint(x: 14, y: -17), control: CGPoint(x: 6, y: -14))
        fluke.addQuadCurve(to: CGPoint(x: 9, y: -2), control: CGPoint(x: 15, y: -8))
        fluke.addQuadCurve(to: CGPoint(x: 15, y: 13), control: CGPoint(x: 15, y: 6))
        fluke.addQuadCurve(to: CGPoint(x: -4, y: 4), control: CGPoint(x: 6, y: 12))
        fluke.closeSubpath()
        tail.fill(fluke, with: .color(c.base.mixed(with: .black, 0.12)))

        var body = Path()
        body.move(to: CGPoint(x: 10, y: 64))
        body.addCurve(to: CGPoint(x: 50, y: 30), control1: CGPoint(x: 10, y: 40), control2: CGPoint(x: 28, y: 30))
        body.addCurve(to: CGPoint(x: 88, y: 62), control1: CGPoint(x: 72, y: 30), control2: CGPoint(x: 86, y: 44))
        body.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 88, y: 80), control2: CGPoint(x: 70, y: 88))
        body.addCurve(to: CGPoint(x: 10, y: 64), control1: CGPoint(x: 26, y: 88), control2: CGPoint(x: 10, y: 80))
        body.closeSubpath()
        ctx.fill(body, with: c.body(top: 28, bottom: 90))
        var belly = ctx
        belly.clip(to: body)
        belly.fill(Path(ellipseIn: CGRect(x: 12, y: 70, width: 62, height: 30)), with: .color(c.light.opacity(0.95)))
        if detail {
            for x in stride(from: 26.0, through: 56, by: 7) {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 76)); line.addLine(to: CGPoint(x: x + 1.5, y: 84))
                belly.stroke(line, with: .color(c.base.opacity(0.22)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        outline(&ctx, body, c.base)
        gloss(&ctx, CGRect(x: 26, y: 33, width: 30, height: 11), inside: body)
        // A little fin.
        var fin = Path()
        fin.move(to: CGPoint(x: 58, y: 70))
        fin.addQuadCurve(to: CGPoint(x: 72, y: 78), control: CGPoint(x: 70, y: 66))
        fin.addQuadCurve(to: CGPoint(x: 58, y: 70), control: CGPoint(x: 62, y: 78))
        ctx.fill(fin, with: .color(c.base.mixed(with: .black, 0.18)))
        face(&ctx, eyes: CGPoint(x: 28, y: 56), CGPoint(x: 44, y: 56), r: 4.4, mouth: CGPoint(x: 36, y: 65), width: 7,
             colors: c, pose: pose)

        // The spout, while it works or is pleased.
        if pose.mood == .working || pose.mood == .happy || pose.mood == .attention {
            for drop in 0..<4 {
                let phase = (pose.action + Double(drop) / 4).truncatingRemainder(dividingBy: 1)
                let spread = CGFloat(drop % 2 == 0 ? -1 : 1) * CGFloat(4 + 6 * phase)
                let y = 28 - CGFloat(26 * phase - 18 * phase * phase)
                let size = CGFloat(3.2 - 1.2 * phase)
                ctx.fill(Path(ellipseIn: CGRect(x: 52 + spread - size, y: y - size, width: 2 * size, height: 2.3 * size)),
                         with: .color(c.extra.opacity(1 - phase * 0.8)))
            }
        }
    }

    /// Gemini CLI and Qwen: a jellyfish that pulses and trails its tentacles.
    static func jellyfish(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let pulse = CGFloat(sin(pose.action * 2 * .pi)) * pose.amount
        for (index, x) in [27.0, 38.5, 50, 61.5, 73].enumerated() {
            var strand = Path()
            let length: CGFloat = index == 2 ? 36 : (index == 0 || index == 4 ? 26 : 32)
            for step in 0...12 {
                let y = 56 + length * CGFloat(step) / 12
                let sway = (1.6 + 2.6 * pose.amount) * CGFloat(sin(pose.action * 2 * .pi + Double(y) * 0.13 + Double(index)))
                    * CGFloat(step) / 12
                let point = CGPoint(x: CGFloat(x) + sway - pulse * 1.5 * (CGFloat(x) - 50) / 25, y: y)
                if step == 0 { strand.move(to: point) } else { strand.addLine(to: point) }
            }
            ctx.stroke(strand, with: .color(c.shade.opacity(0.95)), style: StrokeStyle(lineWidth: index % 2 == 0 ? 3.8 : 3, lineCap: .round))
        }
        var bell = ctx
        bell.translateBy(x: 50, y: 56)
        bell.scaleBy(x: 1 + 0.05 * pulse, y: 1 - 0.05 * pulse)
        bell.translateBy(x: -50, y: -56)
        var dome = Path()
        dome.move(to: CGPoint(x: 13, y: 57))
        dome.addCurve(to: CGPoint(x: 50, y: 12), control1: CGPoint(x: 13, y: 28), control2: CGPoint(x: 29, y: 12))
        dome.addCurve(to: CGPoint(x: 87, y: 57), control1: CGPoint(x: 71, y: 12), control2: CGPoint(x: 87, y: 28))
        for k in 0..<5 {
            let x = 87 - CGFloat(k) * 14.8
            dome.addQuadCurve(to: CGPoint(x: x - 14.8, y: 57), control: CGPoint(x: x - 7.4, y: 64))
        }
        dome.closeSubpath()
        bell.fill(dome, with: c.body(top: 12, bottom: 64))
        bell.fill(Path(ellipseIn: CGRect(x: 22, y: 16, width: 40, height: 30)),
                  with: .radialGradient(Gradient(colors: [c.light.opacity(0.55), c.light.opacity(0)]),
                                        center: CGPoint(x: 40, y: 28), startRadius: 0, endRadius: 22))
        outline(&bell, dome, c.base)
        gloss(&bell, CGRect(x: 25, y: 18, width: 22, height: 10), inside: dome)
        face(&bell, eyes: CGPoint(x: 42, y: 40), CGPoint(x: 58, y: 40), r: 4.3, mouth: CGPoint(x: 50, y: 48.5), width: 6.5,
             colors: c, pose: pose)
    }

    /// OpenCode and Qoder: a turtle that paddles while it works.
    static func turtle(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let skin = c.base
        for (index, foot) in [CGPoint(x: 24, y: 80), CGPoint(x: 64, y: 80), CGPoint(x: 38, y: 83), CGPoint(x: 76, y: 79)].enumerated() {
            var leg = ctx
            leg.translateBy(x: foot.x, y: foot.y)
            leg.rotate(by: .radians(0.45 * Double(pose.amount) * sin(pose.action * 2 * .pi + Double(index) * .pi)))
            leg.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: 12), cornerRadius: 5), with: .color(skin.mixed(with: .black, 0.12)))
        }
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: 14, y: 70)); tailPath.addLine(to: CGPoint(x: 5, y: 75)); tailPath.addLine(to: CGPoint(x: 15, y: 77))
        tailPath.closeSubpath()
        ctx.fill(tailPath, with: .color(skin.mixed(with: .black, 0.12)))
        // The head bobs out and in.
        let reach = 2.2 * CGFloat(sin(pose.action * 2 * .pi)) * pose.amount
        let neck = Path(roundedRect: CGRect(x: 66 + reach, y: 56, width: 14, height: 14), cornerRadius: 6)
        ctx.fill(neck, with: .color(skin))
        let head = Path(ellipseIn: CGRect(x: 66 + reach, y: 33, width: 32, height: 31))
        ctx.fill(head, with: c.body(top: 33, bottom: 66, from: skin))
        outline(&ctx, head, skin)
        // The shell over the legs and neck.
        var shell = Path()
        shell.move(to: CGPoint(x: 11, y: 74))
        shell.addCurve(to: CGPoint(x: 44, y: 32), control1: CGPoint(x: 11, y: 48), control2: CGPoint(x: 24, y: 32))
        shell.addCurve(to: CGPoint(x: 77, y: 74), control1: CGPoint(x: 64, y: 32), control2: CGPoint(x: 77, y: 48))
        shell.addQuadCurve(to: CGPoint(x: 11, y: 74), control: CGPoint(x: 44, y: 82))
        shell.closeSubpath()
        ctx.fill(shell, with: c.body(top: 32, bottom: 80, from: c.shade))
        if detail {
            var plates = ctx
            plates.clip(to: shell)
            var hex = Path()
            for k in 0..<6 {
                let a = Double(k) * .pi / 3 + .pi / 6
                let p = CGPoint(x: 44 + 11 * CGFloat(cos(a)), y: 55 + 9.5 * CGFloat(sin(a)))
                if k == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
            }
            hex.closeSubpath()
            var lines = hex
            for k in 0..<6 {
                let a = Double(k) * .pi / 3 + .pi / 6
                lines.move(to: CGPoint(x: 44 + 11 * CGFloat(cos(a)), y: 55 + 9.5 * CGFloat(sin(a))))
                lines.addLine(to: CGPoint(x: 44 + 40 * CGFloat(cos(a)), y: 55 + 34 * CGFloat(sin(a))))
            }
            plates.stroke(lines, with: .color(c.shade.mixed(with: .black, 0.35).opacity(0.55)),
                          style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        var rim = Path()
        rim.move(to: CGPoint(x: 10, y: 73))
        rim.addQuadCurve(to: CGPoint(x: 78, y: 73), control: CGPoint(x: 44, y: 83))
        ctx.stroke(rim, with: .color(c.light), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        outline(&ctx, shell, c.shade)
        gloss(&ctx, CGRect(x: 22, y: 36, width: 26, height: 10), inside: shell)
        face(&ctx, eyes: CGPoint(x: 76 + reach, y: 46), CGPoint(x: 89 + reach, y: 46), r: 3.7, mouth: CGPoint(x: 82.5 + reach, y: 54),
             width: 5.5, colors: c, pose: pose)
    }

    /// Copilot and CodeBuddy: a chubby gull that flaps while it works.
    static func gull(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let beak = c.extra
        for x in [41.0, 57] {
            var foot = Path()
            foot.move(to: CGPoint(x: x, y: 86)); foot.addLine(to: CGPoint(x: x, y: 93))
            foot.move(to: CGPoint(x: x - 3.5, y: 93.5)); foot.addLine(to: CGPoint(x: x + 3.5, y: 93.5))
            ctx.stroke(foot, with: .color(beak), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        let flap = max(0, sin(pose.action * 2 * .pi)) * Double(pose.amount)
        let body = Path(ellipseIn: CGRect(x: 19, y: 26, width: 62, height: 63))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [.white, c.base, c.shade.mixed(with: .white, 0.45)]),
                                             startPoint: CGPoint(x: 50, y: 26), endPoint: CGPoint(x: 50, y: 90)))
        outline(&ctx, body, c.shade)
        // Wings at its sides, beating while it works.
        for side in [-1.0, 1.0] {
            var wing = ctx
            wing.translateBy(x: 50 + CGFloat(side) * 27, y: 54)
            wing.rotate(by: .radians(side * (0.12 - 1.0 * flap)))
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: -5))
            shape.addQuadCurve(to: CGPoint(x: CGFloat(side) * 9, y: 21), control: CGPoint(x: CGFloat(side) * 15, y: 1))
            shape.addQuadCurve(to: CGPoint(x: 0, y: -5), control: CGPoint(x: CGFloat(side) * -5, y: 12))
            wing.fill(shape, with: .linearGradient(Gradient(colors: [c.shade.mixed(with: .white, 0.35), c.shade.mixed(with: .black, 0.1)]),
                                                   startPoint: CGPoint(x: 0, y: -5), endPoint: CGPoint(x: 0, y: 21)))
        }
        var tuft = Path()
        tuft.move(to: CGPoint(x: 47, y: 28))
        tuft.addQuadCurve(to: CGPoint(x: 52, y: 17), control: CGPoint(x: 44, y: 19))
        tuft.addQuadCurve(to: CGPoint(x: 53, y: 28), control: CGPoint(x: 55, y: 22))
        ctx.fill(tuft, with: .color(c.base.mixed(with: c.shade, 0.3)))
        gloss(&ctx, CGRect(x: 28, y: 31, width: 24, height: 11), inside: body)
        cheeks(&ctx, [CGPoint(x: 36, y: 58), CGPoint(x: 64, y: 58)], r: 4.2, colors: c, pose: pose)
        eyes(&ctx, [CGPoint(x: 40, y: 49), CGPoint(x: 60, y: 49)], r: 4.4, pose: pose)
        let open: CGFloat = pose.mood == .happy || pose.mood == .attention ? 3.4 : (pose.mood == .working ? 1.2 : 0)
        var lower = Path()
        lower.move(to: CGPoint(x: 45.5, y: 58.5))
        lower.addQuadCurve(to: CGPoint(x: 54.5, y: 58.5), control: CGPoint(x: 50, y: 64 + open))
        lower.closeSubpath()
        ctx.fill(lower, with: .color(beak.mixed(with: .black, 0.2)))
        var upper = Path()
        upper.move(to: CGPoint(x: 44, y: 57))
        upper.addQuadCurve(to: CGPoint(x: 56, y: 57), control: CGPoint(x: 50, y: 52))
        upper.addQuadCurve(to: CGPoint(x: 44, y: 57), control: CGPoint(x: 50, y: 63 - open * 0.3))
        ctx.fill(upper, with: .color(beak))
    }

    /// Cursor and Windsurf: a little boat with a face on its hull, riding the swell.
    static func boat(_ ctx: inout GraphicsContext, ground: GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        var hullContext = ctx
        hullContext.translateBy(x: 50, y: 80)
        hullContext.rotate(by: .radians(0.07 * sin(pose.action * 2 * .pi)))
        hullContext.translateBy(x: -50, y: -80)
        let flutter = 5 * CGFloat(sin(pose.action * 2 * .pi * 2)) * pose.amount
        let mast = Path(roundedRect: CGRect(x: 48, y: 13, width: 4, height: 50), cornerRadius: 2)
        hullContext.fill(mast, with: .color(c.detail))
        var flag = Path()
        flag.move(to: CGPoint(x: 52, y: 13))
        flag.addQuadCurve(to: CGPoint(x: 64, y: 16 + flutter * 0.3), control: CGPoint(x: 58, y: 11 - flutter * 0.4))
        flag.addQuadCurve(to: CGPoint(x: 52, y: 20), control: CGPoint(x: 58, y: 20 + flutter * 0.4))
        flag.closeSubpath()
        hullContext.fill(flag, with: .color(Color(red: 1, green: 0.5, blue: 0.45)))
        var sail = Path()
        sail.move(to: CGPoint(x: 54, y: 20))
        sail.addQuadCurve(to: CGPoint(x: 85, y: 56), control: CGPoint(x: 80 + flutter, y: 28))
        sail.addLine(to: CGPoint(x: 54, y: 58))
        sail.closeSubpath()
        hullContext.fill(sail, with: .linearGradient(Gradient(colors: [.white, c.light.mixed(with: c.base, 0.2)]),
                                                     startPoint: CGPoint(x: 54, y: 20), endPoint: CGPoint(x: 85, y: 58)))
        var sail2 = Path()
        sail2.move(to: CGPoint(x: 46, y: 26))
        sail2.addQuadCurve(to: CGPoint(x: 24, y: 56), control: CGPoint(x: 26 - flutter * 0.5, y: 34))
        sail2.addLine(to: CGPoint(x: 46, y: 58))
        sail2.closeSubpath()
        hullContext.fill(sail2, with: .color(c.light.mixed(with: c.base, 0.35)))
        var hull = Path()
        hull.move(to: CGPoint(x: 8, y: 61))
        hull.addLine(to: CGPoint(x: 92, y: 61))
        hull.addQuadCurve(to: CGPoint(x: 75, y: 86), control: CGPoint(x: 90, y: 82))
        hull.addLine(to: CGPoint(x: 25, y: 86))
        hull.addQuadCurve(to: CGPoint(x: 8, y: 61), control: CGPoint(x: 10, y: 82))
        hull.closeSubpath()
        hullContext.fill(hull, with: c.body(top: 61, bottom: 88, from: c.base.mixed(with: .white, 0.32)))
        var stripe = Path()
        stripe.move(to: CGPoint(x: 10, y: 66)); stripe.addLine(to: CGPoint(x: 90, y: 66))
        var stripes = hullContext
        stripes.clip(to: hull)
        stripes.stroke(stripe, with: .color(.white.opacity(0.35)), lineWidth: 2.4)
        outline(&hullContext, hull, c.base)
        face(&hullContext, eyes: CGPoint(x: 41, y: 72.5), CGPoint(x: 59, y: 72.5), r: 4, mouth: CGPoint(x: 50, y: 79.5), width: 6.5,
             colors: c, pose: pose)
        var sea = ground
        waves(&sea, y: 91, color: c.extra, pose: pose, offset: 0, opacity: 0.9)
        waves(&sea, y: 97, color: c.extra, pose: pose, offset: 3.4, opacity: 0.45)
    }

    /// Trae and Kiro: an octopus whose arms curl as it works.
    static func octopus(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let arm = c.base.mixed(with: c.shade, 0.35)
        for (index, x) in [23.0, 33, 44, 56, 67, 77].enumerated() {
            let outward = CGFloat((x - 50) / 27)
            let sway = 5 * CGFloat(sin(pose.action * 2 * .pi + Double(index) * 1.1)) * pose.amount
            var tentacle = Path()
            tentacle.move(to: CGPoint(x: x, y: 58))
            let end = CGPoint(x: CGFloat(x) + outward * 12 + sway, y: 88 + abs(outward) * -4)
            tentacle.addQuadCurve(to: end, control: CGPoint(x: CGFloat(x) + outward * 2 - sway, y: 78))
            tentacle.addQuadCurve(to: CGPoint(x: end.x + (outward >= 0 ? 6 : -6), y: end.y - 5),
                                  control: CGPoint(x: end.x + (outward >= 0 ? 6 : -6), y: end.y + 4))
            ctx.stroke(tentacle, with: .color(arm), style: StrokeStyle(lineWidth: 8.5, lineCap: .round, lineJoin: .round))
            if detail {
                ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(x) + outward * 4 - 1.6, y: 74, width: 3.2, height: 3.2)),
                         with: .color(c.light.opacity(0.8)))
            }
        }
        var head = Path()
        head.move(to: CGPoint(x: 18, y: 50))
        head.addCurve(to: CGPoint(x: 50, y: 10), control1: CGPoint(x: 18, y: 24), control2: CGPoint(x: 32, y: 10))
        head.addCurve(to: CGPoint(x: 82, y: 50), control1: CGPoint(x: 68, y: 10), control2: CGPoint(x: 82, y: 24))
        head.addCurve(to: CGPoint(x: 50, y: 69), control1: CGPoint(x: 82, y: 64), control2: CGPoint(x: 67, y: 69))
        head.addCurve(to: CGPoint(x: 18, y: 50), control1: CGPoint(x: 33, y: 69), control2: CGPoint(x: 18, y: 64))
        head.closeSubpath()
        ctx.fill(head, with: c.body(top: 10, bottom: 70))
        if detail {
            for spot in [CGRect(x: 58, y: 18, width: 7, height: 6), CGRect(x: 67, y: 27, width: 5, height: 4.5), CGRect(x: 33, y: 21, width: 4, height: 3.6)] {
                ctx.fill(Path(ellipseIn: spot), with: .color(c.light.opacity(0.55)))
            }
        }
        outline(&ctx, head, c.base)
        gloss(&ctx, CGRect(x: 27, y: 15, width: 24, height: 11), inside: head)
        face(&ctx, eyes: CGPoint(x: 41, y: 46), CGPoint(x: 59, y: 46), r: 4.6, mouth: CGPoint(x: 50, y: 56), width: 6.5,
             colors: c, pose: pose)
    }

    /// Grok, Factory and Amp: a pufferfish that puffs up while it works.
    static func puffer(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let breath = pose.mood == .working || pose.mood == .attention ? (0.5 + 0.5 * sin(pose.action * 2 * .pi)) : 0.2
        let radius = 27 + 4.5 * CGFloat(breath) * pose.amount + (pose.mood == .attention ? 3 : 0)
        let center = CGPoint(x: 46, y: 56)
        // Tail fin.
        var tail = ctx
        tail.translateBy(x: center.x + radius - 3, y: center.y)
        tail.rotate(by: .radians(0.3 * sin(pose.action * 2 * .pi * 2) * Double(pose.amount)))
        var fan = Path()
        fan.move(to: .zero)
        fan.addQuadCurve(to: CGPoint(x: 17, y: -12), control: CGPoint(x: 8, y: -12))
        fan.addQuadCurve(to: CGPoint(x: 17, y: 12), control: CGPoint(x: 12, y: 0))
        fan.addQuadCurve(to: .zero, control: CGPoint(x: 8, y: 12))
        tail.fill(fan, with: .color(c.shade))
        // Spikes.
        var spikes = Path()
        for k in 0..<16 {
            let a = Double(k) * 2 * .pi / 16 + 0.1
            func point(_ r: CGFloat, _ angle: Double) -> CGPoint {
                CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            }
            spikes.move(to: point(radius - 2, a - 0.13))
            spikes.addLine(to: point(radius + 6 + 2 * CGFloat(breath), a))
            spikes.addLine(to: point(radius - 2, a + 0.13))
            spikes.closeSubpath()
        }
        ctx.fill(spikes, with: .color(c.shade))
        let body = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        ctx.fill(body, with: c.body(top: center.y - radius, bottom: center.y + radius))
        var belly = ctx
        belly.clip(to: body)
        belly.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.8, y: center.y + radius * 0.25, width: radius * 1.6, height: radius)),
                   with: .color(c.light.mixed(with: .white, 0.35).opacity(0.9)))
        outline(&ctx, body, c.base)
        gloss(&ctx, CGRect(x: center.x - radius * 0.7, y: center.y - radius * 0.82, width: radius * 0.9, height: radius * 0.4), inside: body)
        var fin = ctx
        fin.translateBy(x: center.x + radius * 0.62, y: center.y + radius * 0.2)
        fin.rotate(by: .radians(0.35 + 0.35 * sin(pose.action * 2 * .pi * 2)))
        fin.fill(Path(ellipseIn: CGRect(x: -2, y: -3, width: 10, height: 6)), with: .color(c.shade.opacity(0.9)))
        cheeks(&ctx, [CGPoint(x: 33, y: 56), CGPoint(x: 59, y: 56)], r: 4, colors: c, pose: pose)
        eyes(&ctx, [CGPoint(x: 37, y: 48), CGPoint(x: 55, y: 48)], r: 4.6, pose: pose)
        if pose.mood == .happy || pose.mood == .failed || pose.mood == .sleeping {
            mouth(&ctx, at: CGPoint(x: 46, y: 59), width: 6.5, pose: pose)
        } else {
            // Pursed lips.
            let lips = Path(ellipseIn: CGRect(x: 43, y: 57, width: 6.5, height: pose.mood == .attention ? 6.5 : 5))
            ctx.fill(lips, with: .color(Color(red: 0.95, green: 0.45, blue: 0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: 44.8, y: 58.8, width: 2.9, height: pose.mood == .attention ? 2.9 : 1.6)),
                     with: .color(CreatureColors.ink))
        }
    }

    /// ZCode and Devin: a crab with eyes on stalks that snaps its claws as it works.
    static func crab(_ ctx: inout GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        let shuffle = 1.6 * CGFloat(sin(pose.action * 2 * .pi)) * pose.amount
        var all = ctx
        all.translateBy(x: shuffle, y: 0)
        // Legs.
        for side in [-1.0, 1.0] {
            for k in 0..<3 {
                let lift = 2.2 * CGFloat(sin(pose.action * 2 * .pi + Double(k) * 2 + (side > 0 ? .pi : 0))) * pose.amount
                var leg = Path()
                let start = CGPoint(x: 50 + CGFloat(side) * (22 + CGFloat(k) * 3), y: 68 + CGFloat(k) * 4)
                leg.move(to: start)
                leg.addLine(to: CGPoint(x: start.x + CGFloat(side) * 9, y: start.y + 3 - lift))
                leg.addLine(to: CGPoint(x: start.x + CGFloat(side) * 12, y: start.y + 12 - lift))
                all.stroke(leg, with: .color(c.shade), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
            }
        }
        // Claws: raised for news, snapping at work.
        let raise = pose.mood == .attention || pose.mood == .happy ? CGFloat(6 + 4 * sin(pose.action * 2 * .pi)) : 0
        let snap = pose.mood == .working ? 0.1 + 0.4 * max(0, sin(pose.action * 4 * .pi)) : 0.25
        for side in [-1.0, 1.0] {
            let claw = CGPoint(x: 50 + CGFloat(side) * 36, y: 40 - raise)
            var arm = Path()
            arm.move(to: CGPoint(x: 50 + CGFloat(side) * 22, y: 62))
            arm.addQuadCurve(to: CGPoint(x: claw.x - CGFloat(side) * 2, y: claw.y + 9), control: CGPoint(x: 50 + CGFloat(side) * 34, y: 64))
            all.stroke(arm, with: .color(c.shade), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            all.drawLayer { layer in
                let pincer = Path(ellipseIn: CGRect(x: claw.x - 11, y: claw.y - 11, width: 22, height: 22))
                layer.fill(pincer, with: c.body(top: claw.y - 11, bottom: claw.y + 11))
                var notch = Path()
                notch.move(to: CGPoint(x: claw.x, y: claw.y + 1))
                let reach = Double.pi / 2 + (side < 0 ? 0.35 : -0.35)
                for angle in [reach - snap - 0.35, reach + snap + 0.35].map({ $0 - .pi }) {
                    notch.addLine(to: CGPoint(x: claw.x + 16 * CGFloat(cos(angle)), y: claw.y + 16 * CGFloat(sin(angle))))
                }
                notch.closeSubpath()
                layer.blendMode = .destinationOut
                layer.fill(notch, with: .color(.black))
            }
        }
        let body = Path(ellipseIn: CGRect(x: 18, y: 46, width: 64, height: 38))
        // Eye stalks.
        let blinkScale = 1 - pose.blink
        for x in [39.0, 61] {
            var stalk = Path()
            stalk.move(to: CGPoint(x: x + (x < 50 ? 3 : -3), y: 52)); stalk.addLine(to: CGPoint(x: x, y: 32))
            all.stroke(stalk, with: .color(c.base), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
            let white = CGRect(x: x - 7, y: 31 - 7 * blinkScale - 0.6, width: 14, height: max(1.6, 14 * blinkScale))
            all.fill(Path(ellipseIn: white), with: .color(.white))
            all.stroke(Path(ellipseIn: white), with: .color(c.shade.opacity(0.6)), lineWidth: 1.2)
            switch pose.mood {
            case .happy, .failed, .sleeping:
                var inner = all
                eyes(&inner, [CGPoint(x: x, y: 31)], r: 3.6, pose: pose)
            default:
                if blinkScale > 0.3 {
                    let pupil = CGPoint(x: x + pose.look.x * 2.4, y: 31.5 + pose.look.y * 2.2)
                    let r: CGFloat = 3.7 * pose.eyeScale
                    all.fill(Path(ellipseIn: CGRect(x: pupil.x - r, y: pupil.y - r * blinkScale, width: 2 * r, height: 2 * r * blinkScale)),
                             with: .color(CreatureColors.ink))
                    all.fill(Path(ellipseIn: CGRect(x: pupil.x - 2.2, y: pupil.y - 2.4, width: 2.2, height: 2.2)), with: .color(.white))
                }
            }
        }
        all.fill(body, with: c.body(top: 46, bottom: 84))
        outline(&all, body, c.base)
        gloss(&all, CGRect(x: 28, y: 49, width: 28, height: 9), inside: body, angle: -0.12)
        if detail {
            for x in [36.0, 64] {
                all.fill(Path(ellipseIn: CGRect(x: x - 2, y: 54, width: 4, height: 3)), with: .color(c.light.opacity(0.6)))
            }
        }
        cheeks(&all, [CGPoint(x: 33, y: 68), CGPoint(x: 67, y: 68)], r: 4, colors: c, pose: pose)
        mouth(&all, at: CGPoint(x: 50, y: 67), width: 7, pose: pose)
    }

    /// The island, for the app itself and for agents it does not know: a palm that sways.
    static func island(_ ctx: inout GraphicsContext, ground: GraphicsContext, _ c: CreatureColors, _ pose: CreaturePose, _ detail: Bool) {
        var sea = ground
        waves(&sea, y: 90, color: c.extra, pose: pose, offset: 0, opacity: 0.85)
        waves(&sea, y: 96, color: c.extra, pose: pose, offset: 2.9, opacity: 0.4)
        var mound = Path()
        mound.move(to: CGPoint(x: 9, y: 87))
        mound.addCurve(to: CGPoint(x: 91, y: 87), control1: CGPoint(x: 18, y: 58), control2: CGPoint(x: 82, y: 58))
        mound.closeSubpath()
        ctx.fill(mound, with: c.body(top: 64, bottom: 88, from: c.base))
        outline(&ctx, mound, c.base)
        var trunk = Path()
        trunk.move(to: CGPoint(x: 55, y: 67))
        trunk.addQuadCurve(to: CGPoint(x: 45, y: 29), control: CGPoint(x: 57, y: 46))
        ctx.stroke(trunk, with: .color(c.shade), style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
        if detail {
            for k in 1..<6 {
                let s = CGFloat(k) / 6
                let p = CGPoint(x: 55 + (45 - 55) * s * s + 2 * (57 - 55) * s * (1 - s), y: 67 + (29 - 67) * s)
                var ring = Path()
                ring.move(to: CGPoint(x: p.x - 3, y: p.y)); ring.addLine(to: CGPoint(x: p.x + 3, y: p.y + 1))
                ctx.stroke(ring, with: .color(c.shade.mixed(with: .black, 0.3).opacity(0.6)), lineWidth: 1.3)
            }
        }
        let leaf = c.light
        for (index, angle) in [-2.9, -2.35, -1.5, -0.75, -0.2].enumerated() {
            var frond = ctx
            frond.translateBy(x: 45, y: 29)
            frond.rotate(by: .radians(angle + 0.08 * sin(pose.angle(5.04) + Double(index))))
            var shape = Path()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: 30, y: 5), control: CGPoint(x: 16, y: -10))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: 15, y: 6))
            frond.fill(shape, with: .linearGradient(Gradient(colors: [leaf.mixed(with: .white, 0.2), leaf.mixed(with: .black, 0.25)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 30, y: 5)))
        }
        for x in [41.0, 47] {
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: 30, width: 6, height: 6)), with: .color(c.shade.mixed(with: .black, 0.25)))
        }
        face(&ctx, eyes: CGPoint(x: 41, y: 76.5), CGPoint(x: 59, y: 76.5), r: 3.4, mouth: CGPoint(x: 50, y: 81), width: 5.5,
             colors: c, pose: pose)
    }

    // MARK: Things around it

    static func accessory(_ ctx: inout GraphicsContext, _ pose: CreaturePose) {
        switch pose.mood {
        case .attention:
            let scale = 1 + 0.12 * CGFloat(sin(pose.angle(0.575)))
            var badge = ctx
            badge.translateBy(x: 86, y: 14 - pose.hop * 0.4)
            badge.scaleBy(x: scale, y: scale)
            badge.fill(Path(ellipseIn: CGRect(x: -9.5, y: -9.5, width: 19, height: 19)), with: .color(Theme.amber))
            badge.fill(Path(roundedRect: CGRect(x: -1.6, y: -6, width: 3.2, height: 7.5), cornerRadius: 1.6), with: .color(.black))
            badge.fill(Path(ellipseIn: CGRect(x: -1.8, y: 3, width: 3.6, height: 3.6)), with: .color(.black))
        case .waiting:
            var bubble = ctx
            bubble.translateBy(x: 80, y: 13)
            var shape = Path(roundedRect: CGRect(x: -15, y: -9, width: 30, height: 18), cornerRadius: 9)
            shape.move(to: CGPoint(x: -9, y: 7)); shape.addLine(to: CGPoint(x: -14, y: 14)); shape.addLine(to: CGPoint(x: -3, y: 8))
            bubble.fill(shape, with: .color(.white.opacity(0.92)))
            for k in 0..<3 {
                let lift = max(0, sin(pose.angle(1.26) - Double(k) * 0.9))
                bubble.fill(Path(ellipseIn: CGRect(x: -9.5 + CGFloat(k) * 7, y: -2 - 2 * CGFloat(lift), width: 5, height: 5)),
                            with: .color(CreatureColors.ink.opacity(0.45 + 0.55 * lift)))
            }
        case .happy:
            for (index, spot) in [CGPoint(x: 13, y: 20), CGPoint(x: 88, y: 26), CGPoint(x: 78, y: 7)].enumerated() {
                let s = CGFloat(0.55 + 0.45 * sin(pose.angle(1.24) + Double(index) * 2.1))
                var star = ctx
                star.translateBy(x: spot.x, y: spot.y)
                star.scaleBy(x: s, y: s)
                var shape = Path()
                shape.move(to: CGPoint(x: 0, y: -7))
                shape.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 1, y: -1))
                shape.addQuadCurve(to: CGPoint(x: 0, y: 7), control: CGPoint(x: 1, y: 1))
                shape.addQuadCurve(to: CGPoint(x: -7, y: 0), control: CGPoint(x: -1, y: 1))
                shape.addQuadCurve(to: CGPoint(x: 0, y: -7), control: CGPoint(x: -1, y: -1))
                star.fill(shape, with: .color(index == 1 ? Theme.amber : .white))
            }
        case .failed:
            let slide = CGFloat(pose.phase(1.8))
            var drop = ctx
            drop.translateBy(x: 84, y: 20 + 10 * slide)
            drop.opacity = Double(1 - slide * 0.7)
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: -7))
            shape.addQuadCurve(to: CGPoint(x: 0, y: 6), control: CGPoint(x: 9, y: 4))
            shape.addQuadCurve(to: CGPoint(x: 0, y: -7), control: CGPoint(x: -9, y: 4))
            drop.fill(shape, with: .color(Color(red: 0.55, green: 0.8, blue: 1)))
        case .sleeping:
            for k in 0..<2 {
                let phase = CGFloat(pose.phase(2.4, Double(k) * 1.2))
                let text = Text("z").font(.system(size: 13 + 7 * phase, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(Double(1 - phase) * 0.9))
                ctx.draw(text, at: CGPoint(x: 78 + 8 * phase, y: 22 - 16 * phase))
            }
        case .idle, .working:
            break
        }
    }
}

/// A creature in vector, alive while `lively`.
struct CreatureCanvas: View {
    var sprite: MascotSprite
    var mood: CreatureMood
    var lively: Bool
    var seed: Double
    /// A fixed moment, for pictures: nil runs the clock.
    var moment: Double?
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = CreatureColors(sprite)
        let detail = size >= 24
        if lively, moment == nil, !reduceMotion {
            // Played by Core Animation from frames drawn once: no work for the app while it moves.
            LiveCreature(sprite: sprite, mood: mood, size: size, seed: seed)
        } else {
            canvas(colors, detail: detail, pose: CreaturePose.make(mood: mood, t: moment ?? 0, seed: moment == nil ? 0 : seed,
                                                                   still: moment == nil))
        }
    }

    private func canvas(_ colors: CreatureColors, detail: Bool, pose: CreaturePose) -> some View {
        Canvas { context, canvasSize in
            CreatureArt.draw(sprite, colors: colors, pose: pose, in: context, size: canvasSize, detail: detail)
        }
    }
}

import NikoCore

extension CreatureMood {
    /// How a session's creature feels: busy at work, hopping when it needs you,
    /// pleased just after a turn, looking up while it waits, asleep after a long quiet.
    static func of(_ session: Session, now: Date) -> CreatureMood {
        switch session.phase {
        case .working: return .working
        case .needsAttention: return .attention
        case .waiting:
            let quiet = now.timeIntervalSince(session.phaseSince)
            if quiet < 90 { return .happy }
            return quiet < 30 * 60 ? .waiting : .sleeping
        }
    }

    /// Moves of its own: at work, asking for you, and for a few seconds after a turn.
    static func moves(_ session: Session, now: Date) -> Bool {
        switch session.phase {
        case .working, .needsAttention: return true
        case .waiting: return now.timeIntervalSince(session.phaseSince) < 8
        }
    }
}

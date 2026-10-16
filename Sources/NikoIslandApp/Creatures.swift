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

/// Draws a figure: its pet, in the pose of the moment.
enum CreatureArt {
    static func draw(_ sprite: MascotSprite, pose: CreaturePose, in context: GraphicsContext, size: CGSize, scale: CGFloat, detail: Bool) {
        PixelPetArt.draw(sprite.pet ?? PixelPets.island, pose: pose, in: context, size: size, scale: scale, detail: detail)
    }
}

/// A pet, alive while `lively`.
struct CreatureCanvas: View {
    var sprite: MascotSprite
    var mood: CreatureMood
    var lively: Bool
    var seed: Double
    /// A fixed moment, for pictures: nil runs the clock.
    var moment: Double?
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let detail = size >= 24
        if lively, moment == nil, !reduceMotion {
            // Played by Core Animation from frames drawn once: no work for the app while it moves.
            LiveCreature(sprite: sprite, mood: mood, size: size, seed: seed)
        } else {
            canvas(detail: detail, pose: CreaturePose.make(mood: mood, t: moment ?? 0, seed: moment == nil ? 0 : seed,
                                                                   still: moment == nil))
        }
    }

    private func canvas(detail: Bool, pose: CreaturePose) -> some View {
        let scale = displayScale
        return Canvas { context, canvasSize in
            CreatureArt.draw(sprite, pose: pose, in: context, size: canvasSize, scale: scale, detail: detail)
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

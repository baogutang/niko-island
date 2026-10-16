import AppKit
import QuartzCore
import SwiftUI

/// The welcome's passers-by and its confetti, as Core Animation layers.
///
/// The creatures were SwiftUI views moved on every frame, which kept the whole
/// page busy. Here each one is a layer handed a path and a timing once; the
/// window server moves it at the display's refresh rate with no work from the
/// app. Sprites are drawn one pixel per cell and enlarged with nearest-neighbour
/// sampling, so their edges stay hard at any size, and they are never rotated
/// (a turned pixel creature is a blurred one).
struct CreatureStageView: NSViewRepresentable {
    var stage: BackdropStage
    var unit: CGFloat
    var accent: Color
    var islandBottom: CGFloat

    func makeNSView(context: Context) -> CreatureStageNSView {
        let view = CreatureStageNSView(stage: stage)
        view.configure(unit: unit, accent: accent, islandBottom: islandBottom)
        return view
    }

    func updateNSView(_ view: CreatureStageNSView, context: Context) {
        view.configure(unit: unit, accent: accent, islandBottom: islandBottom)
    }
}

final class CreatureStageNSView: NSView {
    private struct Swimmer {
        var sprite: MascotSprite
        var size: CGFloat
        var facesLeft: Bool
        var movingRight: Bool
        /// Seconds to cross the screen; nil for one that stays where it is.
        var period: Double?
        var offset: Double
        var height: CGFloat
        var bob: CGFloat
        var bobSpeed: Double
        var drift: CGFloat = 0
    }

    private let stage: BackdropStage
    private var unit: CGFloat = 1
    private var accent = NSColor.systemTeal
    private var islandBottom: CGFloat = 26
    private var builtFor: CGSize = .zero
    private let creatures = CALayer()
    private let confetti = CAEmitterLayer()

    init(stage: BackdropStage) {
        self.stage = stage
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(creatures)
        layer?.addSublayer(confetti)
        stage.onCelebrate = { [weak self] in self?.burst() }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Top-left origin, as the rest of the welcome is laid out.
    override var isFlipped: Bool { true }

    func configure(unit: CGFloat, accent: Color, islandBottom: CGFloat) {
        let changed = unit != self.unit || islandBottom != self.islandBottom
        self.unit = unit
        self.accent = NSColor(accent)
        self.islandBottom = islandBottom
        if changed { builtFor = .zero; needsLayout = true }
    }

    override func layout() {
        super.layout()
        guard bounds.size != builtFor, bounds.width > 0 else { return }
        builtFor = bounds.size
        build()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        builtFor = .zero
        needsLayout = true
    }

    private var swimmers: [Swimmer] {
        let u = unit
        return [
            Swimmer(sprite: Mascots.whale, size: 66 * u, facesLeft: true, movingRight: true, period: 44, offset: 0.12,
                    height: 0.752, bob: 8 * u, bobSpeed: 0.5),
            Swimmer(sprite: Mascots.boat, size: 54 * u, facesLeft: true, movingRight: false, period: 68, offset: 0.55,
                    height: 0.668, bob: 5 * u, bobSpeed: 0.9),
            Swimmer(sprite: Mascots.turtle, size: 44 * u, facesLeft: false, movingRight: true, period: 58, offset: 0.8,
                    height: 0.91, bob: 9 * u, bobSpeed: 0.7),
            Swimmer(sprite: Mascots.jellyfish, size: 40 * u, facesLeft: false, movingRight: false, period: nil, offset: 0,
                    height: 0.90, bob: 14 * u, bobSpeed: 0.6, drift: 26 * u),
            Swimmer(sprite: Mascots.gull, size: 34 * u, facesLeft: false, movingRight: true, period: 29, offset: 0.7,
                    height: 0.19, bob: 12 * u, bobSpeed: 1.3),
        ]
    }

    private func build() {
        creatures.sublayers?.forEach { $0.removeFromSuperlayer() }
        creatures.frame = bounds
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        creatures.speed = reduced ? 0.25 : 1
        let now = CACurrentMediaTime()
        let scale = window?.backingScaleFactor ?? 2
        for swimmer in swimmers {
            let mood: CreatureMood = swimmer.sprite.name == Mascots.jellyfish.name ? .idle : .working
            let frames = CreatureFrames.frames(swimmer.sprite, mood: mood, points: swimmer.size, scale: scale)
            guard let first = frames.first else { continue }
            // Travel: an outer layer crosses the screen at an even pace.
            let lane = CALayer()
            lane.bounds = CGRect(x: 0, y: 0, width: swimmer.size, height: swimmer.size)
            let y = bounds.height * swimmer.height
            if let period = swimmer.period {
                let margin = swimmer.size * 1.6
                let from = swimmer.movingRight ? -margin : bounds.width + margin
                let to = swimmer.movingRight ? bounds.width + margin : -margin
                lane.position = CGPoint(x: from, y: y)
                let travel = CABasicAnimation(keyPath: "position.x")
                travel.fromValue = from
                travel.toValue = to
                travel.duration = period
                travel.repeatCount = .infinity
                travel.timeOffset = period * swimmer.offset
                travel.beginTime = now
                lane.add(travel, forKey: "travel")
            } else {
                lane.position = CGPoint(x: bounds.width * 0.86, y: y)
                let drift = CABasicAnimation(keyPath: "position.x")
                drift.fromValue = bounds.width * 0.86 - swimmer.drift
                drift.toValue = bounds.width * 0.86 + swimmer.drift
                drift.duration = .pi / 0.3
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                lane.add(drift, forKey: "drift")
            }
            // Bobbing on the swell, and the two frames of its paddling.
            let body = CALayer()
            body.frame = lane.bounds
            body.contents = first
            body.contentsGravity = .resizeAspect
            body.opacity = 0.92
            if swimmer.facesLeft == swimmer.movingRight { body.transform = CATransform3DMakeScale(-1, 1, 1) }
            let bob = CABasicAnimation(keyPath: "position.y")
            bob.fromValue = body.position.y - swimmer.bob
            bob.toValue = body.position.y + swimmer.bob
            bob.duration = .pi / swimmer.bobSpeed
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bob.timeOffset = Double.random(in: 0...bob.duration)
            body.add(bob, forKey: "bob")
            if frames.count > 1 {
                let paddle = CAKeyframeAnimation(keyPath: "contents")
                paddle.values = frames
                paddle.calculationMode = .discrete
                paddle.duration = CreaturePose.loop(mood)
                paddle.repeatCount = .infinity
                paddle.timeOffset = Double.random(in: 0...CreaturePose.loop(mood))
                body.add(paddle, forKey: "paddle")
            }
            lane.addSublayer(body)
            creatures.addSublayer(lane)
        }
        setUpConfetti()
    }

    // MARK: Confetti

    private func setUpConfetti() {
        confetti.frame = bounds
        confetti.emitterPosition = CGPoint(x: bounds.midX, y: islandBottom)
        confetti.emitterShape = .point
        confetti.birthRate = 0
        let colors: [NSColor] = [accent, NSColor(Theme.sky), NSColor(Theme.amber), NSColor(Theme.coral), NSColor(Theme.violet), .white]
        let square = MascotImage.square()
        confetti.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = square
            cell.color = color.cgColor
            cell.birthRate = 40
            cell.lifetime = 3.4
            cell.lifetimeRange = 0.6
            cell.velocity = 560 * unit
            cell.velocityRange = 380 * unit
            // A fan below the island: mostly sideways and down (the layer's y points down).
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi * 0.42
            cell.yAcceleration = 420 * unit
            cell.spin = 3
            cell.spinRange = 9
            cell.scale = 0.55 * unit
            cell.scaleRange = 0.25 * unit
            cell.alphaSpeed = -0.25
            cell.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            return cell
        }
    }

    private func burst() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        confetti.beginTime = CACurrentMediaTime()
        confetti.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.confetti.birthRate = 0 }
    }
}

/// Creatures as images: pixel sprites one image pixel per cell, so enlarging them is
/// exact, and vector creatures as a loop of frames for Core Animation to flip through.
enum MascotImage {
    @MainActor private static var cache: [String: CGImage] = [:]
    @MainActor static func make(_ sprite: MascotSprite, frame: Int) -> CGImage? {
        let key = "\(sprite.name)/\(frame)/\(sprite.palette.keys.sorted().map { "\($0)" }.joined())"
        if let hit = cache[key] { return hit }
        let rows = sprite.frames[frame % sprite.frames.count]
        let width = sprite.columns, height = sprite.rows
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() {
                guard let color = sprite.palette[character] else { continue }
                context.setFillColor(NSColor(color).cgColor)
                // Core Graphics counts rows from the bottom.
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        let image = context.makeImage()
        cache[key] = image
        return image
    }

    /// A white 16-point square for confetti, tinted per cell.
    static func square() -> CGImage? {
        guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return context.makeImage()
    }
}

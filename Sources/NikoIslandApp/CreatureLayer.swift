import AppKit
import QuartzCore
import SwiftUI

/// Creatures that move, played by Core Animation.
///
/// Redrawing a creature in SwiftUI thirty times a second kept the app busy for as
/// long as an agent worked, which is most of the day. Instead each mood's loop is
/// drawn once, as one strip of frames side by side, and handed to a layer that
/// shows one frame of it at a time; the window server steps along the strip at no
/// cost to the app. One image per loop, not one per frame: Core Animation keeps a
/// buffer of its own for every image it shows, and frames as images of their own
/// came to 2,700 buffers and 135 MB.
@MainActor
enum CreatureFrames {
    /// A mood's loop: `count` frames side by side in one image.
    struct Strip {
        var image: CGImage
        var count: Int

        /// Where frame `index` is in the strip, in the unit square a layer's `contentsRect` uses.
        func rect(_ index: Int) -> CGRect {
            CGRect(x: CGFloat(index) / CGFloat(count), y: 0, width: 1 / CGFloat(count), height: 1)
        }
    }

    /// The widest image a layer is sure to take.
    static let widest: CGFloat = 16_384
    private static var cache: [String: Strip] = [:]
    private static var order: [String] = []

    /// Frames a second: the calm moods move slowly and need fewer.
    static func rate(_ mood: CreatureMood) -> Double {
        switch mood {
        case .idle, .waiting, .sleeping: return 12
        case .failed: return 15
        case .working, .attention, .happy: return 24
        }
    }

    static func strip(_ sprite: MascotSprite, mood: CreatureMood, points: CGFloat, scale: CGFloat) -> Strip? {
        let key = "\(sprite.name)|\(mood.rawValue)|\(Int((points * scale).rounded()))"
        if let hit = cache[key] { return hit }
        let loop = CreaturePose.loop(mood)
        let side = max(1, points * scale)
        let count = min(max(2, Int((loop * rate(mood)).rounded())), max(2, Int(widest / side)))
        let seed = MascotView.seed(sprite.name)
        let detail = points >= 24
        let sheet = Canvas { context, _ in
            for index in 0..<count {
                var cell = context
                cell.translateBy(x: CGFloat(index) * points, y: 0)
                cell.clip(to: Path(CGRect(x: 0, y: 0, width: points, height: points)))
                let pose = CreaturePose.make(mood: mood, t: loop * Double(index) / Double(count), seed: seed, still: false)
                CreatureArt.draw(sprite, pose: pose, in: cell, size: CGSize(width: points, height: points), scale: scale, detail: detail)
            }
        }
        .frame(width: CGFloat(count) * points, height: points)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        let strip = Strip(image: image, count: count)
        cache[key] = strip
        order.append(key)
        // A few dozen loops at most: each is one image of a few hundred kilobytes.
        if order.count > 48 { cache[order.removeFirst()] = nil }
        return strip
    }
}

/// A moving creature for SwiftUI: a layer that plays its mood's frames.
struct LiveCreature: NSViewRepresentable {
    var sprite: MascotSprite
    var mood: CreatureMood
    var size: CGFloat
    /// 0…1: where in its loop this one starts, so creatures side by side are out of step.
    var seed: Double

    func makeNSView(context: Context) -> LiveCreatureView { LiveCreatureView() }

    func updateNSView(_ view: LiveCreatureView, context: Context) {
        view.show(sprite: sprite, mood: mood, size: size, seed: seed)
    }
}

final class LiveCreatureView: NSView {
    private let player = CALayer()
    private var shown: (sprite: MascotSprite, mood: CreatureMood, size: CGFloat, seed: Double)?
    private var key = ""

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        player.contentsGravity = .resizeAspect
        // Pixel art, and frames side by side in one image: sampled without blending, so the
        // edge of the next frame can never show at the edge of this one.
        player.magnificationFilter = .nearest
        player.minificationFilter = .nearest
        layer?.addSublayer(player)
    }

    required init?(coder: NSCoder) { nil }

    // The row or island underneath takes the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        replay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        replay()
    }

    private func replay() {
        guard let shown else { return }
        key = ""
        show(sprite: shown.sprite, mood: shown.mood, size: shown.size, seed: shown.seed)
    }

    func show(sprite: MascotSprite, mood: CreatureMood, size: CGFloat, seed: Double) {
        shown = (sprite, mood, size, seed)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let next = "\(sprite.name)|\(mood.rawValue)|\(size)|\(scale)|\(seed)"
        guard next != key else { return }
        key = next
        let strip = CreatureFrames.strip(sprite, mood: mood, points: size, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        player.removeAnimation(forKey: "loop")
        player.contents = strip?.image
        player.contentsRect = strip?.rect(0) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        player.contentsScale = scale
        CATransaction.commit()
        guard let strip, strip.count > 1 else { return }
        let loop = CreaturePose.loop(mood)
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (0..<strip.count).map { NSValue(rect: strip.rect($0)) }
        animation.calculationMode = .discrete
        animation.duration = loop
        animation.repeatCount = .infinity
        animation.timeOffset = loop * seed
        animation.isRemovedOnCompletion = false
        player.add(animation, forKey: "loop")
    }
}

/// The light along the bottom of the closed island while agents work, moved by Core Animation.
struct EdgeSheen: NSViewRepresentable {
    var color: Color

    func makeNSView(context: Context) -> EdgeSheenView { EdgeSheenView() }

    func updateNSView(_ view: EdgeSheenView, context: Context) { view.tint = NSColor(color) }
}

final class EdgeSheenView: NSView {
    private let streak = CAGradientLayer()
    private var builtFor: CGSize = .zero
    var tint: NSColor = .systemTeal {
        didSet { if tint != oldValue { builtFor = .zero; needsLayout = true } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        streak.startPoint = CGPoint(x: 0, y: 0.5)
        streak.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(streak)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard bounds.size != builtFor, bounds.width > 0 else { return }
        builtFor = bounds.size
        let width = bounds.width * 0.38
        streak.colors = [tint.withAlphaComponent(0).cgColor, tint.withAlphaComponent(0.95).cgColor, tint.withAlphaComponent(0).cgColor]
        streak.cornerRadius = 0.8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit's y points up: the bottom edge is y = 0.
        streak.frame = CGRect(x: -width, y: 0.3, width: width, height: 1.6)
        CATransaction.commit()
        streak.removeAllAnimations()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { streak.opacity = 0; return }
        let run = CAKeyframeAnimation(keyPath: "position.x")
        run.values = [-width / 2, bounds.width + width / 2, bounds.width + width / 2]
        run.keyTimes = [0, 0.8, 1]
        run.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        run.duration = 2.4
        run.repeatCount = .infinity
        run.isRemovedOnCompletion = false
        streak.add(run, forKey: "run")
    }
}

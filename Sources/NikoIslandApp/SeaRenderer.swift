import AppKit
import MetalKit
import NikoCore
import SwiftUI

/// The welcome's night sea, drawn on the GPU.
///
/// One fragment shader computes every pixel of the sky, the aurora, the stars,
/// the moon, the island's opening ripple and the waves, at the display's own
/// resolution and in step with its refresh. Nothing is drawn small and
/// stretched (that is what made the old aurora soft), and the CPU only hands
/// over a few numbers per frame: the page is never laid out again because the
/// pointer moved. The shader is compiled from source when first needed, so the
/// build needs nothing beyond the Swift toolchain.
enum SeaShader {
    struct Uniforms {
        var resolution: SIMD2<Float>
        var pointer: SIMD2<Float>
        var accent: SIMD4<Float>
        var time: Float
        var intro: Float
        /// Pixels per point.
        var backing: Float
        /// Design units (`u`) per point.
        var unit: Float
        /// Where the island ends, in points from the top.
        var islandBottom: Float
        var padding: SIMD3<Float> = .zero
    }

    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float2 pointer;
        float4 accent;
        float time;
        float intro;
        float backing;
        float unit;
        float islandBottom;
        float3 padding;
    };

    struct Out { float4 position [[position]]; };

    vertex Out sea_vertex(uint id [[vertex_id]]) {
        // One triangle that covers the screen.
        float2 p = float2((id << 1) & 2, id & 2);
        Out out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float2 hash22(float2 p) {
        float n = hash21(p);
        return float2(n, hash21(p + n + 17.17));
    }

    static float3 over(float3 base, float3 color, float alpha) { return mix(base, color, clamp(alpha, 0.0, 1.0)); }

    static float3 screen_blend(float3 base, float3 color, float alpha) {
        float3 lit = 1.0 - (1.0 - base) * (1.0 - color);
        return mix(base, lit, clamp(alpha, 0.0, 1.0));
    }

    // A square of side `side` points centred at `c`, with a one-pixel soft edge so it stays crisp but never jaggy.
    static float square(float2 p, float2 c, float side, float px) {
        float2 d = abs(p - c) - side * 0.5;
        float outside = max(d.x, d.y);
        return clamp(0.5 - outside / px, 0.0, 1.0);
    }

    fragment float4 sea_fragment(Out in [[stage_in]], constant Uniforms &U [[buffer(0)]]) {
        float px = 1.0 / U.backing;                 // one pixel, in points
        float2 p = in.position.xy * px;             // this pixel, in points, from the top left
        float W = U.resolution.x * px, H = U.resolution.y * px;
        float u = U.unit, t = U.time, intro = U.intro;
        float2 ptr = U.pointer;
        float3 accent = U.accent.rgb;
        const float3 skyBlue = float3(0.45, 0.72, 1.0);
        const float3 violet = float3(0.72, 0.62, 1.0);
        const float3 coral = float3(1.0, 0.47, 0.43);

        // Sky: deep at the top, lighter towards the horizon.
        float v = p.y / H;
        float3 col = v < 0.5 ? mix(float3(0.010, 0.012, 0.030), float3(0.018, 0.060, 0.120), v / 0.5)
                             : mix(float3(0.018, 0.060, 0.120), float3(0.020, 0.115, 0.165), (v - 0.5) / 0.5);

        // Slow light behind everything, leaning a little towards the pointer.
        float3 lightColor[4] = { accent, skyBlue, violet, coral };
        float4 light[4] = { float4(0.22, 0.28, 0.10, 0.0), float4(0.74, 0.22, 0.08, 1.7),
                            float4(0.50, 0.44, 0.07, 3.1), float4(0.88, 0.54, 0.045, 4.4) };
        for (int i = 0; i < 4; i++) {
            float2 c = float2(W * (light[i].x + 0.05 * sin(t * 0.07 + light[i].w) + ptr.x * 0.03),
                              H * (light[i].y + 0.04 * cos(t * 0.05 + light[i].w) + ptr.y * 0.03));
            float r = W * 0.34;
            float a = light[i].z * 2.2 * max(0.0, 1.0 - length(p - c) / r);
            col = over(col, lightColor[i], a * a * (3.0 - 2.0 * a) * 0.9 + a * 0.1);
        }

        // Aurora: three curtains, worked out per pixel, so they are soft without being blurry.
        float auroraFade = 0.85 * clamp((intro - 0.5) / 2.2, 0.0, 1.0);
        if (auroraFade > 0.0 && v < 0.62) {
            float3 curtainColor[3] = { accent, skyBlue, violet };
            float4 curtain[3] = { float4(0.20, 0.016, 0.21, 0.0), float4(0.27, 0.011, 0.16, 2.1), float4(0.15, 0.021, 0.27, 4.0) };
            float xs = (p.x + ptr.x * 60.0) / 6.0;   // the scale the curtains were designed at
            for (int i = 0; i < 3; i++) {
                float level = curtain[i].x, freq = curtain[i].y, speed = curtain[i].z, phase = curtain[i].w;
                float wave = sin(xs * freq * 6.0 + t * speed + phase) + 0.5 * sin(xs * freq * 14.0 - t * speed * 1.6 + phase * 2.0);
                float top = H * (level + 0.045 * wave);
                float fall = H * (0.20 + 0.07 * sin(xs * 0.11 + t * 0.23 + phase));
                float s = (p.y - top) / fall;
                if (s < -0.15 || s > 1.05) continue;
                // Bright at the hem, fading upwards into the sky and downwards into the night.
                float profile = smoothstep(-0.12, 0.22, s) * (1.0 - smoothstep(0.22, 1.0, s));
                // Rays: broad brighter bands that wander along the curtain (soft by construction, not by blurring).
                float ray = 0.5 + 0.5 * sin(xs * 0.34 + t * 0.7 + phase * 3.0) * sin(xs * 0.13 - t * 0.35);
                float a = (0.14 + 0.36 * ray * ray) * profile;
                col = screen_blend(col, curtainColor[i], a * auroraFade * 0.85);
            }
        }

        // Stars: square, in three layers; nearer ones move further with the pointer.
        if (v < 0.66) {
            for (int layer = 0; layer < 3; layer++) {
                float depth = 0.35 + 0.3 * float(layer);
                // About 150 stars on any screen, as many far ones as near ones put together.
                float cell = (64.0 + 34.0 * float(layer)) * u;
                float2 shifted = p + float2(ptr.x * 46.0 * u * depth, ptr.y * 30.0 * u * depth);
                float2 id = floor(shifted / cell);
                float2 r = hash22(id + float(layer) * 31.7);
                if (r.x > 0.62) continue;                       // some cells have no star
                float2 c = (id + 0.2 + 0.6 * hash22(id + 7.3 + float(layer))) * cell;
                float side = (depth > 0.8 ? 3.0 : 2.0) * max(1.0, u * 0.9);
                float twinkle = 0.22 + 0.78 * abs(sin(t * (0.4 + r.y) + r.x * 6.28));
                float lit = clamp((intro - 0.4 - r.y * 1.8) / 0.6, 0.0, 1.0);
                float fadeLow = 1.0 - smoothstep(0.52, 0.66, c.y / H);
                col = over(col, float3(1.0), 0.8 * twinkle * lit * fadeLow * square(shifted, c, side, px));
            }
        }

        // The moon, a little behind the stars in the parallax.
        float2 moon = float2(W * 0.82 - ptr.x * 14.0 * u, H * 0.17 - ptr.y * 9.0 * u);
        float mr = min(W, H) * 0.045;
        float md = length(p - moon);
        col = over(col, float3(1.0), 0.17 * clamp(1.0 - (md - mr) / (mr * 4.0), 0.0, 1.0) * step(mr, md));
        float disc = clamp((mr - md) / px + 0.5, 0.0, 1.0);
        float3 moonColor = float3(0.96, 0.95, 0.88);
        float3 craters[3] = { float3(-0.45, -0.5, 0.25), float3(0.2, 0.15, 0.16), float3(-0.1, 0.42, 0.1) };
        for (int i = 0; i < 3; i++) {
            float2 cc = moon + float2(craters[i].x, craters[i].y) * mr + craters[i].z * mr;
            moonColor = over(moonColor, float3(0.86, 0.85, 0.78), clamp((craters[i].z * mr - length(p - cc)) / px + 0.5, 0.0, 1.0));
        }
        col = over(col, moonColor, disc);

        // Shooting stars: one soon after the start, then every few seconds.
        if (v < 0.5) {
            float3 shooting[2] = { float3(7.0, 1.6, 0.58), float3(11.0, 5.2, 0.42) };
            for (int i = 0; i < 2; i++) {
                float period = shooting[i].x, shift = shooting[i].y, slope = shooting[i].z;
                float lap = fmod(t + shift, period);
                if (lap >= 0.95) continue;
                float progress = lap / 0.95;
                float pass = floor((t + shift) / period);
                float startX = W * (0.12 + 0.6 * abs(sin(pass * 12.9898 + shift)));
                float2 head = float2(startX + progress * W * 0.24, H * (0.06 + 0.16 * progress * slope * 2.0));
                float2 dir = normalize(float2(9.0, 9.0 * slope));
                float along = dot(head - p, dir);
                if (along < -4.0 * u || along > 170.0 * u) continue;
                float across = abs(dot(head - p, float2(-dir.y, dir.x)));
                float fade = 1.0 - clamp(along / (170.0 * u), 0.0, 1.0);
                float width = max(1.0, 3.2 * u * fade) * 0.5;
                col = over(col, float3(1.0), 0.95 * fade * sin(progress * M_PI_F) * clamp((width - across) / px + 0.5, 0.0, 1.0));
            }
        }

        // The island lands: a ring of light runs out from it across the sky.
        float ripple = (intro - 0.55) / 1.7;
        if (ripple > 0.0 && ripple < 1.0) {
            float eased = 1.0 - pow(1.0 - ripple, 3.0);
            float radius = eased * max(W, H) * 0.95;
            float2 q = p - float2(W * 0.5, U.islandBottom);
            float d = length(float2(q.x, q.y / 0.82));
            float3 rings = float3(0.0, 26.0 * u, 60.0 * u);
            float3 strength = float3(1.0, 0.5, 0.25);
            float lineWidth = (5.0 - 3.0 * eased) * u;
            for (int i = 0; i < 3; i++) {
                float r = max(0.0, radius - rings[i]);
                float ring = clamp((lineWidth * 0.5 - abs(d - r)) / px + 0.5, 0.0, 1.0);
                col = over(col, accent, 0.55 * strength[i] * (1.0 - ripple) * ring);
            }
        }

        // The sea: three swells, the nearest lowest.
        if (v > 0.6) {
            float3 bandColor[3] = { float3(0.03, 0.20, 0.27), float3(0.02, 0.15, 0.22), float3(0.015, 0.10, 0.16) };
            float4 band[3] = { float4(0.70, 16.0, 0.50, 0.9), float4(0.77, 20.0, 0.36, 2.2), float4(0.85, 26.0, 0.26, 4.0) };
            for (int i = 0; i < 3; i++) {
                float shifted = p.x + ptr.x * 40.0 * u * float(i + 1);
                float crest = H * band[i].x + sin(shifted / (140.0 * u) + t * band[i].z + band[i].w) * band[i].y * u
                            + sin(shifted / (57.0 * u) + t * band[i].z * 1.7) * band[i].y * u * 0.28;
                float inside = clamp((p.y - crest) / px + 0.5, 0.0, 1.0);
                float depth = clamp((p.y - H * band[i].x) / (H - H * band[i].x), 0.0, 1.0);
                col = over(col, bandColor[i], inside * mix(0.94, 0.99, depth));
                // A thin bright line along the crest, as moonlight catches it.
                float edge = clamp(1.0 - abs(p.y - crest) / (1.2 * u), 0.0, 1.0) * inside;
                col = over(col, float3(0.6, 0.85, 1.0), edge * 0.10 / float(i + 1));
                if (i == 0) {
                    // Moonlight breaking on the nearest swell.
                    for (int g = 0; g < 10; g++) {
                        float offset = float(g) - 4.5;
                        float span = (36.0 - abs(offset) * 5.0 + sin(t * 1.6 + float(g)) * 7.0) * u;
                        float y = H * band[0].x + (18.0 + float(g) * 13.0) * u;
                        float cx = moon.x + sin(t * 0.9 + float(g) * 1.3) * 10.0 * u;
                        float2 d = abs(p - float2(cx, y + 1.5 * u)) - float2(max(4.0, span) * 0.5, 1.5 * u);
                        float a = clamp(0.5 - max(d.x, d.y) / px, 0.0, 1.0);
                        col = over(col, float3(1.0), (0.21 - float(g) * 0.017) * a * inside);
                    }
                }
            }
            // Plankton: specks that light up where the pointer passes.
            if (v > 0.73) {
                float cell = 46.0 * u;
                float2 id = floor(p / cell);
                float2 r = hash22(id + 91.3);
                if (r.x < 0.45) {
                    float2 c = (id + 0.2 + 0.6 * hash22(id + 3.1)) * cell
                             + float2(sin(t * 0.2 + r.y * 6.28) * 12.0 * u, cos(t * 0.3 + r.x * 6.28) * 6.0 * u);
                    float2 pointer = (ptr + 0.5) * float2(W, H);
                    float nearPtr = max(0.0, 1.0 - length(c - pointer) / (260.0 * u));
                    float glow = 0.05 + 0.2 * abs(sin(t * (0.5 + r.y) + r.x * 6.28)) + 0.75 * nearPtr * nearPtr;
                    float side = (nearPtr > 0.5 ? 3.0 : 2.0) * max(1.0, u * 0.9);
                    col = over(col, accent, min(1.0, glow) * square(p, c, side, px));
                }
            }
        }

        // The night comes up out of black as the welcome begins.
        float dawn = clamp((intro - 0.15) / 1.6, 0.0, 1.0);
        col *= dawn * dawn * (3.0 - 2.0 * dawn);
        // A whisper of noise: no visible bands in the long gradients.
        col += (hash21(in.position.xy + fract(t) * 13.0) - 0.5) / 255.0;
        return float4(col, 1.0);
    }
    """#

    /// The compiled pipeline, made once per process.
    @MainActor static var pipeline: (MTLDevice, MTLRenderPipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: source, options: nil),
              let vertex = library.makeFunction(name: "sea_vertex"),
              let fragment = library.makeFunction(name: "sea_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return (device, state)
    }()

    /// The scene as a picture, for documentation images (a live Metal view cannot be photographed by SwiftUI).
    @MainActor static func image(size: CGSize, backing: CGFloat, unit: CGFloat, accent: Color, islandBottom: CGFloat,
                                 time: Double, intro: Double) -> CGImage? {
        guard let (device, state) = pipeline, let queue = device.makeCommandQueue() else { return nil }
        let width = Int(size.width * backing), height = Int(size.height * backing)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = Uniforms(resolution: SIMD2(Float(width), Float(height)), pointer: .zero, accent: rgba(accent),
                                time: Float(time), intro: Float(intro), backing: Float(backing), unit: Float(unit),
                                islandBottom: Float(islandBottom))
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func rgba(_ color: Color) -> SIMD4<Float> {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return SIMD4(Float(resolved.redComponent), Float(resolved.greenComponent), Float(resolved.blueComponent), 1)
    }
}

/// The live sea: an MTKView that draws a frame per display refresh.
struct SeaMetalView: NSViewRepresentable {
    var stage: BackdropStage
    var unit: CGFloat
    var accent: Color
    var islandBottom: CGFloat

    func makeCoordinator() -> SeaDrawer { SeaDrawer(stage: stage) }

    func makeNSView(context: Context) -> MTKView {
        let view = SeaView(frame: .zero, device: SeaShader.pipeline?.0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        context.coordinator.update(unit: unit, accent: accent, islandBottom: islandBottom)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(unit: unit, accent: accent, islandBottom: islandBottom)
    }
}

/// An MTKView that runs at the refresh rate of whatever screen it is on (120 Hz on ProMotion).
final class SeaView: MTKView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        preferredFramesPerSecond = window?.screen?.maximumFramesPerSecond ?? 60
    }

    // Clicks belong to the page above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class SeaDrawer: NSObject, MTKViewDelegate {
    private let stage: BackdropStage
    private let queue: MTLCommandQueue?
    private var unit: Float = 1
    private var accent = SIMD4<Float>(0.42, 0.88, 0.74, 1)
    private var islandBottom: Float = 26
    /// Frames drawn in the last second, for the development build's frame counter.
    private(set) var framesPerSecond = 0
    private var frameCount = 0
    private var countedSince = CACurrentMediaTime()

    init(stage: BackdropStage) {
        self.stage = stage
        queue = SeaShader.pipeline?.0.makeCommandQueue()
    }

    func update(unit: CGFloat, accent: Color, islandBottom: CGFloat) {
        self.unit = Float(unit)
        self.accent = SeaShader.rgba(accent)
        self.islandBottom = Float(islandBottom)
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        guard let (_, state) = SeaShader.pipeline, let queue, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = Date()
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let backing = Float(view.window?.backingScaleFactor ?? 2)
        var uniforms = SeaShader.Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            pointer: reduced ? .zero : SIMD2(Float(stage.pointer.width), Float(stage.pointer.height)),
            accent: accent,
            // Reduce Motion: the scene barely drifts, and the night is simply there.
            time: Float(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) * (reduced ? 0.15 : 1)),
            intro: reduced ? 30 : Float(now.timeIntervalSince(stage.began)),
            backing: backing, unit: unit, islandBottom: islandBottom)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SeaShader.Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        frameCount += 1
        let elapsed = CACurrentMediaTime() - countedSince
        if elapsed >= 1 {
            framesPerSecond = Int((Double(frameCount) / elapsed).rounded())
            stage.framesPerSecond = framesPerSecond
            frameCount = 0
            countedSince = CACurrentMediaTime()
        }
    }
}

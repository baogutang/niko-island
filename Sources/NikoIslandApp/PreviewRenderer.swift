import AppKit
import ImageIO
import NikoCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders the real views with made-up sessions into images: the README and
/// website pictures, the demo GIF and the mascot strip all come from here
/// (`niko-island internal render-preview <dir>`). Nothing touches user data.
@MainActor
enum PreviewRenderer {
    enum Scene: String, CaseIterable {
        case idle, working, attention, toast, done
        case sessions, permission, question, usage, empty
        case settingsSounds = "settings-sounds"
        case settingsAgents = "settings-agents"
        case settingsIsland = "settings-island"
        case onboarding
        case onboardingAgents = "onboarding-agents"

        var isSettings: Bool { self == .settingsSounds || self == .settingsAgents || self == .settingsIsland }
        var isOnboarding: Bool { self == .onboarding || self == .onboardingAgents }
    }

    // MARK: Sample data

    private static func event(_ fields: [String: String], input: JSONObject? = nil, host: (program: String, bundle: String?)? = nil) -> AgentEvent? {
        var object = JSONObject()
        for key in fields.keys.sorted() { object[key] = .string(fields[key] ?? "") }
        if let input { object["tool_input"] = .object(input) }
        if let host {
            var meta = JSONObject(["term_program": .string(host.program)])
            if let bundle = host.bundle { meta["bundle_id"] = .string(bundle) }
            object[AgentEvent.metaKey] = .object(meta)
        }
        return try? AgentEvent(json: .object(object))
    }

    static func demoModel(_ scene: Scene) -> AppModel {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("niko-preview-\(getpid())")
        let model = AppModel(paths: NikoPaths(root: scratch.appendingPathComponent("ni")), home: scratch, log: .inMemory())
        let now = PreviewClock.now
        var replierID: UInt64 = 1

        func send(_ source: String, _ name: String, session: String, project: String, ago: TimeInterval,
                  prompt: String? = nil, tool: String? = nil, input: JSONObject? = nil,
                  host: (program: String, bundle: String?)? = ("iTerm.app", nil), extra: [String: String] = [:], blocking: Bool = false) {
            var fields = ["source": source, "hook_event_name": name, "session_id": session, "cwd": "/Users/dev/code/" + project]
            if let prompt { fields["prompt"] = prompt }
            if let tool { fields["tool_name"] = tool }
            for (key, value) in extra { fields[key] = value }
            guard let event = event(fields, input: input, host: host) else { return }
            var replier: IngressReplier?
            if blocking {
                replier = IngressReplier.detached(id: replierID)
                replierID += 1
            }
            model.handle(IngressDelivery(event: event, evidence: AdmissionEvidence(channel: .unixSocket, peerUID: getuid()), replier: replier),
                         now: now.addingTimeInterval(-ago))
        }

        func steps(_ list: [(String, String, String)]) -> JSONObject {
            ["todos": .array(list.map { .object(["content": .string($0.0), "activeForm": .string($0.1), "status": .string($0.2)]) })]
        }

        func fleet() {
            send("claude", "UserPromptSubmit", session: "a", project: "atlas-api", ago: 320, prompt: "Fix the flaky upload retry test")
            send("claude", "PreToolUse", session: "a", project: "atlas-api", ago: 300, tool: "TodoWrite", input: steps([
                ("Reproduce the failure", "Reproducing the failure", "completed"), ("Find the race", "Finding the race", "completed"),
                ("Add a backoff", "Adding a backoff", "completed"), ("Run the upload tests", "Running the upload tests", "in_progress"),
                ("Tidy up", "Tidying up", "pending"),
            ]))
            send("claude", "PreToolUse", session: "a", project: "atlas-api", ago: 46, tool: "Bash", input: ["command": .string("swift test --filter UploadTests")])
            send("codex", "UserPromptSubmit", session: "b", project: "storefront", ago: 260, prompt: "Move the checkout form to the new validation hooks",
                 host: ("ghostty", "com.mitchellh.ghostty"))
            send("codex", "UserPromptSubmit", session: "b", project: "storefront", ago: 120, prompt: "keep the old error copy for now",
                 host: ("ghostty", "com.mitchellh.ghostty"))
            send("codex", "PreToolUse", session: "b", project: "storefront", ago: 32, tool: "Edit",
                 input: ["file_path": .string("/Users/dev/code/storefront/src/CheckoutForm.tsx")], host: ("ghostty", "com.mitchellh.ghostty"))
            send("gemini", "UserPromptSubmit", session: "c", project: "docs-site", ago: 900, prompt: "Tighten the install guide", host: ("Apple_Terminal", nil))
            send("gemini", "Stop", session: "c", project: "docs-site", ago: 372, host: ("Apple_Terminal", nil))
            send("cursor", "UserPromptSubmit", session: "d", project: "pixel-kit", ago: 75, prompt: "Find where the sprite cache is invalidated",
                 host: ("vscode", "com.todesktop.230313mzl4w4u92"))
            send("cursor", "PreToolUse", session: "d", project: "pixel-kit", ago: 18, tool: "Grep", input: ["pattern": .string("invalidate(Cache|Sprites)")],
                 host: ("vscode", "com.todesktop.230313mzl4w4u92"))
            send("opencode", "UserPromptSubmit", session: "e", project: "infra", ago: 200, prompt: "Draft the migration plan for the queue workers",
                 host: ("WezTerm", "com.github.wez.wezterm"))
            send("opencode", "PreToolUse", session: "e", project: "infra", ago: 12, tool: "Read", input: ["file_path": .string("/Users/dev/code/infra/workers/queue.tf")],
                 host: ("WezTerm", "com.github.wez.wezterm"))
        }

        let agentRows: [MaintenanceState.AgentRow] = [
            .init(id: "claude", name: "Claude Code", stability: .stable, wired: true, approvals: true),
            .init(id: "codex", name: "Codex", stability: .beta, wired: scene == .settingsAgents, approvals: true,
                  followUp: AgentRegistry.descriptor("codex")?.followUp),
            .init(id: "zcode", name: "ZCode", stability: .beta, wired: false, approvals: true),
            .init(id: "cursor", name: "Cursor", stability: .beta, wired: false),
            .init(id: "gemini", name: "Gemini CLI", stability: .beta, wired: false),
            .init(id: "opencode", name: "OpenCode", stability: .experimental, wired: false),
        ]

        /// What the transcripts add: a session nobody announced, a name, a last reply, helpers.
        func transcripts() {
            let desktop = SessionKey(source: "codex", sessionID: "desk")
            model.mergeTranscripts([
                TranscriptSnapshot(key: desktop, path: "/dev/null", cwd: "/Users/dev/code/shot", host: .codexDesktop,
                                   firstPrompt: "Add a share sheet to the capture window", lastPrompt: "Add a share sheet to the capture window",
                                   phase: .working, activity: Activity(verb: "delegating", detail: "API Tester"),
                                   updatedAt: now.addingTimeInterval(-6), phaseSince: now.addingTimeInterval(-410)),
                TranscriptSnapshot(key: SessionKey(source: "codex", sessionID: "h1"), path: "/dev/null", phase: .working, activity: .thinking,
                                   updatedAt: now, isSubagent: true, parentID: "desk"),
                TranscriptSnapshot(key: SessionKey(source: "codex", sessionID: "h2"), path: "/dev/null", phase: .working, activity: .thinking,
                                   updatedAt: now, isSubagent: true, parentID: "desk"),
                TranscriptSnapshot(key: SessionKey(source: "gemini", sessionID: "c"), path: "/dev/null", title: "Install guide",
                                   lastReply: "Shortened the guide to four steps and moved the troubleshooting notes to the end.",
                                   phase: .waiting, activity: .waiting, updatedAt: now.addingTimeInterval(-372)),
            ], now: now)
        }

        switch scene {
        case .idle:
            break
        case .empty:
            model.runningAgents = ["claude", "codex", "zcode"]
            model.maintenance.agents = agentRows
        case .working:
            send("claude", "UserPromptSubmit", session: "a", project: "atlas-api", ago: 60, prompt: "Fix the flaky upload retry test")
            send("claude", "PreToolUse", session: "a", project: "atlas-api", ago: 8, tool: "Bash", input: ["command": .string("swift test")])
            send("codex", "UserPromptSubmit", session: "b", project: "storefront", ago: 40, prompt: "Move the checkout form")
        case .toast:
            send("claude", "UserPromptSubmit", session: "a", project: "atlas-api", ago: 60, prompt: "Fix the flaky upload retry test")
            send("claude", "Stop", session: "a", project: "atlas-api", ago: 1)
        case .done:
            send("claude", "UserPromptSubmit", session: "a", project: "atlas-api", ago: 260, prompt: "Fix the flaky upload retry test")
            send("claude", "PreToolUse", session: "a", project: "atlas-api", ago: 40, tool: "TodoWrite", input: steps([
                ("Reproduce the failure", "Reproducing the failure", "completed"), ("Find the race", "Finding the race", "completed"),
                ("Add a backoff", "Adding a backoff", "completed"), ("Run the upload tests", "Running the upload tests", "completed"),
            ]))
            send("claude", "Stop", session: "a", project: "atlas-api", ago: 1, extra: [
                "last_assistant_message": "Fixed. The retry fired before the first upload had closed its stream, so two writers raced for `upload.tmp`. "
                    + "The retry now waits for the stream to close, with a **250 ms backoff**.\n\nAll 42 upload tests pass.",
            ])
        case .attention, .permission:
            fleet()
            send("claude", "PermissionRequest", session: "a", project: "atlas-api", ago: 12, tool: "Bash",
                 input: ["command": .string("git push origin fix/upload-retry-backoff")], blocking: true)
        case .question:
            fleet()
            let questions: JSONValue = .array([
                .object(["question": .string("Which validation style should the form use?"), "header": .string("Validation"), "multiSelect": .bool(false),
                         "options": .array([
                            .object(["label": .string("Validate on blur"), "description": .string("Show errors when a field loses focus")]),
                            .object(["label": .string("Validate on submit"), "description": .string("Only check when the form is sent")]),
                            .object(["label": .string("Live validation"), "description": .string("Check on every keystroke")]),
                            .object(["label": .string("Keep it as it is"), "description": .string("Leave the current behaviour alone")]),
                         ])]),
                .object(["question": .string("Which fields need it?"), "header": .string("Fields"), "multiSelect": .bool(true),
                         "options": .array([.object(["label": .string("Email")]), .object(["label": .string("Card number")])])]),
            ])
            send("codex", "PermissionRequest", session: "b", project: "storefront", ago: 9, tool: "AskUserQuestion",
                 input: ["questions": questions], host: ("ghostty", "com.mitchellh.ghostty"), blocking: true)
        case .sessions:
            fleet()
            transcripts()
            send("claude", "Notification", session: "a", project: "atlas-api", ago: 14,
                 extra: ["notification_type": "permission_prompt", "message": "Claude needs your permission to use Bash"])
        case .usage:
            fleet()
            model.usage = UsageSnapshot.demo(now: now)
            model.usageAgent = "claude"
            model.route = .usage
        case .settingsSounds:
            model.settings.soundsEnabled = true
            model.settingsPage = SettingsPage.sounds.rawValue
        case .settingsAgents:
            model.settingsPage = SettingsPage.agents.rawValue
            model.maintenance.agents = agentRows
            model.runningAgents = ["claude", "codex"]
        case .settingsIsland:
            model.settingsPage = SettingsPage.island.rawValue
        case .onboarding:
            break
        case .onboardingAgents:
            model.maintenance.agents = agentRows
            model.runningAgents = ["claude", "codex", "zcode"]
        }

        // Sample repositories are not on this disk: say what their `.git` would.
        if !model.sessions.isEmpty {
            model.branches = ["/Users/dev/code/atlas-api": "fix/upload-retry", "/Users/dev/code/storefront": "feat/validation-hooks",
                              "/Users/dev/code/shot": "main", "/Users/dev/code/infra": "queue-migration"]
        }

        switch scene {
        case .sessions, .permission, .question, .usage, .empty: model.expand(.click)
        case .toast, .done: break
        default: model.collapse()
        }
        if scene != .toast { model.dismissToast() }
        return model
    }

    // MARK: Staging

    /// A stand-in desktop: wallpaper, a hint of a menu bar, and the island on top.
    private struct Stage: View {
        @ObservedObject var model: AppModel
        var metrics: IslandMetrics
        var width: CGFloat
        var height: CGFloat?

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.36), Color(red: 0.30, green: 0.22, blue: 0.40),
                                        Color(red: 0.72, green: 0.42, blue: 0.36)], startPoint: .topLeading, endPoint: .bottomTrailing)
                menuBar
                VStack(spacing: 0) {
                    IslandBody(model: model, metrics: metrics)
                    Spacer(minLength: height == nil ? 56 : 0)
                }
            }
            .frame(width: width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.colorScheme, .dark)
        }

        private var menuBar: some View {
            HStack(spacing: 14) {
                ForEach([34, 26, 30, 38, 28], id: \.self) { item in
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: CGFloat(item), height: 7)
                }
                Spacer()
                ForEach(0..<4, id: \.self) { _ in Circle().fill(Color.white.opacity(0.55)).frame(width: 10, height: 10) }
                Capsule().fill(Color.white.opacity(0.55)).frame(width: 46, height: 7)
            }
            .padding(.horizontal, 20)
            .frame(height: metrics.bandHeight)
            .background(Color.black.opacity(0.22))
        }
    }

    static func view(for scene: Scene, metrics: IslandMetrics = .notched, width: CGFloat = 860, height: CGFloat? = nil,
                     mascotFrame: Int = 0, model: AppModel? = nil) -> AnyView {
        let model = model ?? demoModel(scene)
        if scene.isSettings {
            // A page is drawn at its full height; the long agent list is cut off below the fold.
            let page = SettingsRootView(model: model).frame(width: 860).fixedSize(horizontal: false, vertical: true)
            let framed = scene == .settingsAgents ? AnyView(page.frame(height: 700, alignment: .top).clipped()) : AnyView(page)
            return AnyView(framed
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .environment(\.isStaticPreview, true))
        }
        if scene.isOnboarding {
            return AnyView(OnboardingView(model: model, metrics: .plain, onFinish: {}, step: scene == .onboarding ? .welcome : .agents)
                .frame(width: 1440, height: 900)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .environment(\.isStaticPreview, true)
                .environment(\.mascotFrame, mascotFrame))
        }
        return AnyView(Stage(model: model, metrics: metrics, width: width, height: height)
            .environment(\.isStaticPreview, true)
            .environment(\.mascotFrame, mascotFrame))
    }

    private static func cgImage(of view: AnyView, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    static func render(_ scene: Scene, to url: URL, scale: CGFloat = 1.5, metrics: IslandMetrics = .notched) -> Bool {
        // The welcome screens are a whole display with a star field: at 1.5× they weigh 2 MB each.
        guard let image = cgImage(of: view(for: scene, metrics: metrics), scale: scene.isOnboarding ? 1 : scale) else { return false }
        return writePNG(image, to: url)
    }

    // MARK: GIFs

    private static func writeGIF(frames: [(image: CGImage, delay: Double)], to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            return false
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
                                                              kCGImagePropertyGIFDelayTime: frame.delay]] as CFDictionary
            CGImageDestinationAddImage(destination, frame.image, properties)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// A short walk through the island's states.
    static func renderDemo(to url: URL) -> Bool {
        let storyboard: [(Scene, Int, Double)] = [
            (.idle, 0, 1.1), (.working, 0, 0.55), (.working, 1, 0.55), (.working, 0, 0.55), (.working, 1, 0.55),
            (.attention, 0, 1.2), (.permission, 0, 2.6), (.working, 0, 0.5), (.working, 1, 0.5),
            (.question, 0, 2.6), (.sessions, 0, 2.2), (.usage, 0, 2.0), (.done, 0, 2.6), (.idle, 0, 0.9),
        ]
        var frames: [(CGImage, Double)] = []
        for (scene, mascotFrame, delay) in storyboard {
            guard let image = cgImage(of: view(for: scene, width: 760, height: 640, mascotFrame: mascotFrame), scale: 1) else { return false }
            frames.append((image, delay))
        }
        return writeGIF(frames: frames, to: url)
    }

    /// One PNG and one two-frame GIF per creature, plus a strip with all of them.
    static func renderMascots(to directory: URL) -> Bool {
        var ok = true
        for sprite in Mascots.all {
            let frames: [(CGImage, Double)] = (0..<2).compactMap { index in
                let view = AnyView(MascotView(sprite: sprite, size: 72, frame: index).padding(12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black)))
                return cgImage(of: view, scale: 1).map { ($0, 0.55) }
            }
            guard frames.count == 2 else { return false }
            ok = writeGIF(frames: frames, to: directory.appendingPathComponent("\(sprite.name).gif")) && ok
            ok = writePNG(frames[0].0, to: directory.appendingPathComponent("\(sprite.name).png")) && ok
        }
        let strip = AnyView(HStack(spacing: 14) {
            ForEach(Array(Mascots.all.enumerated()), id: \.offset) { _, sprite in MascotView(sprite: sprite, size: 56, frame: 0) }
        }
        .padding(.horizontal, 26).padding(.vertical, 18)
        .background(Capsule().fill(Color.black)))
        if let image = cgImage(of: strip, scale: 2) { ok = writePNG(image, to: directory.appendingPathComponent("strip.png")) && ok }
        return ok
    }
}

private struct MascotFrameKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Which animation frame creatures show in documentation images.
    var mascotFrame: Int {
        get { self[MascotFrameKey.self] }
        set { self[MascotFrameKey.self] = newValue }
    }
}

/// The app icon, drawn in code: the island as a black tab hanging from the top
/// of a dark tile, with a small creature on it. Original artwork.
@MainActor
enum IconRenderer {
    private struct IconView: View {
        var body: some View {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.27, blue: 0.44), Color(red: 0.40, green: 0.27, blue: 0.48),
                                                  Color(red: 0.86, green: 0.50, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 186, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 6))
                IslandShape(ear: 40, radius: 120)
                    .fill(Color.black)
                    .frame(width: 690, height: 440)
                    .shadow(color: .black.opacity(0.45), radius: 44, y: 24)
                HStack(spacing: 44) {
                    MascotView(sprite: Mascots.island, size: 264, frame: 0)
                    VStack(alignment: .leading, spacing: 34) {
                        Capsule().fill(Color.white).frame(width: 230, height: 46)
                        Capsule().fill(Color.white.opacity(0.42)).frame(width: 160, height: 36)
                    }
                }
                .padding(.top, 92)
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
            .frame(width: 1024, height: 1024)
        }
    }

    /// Writes a complete `.iconset` directory (for `iconutil -c icns`).
    static func writeIconset(to directory: URL) -> Bool {
        let variants: [(name: String, pixels: CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for variant in variants {
                let renderer = ImageRenderer(content: IconView())
                renderer.scale = variant.pixels / 1024
                guard let cgImage = renderer.cgImage else { return false }
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
                try png.write(to: directory.appendingPathComponent(variant.name + ".png"))
            }
            return true
        } catch {
            return false
        }
    }
}

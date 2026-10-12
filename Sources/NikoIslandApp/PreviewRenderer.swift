import AppKit
import NikoCore
import SwiftUI

/// Renders the real panel views with made-up sessions into a PNG. Used for the
/// README screenshot (`niko-island internal render-preview`) and to eyeball
/// layout without a display session. Nothing here touches the user's data.
@MainActor
enum PreviewRenderer {
    enum Scene: String, CaseIterable { case sessions, question, empty, settings, usage }

    static func demoModel(_ scene: Scene) -> AppModel {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("niko-preview-\(getpid())")
        let model = AppModel(paths: NikoPaths(root: scratch.appendingPathComponent("ni")), home: scratch, log: .inMemory())
        let now = Date()
        var nextReplier: UInt64 = 1

        func send(_ json: String, secondsAgo: TimeInterval, blocking: Bool = false) {
            guard let value = try? JSONValue.parse(json), let event = try? AgentEvent(json: value) else { return }
            let evidence = AdmissionEvidence(channel: .unixSocket, peerUID: getuid())
            var replier: IngressReplier?
            if blocking {
                replier = IngressReplier.detached(id: nextReplier)
                nextReplier += 1
            }
            model.handle(IngressDelivery(event: event, evidence: evidence, replier: replier), now: now.addingTimeInterval(-secondsAgo))
        }

        switch scene {
        case .empty:
            break
        case .settings:
            model.selectedTab = .settings
            model.maintenance.agents = [
                .init(id: "claude", name: "Claude Code", stability: .stable, wired: true),
                .init(id: "codex", name: "Codex CLI", stability: .experimental, wired: false),
            ]
        case .usage:
            model.selectedTab = .usage
            model.usage = UsageSnapshot.demo(now: now)
        case .sessions, .question:
            send(#"{"source":"claude","hook_event_name":"UserPromptSubmit","session_id":"a","cwd":"/Users/dev/code/atlas-api","prompt":"fix flaky upload retry"}"#, secondsAgo: 300)
            send(#"{"source":"claude","hook_event_name":"PreToolUse","session_id":"a","cwd":"/Users/dev/code/atlas-api","tool_name":"Bash","tool_input":{"command":"swift test --filter UploadTests"}}"#, secondsAgo: 134)
            send(#"{"source":"claude","hook_event_name":"UserPromptSubmit","session_id":"b","cwd":"/Users/dev/code/storefront","prompt":"migrate the checkout form to the new validation hooks"}"#, secondsAgo: 240)
            send(#"{"source":"claude","hook_event_name":"PreToolUse","session_id":"b","cwd":"/Users/dev/code/storefront","tool_name":"Edit","tool_input":{"file_path":"/Users/dev/code/storefront/src/CheckoutForm.tsx"}}"#, secondsAgo: 41)
            send(#"{"source":"claude","hook_event_name":"UserPromptSubmit","session_id":"c","cwd":"/Users/dev/code/docs-site","prompt":"tighten the install guide"}"#, secondsAgo: 900)
            send(#"{"source":"claude","hook_event_name":"Stop","session_id":"c","cwd":"/Users/dev/code/docs-site"}"#, secondsAgo: 372)
            if scene == .sessions {
                send(#"{"source":"claude","hook_event_name":"PermissionRequest","session_id":"a","cwd":"/Users/dev/code/atlas-api","tool_name":"Bash","tool_input":{"command":"git push origin feature/retry-backoff"}}"#, secondsAgo: 12, blocking: true)
            } else {
                send(#"{"source":"claude","hook_event_name":"PermissionRequest","session_id":"b","cwd":"/Users/dev/code/storefront","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which validation style should the form use?","header":"Validation","multiSelect":false,"options":[{"label":"Validate on blur","description":"Show errors when a field loses focus"},{"label":"Validate on submit","description":"Only check when the form is sent"},{"label":"Live validation","description":"Check on every keystroke"}]},{"question":"Which fields need it?","header":"Fields","multiSelect":true,"options":[{"label":"Email"},{"label":"Card number"}]}]}}"#, secondsAgo: 8, blocking: true)
            }
        }
        return model
    }

    static func render(_ scene: Scene, to url: URL, scale: CGFloat = 2) -> Bool {
        let model = demoModel(scene)
        let content = PanelView(model: model)
            .environment(\.isStaticPreview, true)
            .padding(28)
            .background(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.20), Color(red: 0.07, green: 0.08, blue: 0.11)],
                                       startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

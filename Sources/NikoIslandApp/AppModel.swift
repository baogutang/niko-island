import Foundation
import NikoCore

/// What the model asks of the notification layer. The real implementation
/// talks to UserNotifications; tests record the calls.
@MainActor
public protocol AttentionNotifying: AnyObject {
    func notify(kind: NikoSettings.EventKind, session: Session, body: String)
    func clear(session: SessionKey)
}

/// Main-actor state behind the panel: sessions, pending approvals, settings.
@MainActor
public final class AppModel: ObservableObject {
    public struct Badge: Equatable, Sendable {
        public var active = 0
        public var pending = 0
    }

    public enum Tab: String, Sendable, CaseIterable { case sessions, usage, settings }

    /// A blocking request waiting for an explicit user decision. Never auto-dismissed.
    public struct PendingRequest: Identifiable {
        public let id: UInt64
        public let event: AgentEvent
        public let receivedAt: Date
        public let questions: [AgentQuestion]
        public let summary: RequestSummary
        let replier: IngressReplier

        public var sessionKey: SessionKey { event.key }
        public var isQuestion: Bool { !questions.isEmpty }
    }

    public enum StartFailure: Equatable, Sendable {
        case anotherInstanceRunning
        case other(String)
    }

    public let paths: NikoPaths
    /// Home directory holding the agents' config directories (overridable for tests).
    public let home: URL
    public let hub: IngressHub
    let log: NikoLog

    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var pending: [PendingRequest] = []
    @Published public private(set) var badge = Badge()
    @Published public private(set) var grantedSessions: Set<SessionKey> = []
    @Published public private(set) var startFailure: StartFailure?
    @Published public private(set) var httpPort: UInt16 = 0
    @Published public var selectedTab: Tab = .sessions
    @Published public var settings: NikoSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(paths: paths)
            hub.updatePolicy(settings.admissionPolicy)
            reconcileHTTPIngress()
        }
    }
    @Published public internal(set) var usage = UsageSnapshot()
    @Published public internal(set) var maintenance = MaintenanceState()

    /// The panel wants to be shown (a request arrived).
    public var onAttentionNeeded: (() -> Void)?
    public weak var notifier: AttentionNotifying?
    /// Brings the session's terminal to the front; replaced in tests.
    public var jumpHandler: (Session) -> Void = { TerminalJumper.jump(to: $0) }

    private var store = SessionStore()
    private var grants = SessionGrants()
    private var unixServer: UnixIngressServer?
    private var httpServer: HTTPIngressServer?
    private var pruneTimer: Timer?
    var usageEngine: UsageEngine?

    public init(paths: NikoPaths, home: URL = NikoPaths.userHome(), log: NikoLog = .shared) {
        self.paths = paths
        self.home = home
        self.log = log
        let settings = NikoSettings.load(paths: paths)
        self.settings = settings
        self.hub = IngressHub(policy: settings.admissionPolicy, log: log)
    }

    // MARK: Lifecycle

    @discardableResult
    public func start(usage: Bool = true) -> Bool {
        do {
            try SecureDirectory.ensureTree(paths)
        } catch {
            startFailure = .other("\(error)")
            return false
        }
        log.configure(fileURL: paths.logFile)
        AppModel.raiseFileDescriptorLimit()

        hub.setHandler { [weak self] delivery in
            // Ingress queue → main actor. Order is preserved by the main queue.
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.handle(delivery) }
            }
        }
        let server = UnixIngressServer(paths: paths, hub: hub)
        do {
            try server.start()
        } catch IngressError.alreadyRunning {
            startFailure = .anotherInstanceRunning
            return false
        } catch {
            startFailure = .other("\(error)")
            log.error("ingress failed to start: \(error)")
            return false
        }
        unixServer = server
        startFailure = nil
        log.info("niko-island \(NikoVersion.current) started, socket ready")

        // Keep the shim's pointer to our bridge binary fresh while hooks are installed.
        if FileManager.default.fileExists(atPath: paths.bridgeShim.path), let bridge = Shims.locateBridgeBinary() {
            AtomicFile.write(Data((bridge + "\n").utf8), to: paths.bridgeCache.path, mode: 0o600)
            unlink(paths.bridgeMiss.path)
        }
        reconcileHTTPIngress()

        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.pruneStaleSessions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer

        if usage { startUsageEngine() }
        refreshMaintenance()
        return true
    }

    public func stop() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        usageEngine?.stop()
        usageEngine = nil
        httpServer?.stop()
        httpServer = nil
        // Closing the socket releases every waiting bridge: it sees EOF, prints
        // nothing and exits 0, so the agent falls back to its own prompt.
        unixServer?.stop()
        unixServer = nil
        hub.setHandler(nil)
    }

    private func reconcileHTTPIngress() {
        guard unixServer != nil else { return }
        if settings.httpIngressEnabled, httpServer == nil {
            let server = HTTPIngressServer(paths: paths, hub: hub, preferredPort: settings.httpPort)
            do {
                try server.start()
                httpServer = server
                httpPort = server.port
                log.info("http ingress listening on 127.0.0.1:\(server.port)")
            } catch {
                log.error("http ingress failed to start: \(error)")
            }
        } else if !settings.httpIngressEnabled, let server = httpServer {
            server.stop()
            httpServer = nil
            httpPort = 0
        }
    }

    /// GUI processes start with a soft limit of 256 descriptors; every pending
    /// approval holds one, so give ourselves room.
    static func raiseFileDescriptorLimit() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
        let wanted = min(limit.rlim_max, 4096)
        if limit.rlim_cur < wanted {
            limit.rlim_cur = wanted
            setrlimit(RLIMIT_NOFILE, &limit)
        }
    }

    // MARK: Ingress

    func handle(_ delivery: IngressDelivery, now: Date = Date()) {
        let event = delivery.event
        let change = store.apply(event, evidence: delivery.evidence, now: now)

        if let replier = delivery.replier {
            if grants.covers(event) {
                replier.send(ReplyBuilder.line(for: .allowOnce, event: event, reason: "allowed for this session"))
                store.resolveAttention(event.key, activity: Activity.forTool(event.toolName, input: event.toolInput))
            } else {
                let request = PendingRequest(id: replier.id, event: event, receivedAt: now,
                                             questions: Questions.isQuestion(event) ? Questions.parse(toolInput: event.toolInput) : [],
                                             summary: RequestSummary(event: event), replier: replier)
                pending.append(request)
                let id = request.id
                replier.onClose { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.requestWithdrawn(id) }
                    }
                }
                if !replier.isOpen {
                    requestWithdrawn(id)   // the sender left before we could even show it
                } else {
                    selectedTab = .sessions
                    if let session = store[event.key] {
                        announce(request.isQuestion ? .question : .permission, session: session,
                                 body: request.isQuestion ? (request.questions.first?.text ?? "") : (event.toolName ?? ""))
                    }
                    onAttentionNeeded?()
                }
            }
        }

        switch change {
        case .ended(let key):
            grants.revoke(key)
            notifier?.clear(session: key)
        case .becameIdle(let key):
            if let session = store[key] { announce(.idle, session: session, body: "") }
        case .updated(let key):
            if store[key]?.phase == .working { notifier?.clear(session: key) }
        }
        publish()
    }

    private func announce(_ kind: NikoSettings.EventKind, session: Session, body: String) {
        guard settings.notificationsEnabled(for: kind) || settings.soundEnabled(for: kind) else { return }
        notifier?.notify(kind: kind, session: session, body: body)
    }

    private func requestWithdrawn(_ id: UInt64) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        if !pending.contains(where: { $0.sessionKey == request.sessionKey }) {
            store.resolveAttention(request.sessionKey, activity: .thinking)
            notifier?.clear(session: request.sessionKey)
        }
        publish()
    }

    private func publish() {
        sessions = store.ordered
        grantedSessions = Set(sessions.map(\.key).filter { grants.hasGrants(for: $0) })
        badge = Badge(active: sessions.filter { $0.phase == .working }.count, pending: pending.count)
    }

    private func pruneStaleSessions() {
        let removed = store.prune()
        removed.forEach { grants.revoke($0) }
        if !removed.isEmpty { publish() }
    }

    // MARK: User actions

    /// Applies an explicit user decision to a pending request.
    public func decide(_ requestID: UInt64, _ decision: UserDecision) {
        guard let index = pending.firstIndex(where: { $0.id == requestID }) else { return }
        let request = pending.remove(at: index)
        request.replier.send(ReplyBuilder.line(for: decision, event: request.event))
        grants.record(decision, for: request.event)

        // A fresh session-wide grant also settles what is already queued for that session.
        if decision == .allowAllSession || decision == .allowAlwaysTool {
            for other in pending where other.sessionKey == request.sessionKey && grants.covers(other.event) {
                other.replier.send(ReplyBuilder.line(for: .allowOnce, event: other.event, reason: "allowed for this session"))
            }
            pending.removeAll { $0.sessionKey == request.sessionKey && grants.covers($0.event) }
        }

        let stillWaiting = pending.contains { $0.sessionKey == request.sessionKey }
        switch decision {
        case .passToTerminal:
            // The agent now asks in its own UI; the session still needs the user.
            if let session = store[request.sessionKey] { jumpHandler(session) }
        case .deny, .block:
            if !stillWaiting { store.resolveAttention(request.sessionKey, activity: .thinking) }
        case .allowOnce, .allowAlwaysTool, .allowAllSession, .answer:
            if !stillWaiting {
                store.resolveAttention(request.sessionKey,
                                       activity: Activity.forTool(request.event.toolName, input: request.event.toolInput))
            }
        }
        if !stillWaiting { notifier?.clear(session: request.sessionKey) }
        publish()
    }

    public func grantSummary(for key: SessionKey) -> (all: Bool, tools: [String]) { grants.summary(for: key) }

    public func revokeGrants(for key: SessionKey) {
        grants.revoke(key)
        publish()
    }

    public func jump(to key: SessionKey) {
        guard let session = store[key] else { return }
        jumpHandler(session)
    }

    /// Removes a card for a session that will never report again (e.g. a killed agent).
    public func dismiss(_ key: SessionKey) {
        guard !pending.contains(where: { $0.sessionKey == key }) else { return }
        store.remove(key)
        grants.revoke(key)
        hub.forget(session: key)
        publish()
    }

    public func pendingRequests(for key: SessionKey) -> [PendingRequest] {
        pending.filter { $0.sessionKey == key }
    }
}

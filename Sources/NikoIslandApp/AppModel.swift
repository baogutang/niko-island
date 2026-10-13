import AppKit
import Foundation
import NikoCore

/// What the model asks of the notification layer. The real implementation
/// talks to UserNotifications; tests record the calls.
@MainActor
public protocol AttentionNotifying: AnyObject {
    func notify(kind: NikoSettings.EventKind, session: Session, body: String)
    func clear(session: SessionKey)
}

/// Plays (or, in tests, records) the cue for an event.
@MainActor
public protocol SoundPlaying: AnyObject {
    func play(_ event: SoundEvent)
}

/// Main-actor state behind the island: sessions, pending approvals, settings.
@MainActor
public final class AppModel: ObservableObject {
    public struct Badge: Equatable, Sendable {
        public var active = 0
        public var pending = 0
    }

    /// What the expanded island is showing.
    public enum Route: String, Sendable { case sessions, usage }

    /// Why the island is open; decides when it closes again.
    public enum ExpandReason: Sendable, Equatable {
        /// The pointer is resting on it: closes when the pointer leaves.
        case hover
        /// The user opened it: stays until they click elsewhere.
        case click
        /// An agent needs a decision: stays until the user clicks elsewhere.
        case attention
    }

    /// A short notice shown in the collapsed island.
    public struct Toast: Equatable, Sendable {
        public enum Kind: Sendable { case completed, failed }
        public var key: SessionKey
        public var title: String
        public var kind: Kind
    }

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
    @Published public private(set) var isExpanded = false
    @Published public private(set) var expandReason: ExpandReason = .click
    @Published public var route: Route = .sessions
    @Published public private(set) var toast: Toast?
    /// The pending request whose details are open (the oldest one unless the user picked another).
    @Published public var focusedRequestID: UInt64?
    @Published public var settings: NikoSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(paths: paths)
            hub.updatePolicy(settings.admissionPolicy)
            reconcileHTTPIngress()
            if settings.pricingRefreshEnabled, !oldValue.pricingRefreshEnabled { refreshPricingIfDue() }
            if settings.sessionRetentionMinutes != oldValue.sessionRetentionMinutes { scout?.setWindow(settings.sessionRetention) }
            if settings.discoverSessions != oldValue.discoverSessions { reconcileScout() }
            if settings.usageResets != oldValue.usageResets { usageEngine?.setResets(settings.usageResets) }
        }
    }
    @Published public internal(set) var usage = UsageSnapshot() {
        didSet { noteRateLimits(previous: oldValue) }
    }
    @Published public internal(set) var maintenance = MaintenanceState()

    /// The island wants to be shown (a request arrived).
    public var onAttentionNeeded: (() -> Void)?
    public weak var notifier: AttentionNotifying?
    public weak var soundPlayer: SoundPlaying?
    /// Opens the settings window (set by the app delegate).
    public var onOpenSettings: (() -> Void)?
    /// Plays a cue regardless of the switches (the preview buttons in Settings).
    public var onPreviewSound: ((SoundEvent) -> Void)?
    /// The settings page that is showing (raw value of `SettingsPage`).
    @Published public var settingsPage = "general"
    /// Whose usage the usage view shows: "all" or an agent id.
    @Published public var usageAgent = "all"
    /// Agents whose app or command-line tool is running right now.
    @Published public internal(set) var runningAgents: [String] = []
    /// Shown instead of the island's usual content the first time the app runs.
    @Published public var wantsOnboarding = false
    /// Brings the session's terminal to the front; replaced in tests.
    public var jumpHandler: (Session) -> Void = { TerminalJumper.jump(to: $0) }

    private var store = SessionStore()
    private var grants = SessionGrants()
    private let inbox = DeliveryInbox()
    private var unixServer: UnixIngressServer?
    private var httpServer: HTTPIngressServer?
    private var pruneTimer: Timer?
    private var presenceTimer: Timer?
    private var toastTask: Task<Void, Never>?
    private var lastPlayed: [SoundEvent: Date] = [:]
    var usageEngine: UsageEngine?
    private var scout: TranscriptScout?
    private var scoutPrimed = false
    /// The app was started with session discovery (tests start without).
    private var scoutWanted = false
    /// Sessions the user dismissed, and when; a transcript must not bring them
    /// back until it has something new to say.
    private var dismissedAt: [SessionKey: Date] = [:]

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
    public func start(usage: Bool = true, scout: Bool? = nil) -> Bool {
        do {
            try SecureDirectory.ensureTree(paths)
        } catch {
            startFailure = .other("\(error)")
            return false
        }
        log.configure(fileURL: paths.logFile)
        AppModel.raiseFileDescriptorLimit()

        hub.setHandler { [weak self] delivery in
            // Ingress queue → main actor, in order. Deliveries are queued and
            // drained in bounded batches so a burst of events cannot starve
            // the UI or trigger one re-render per event.
            guard let self else { return }
            if self.inbox.push(delivery) { self.scheduleDrain() }
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

        if scout ?? usage { startPresence() }
        if usage { startUsageEngine() }
        if scout ?? usage { startScout() }
        refreshMaintenance()
        return true
    }

    // MARK: Agents that are running

    private func startPresence() {
        refreshPresence()
        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.refreshPresence() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        presenceTimer = timer
    }

    func refreshPresence() {
        let apps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task.detached(priority: .utility) {
            let running = AgentPresence.running(apps: apps, processes: AgentPresence.runningProcessNames())
            await MainActor.run {
                if self.runningAgents != running { self.runningAgents = running }
            }
        }
    }

    // MARK: Sessions found on disk

    /// Hooks only speak when something happens. The transcripts say what is
    /// there right now: idle sessions, sessions started before the app, and
    /// agents that are not connected at all.
    /// Follows the "find sessions" setting once the app is running.
    private func reconcileScout() {
        guard scoutWanted else { return }
        if settings.discoverSessions {
            startScout()
        } else {
            scout?.stop()
            scout = nil
            scoutPrimed = false
            mergeTranscripts([])            // sessions known only from transcripts go with it
            scoutPrimed = false
        }
    }

    private func startScout() {
        scoutWanted = true
        guard scout == nil, settings.discoverSessions else { return }
        var options = TranscriptScout.Options()
        options.window = settings.sessionRetention
        let scout = TranscriptScout(home: home, options: options) { [weak self] snapshots in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.mergeTranscripts(snapshots) }
            }
        }
        self.scout = scout
        scout.start()
    }

    func mergeTranscripts(_ snapshots: [TranscriptSnapshot], now: Date = Date()) {
        let dismissed = Set(snapshots.compactMap { snapshot -> SessionKey? in
            guard let when = dismissedAt[snapshot.key] else { return nil }
            return snapshot.updatedAt <= when ? snapshot.key : nil
        })
        dismissedAt = dismissedAt.filter { dismissed.contains($0.key) }
        let changes = store.merge(snapshots, dismissed: dismissed, live: scoutPrimed, now: now)
        scoutPrimed = true
        guard !changes.isEmpty else { return }
        for change in changes { react(to: change) }
        publish()
    }

    public func stop() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        presenceTimer?.invalidate()
        presenceTimer = nil
        toastTask?.cancel()
        usageEngine?.stop()
        usageEngine = nil
        scout?.stop()
        scout = nil
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

    nonisolated private func scheduleDrain() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.drainInbox() }
        }
    }

    private func drainInbox() {
        let (batch, more) = inbox.pop(max: 64)
        for delivery in batch { process(delivery, now: Date()) }
        if !batch.isEmpty { publish() }
        if more { scheduleDrain() }   // yield the main actor between batches
    }

    /// Applies one delivery and publishes the result (previews and tests call this directly).
    func handle(_ delivery: IngressDelivery, now: Date = Date()) {
        process(delivery, now: now)
        publish()
    }

    private func process(_ delivery: IngressDelivery, now: Date) {
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
                    pending.removeAll { $0.id == id }   // the sender left before we could even show it
                    store.resolveAttention(event.key, activity: .thinking, now: now)
                } else {
                    route = .sessions
                    if let session = store[event.key] {
                        announce(request.isQuestion ? .question : .permission, session: session,
                                 body: request.isQuestion ? (request.questions.first?.text ?? "") : (event.toolName ?? ""))
                    }
                    play(.attention)
                    if settings.expandOnAttention { expand(.attention) }
                    onAttentionNeeded?()
                }
            }
        }

        react(to: change)
    }

    private func react(to change: SessionStore.Change) {
        switch change {
        case .ended(let key):
            grants.revoke(key)
            notifier?.clear(session: key)
        case .becameIdle(let key):
            if let session = store[key] {
                announce(.idle, session: session, body: "")
                show(Toast(key: key, title: session.title, kind: .completed))
            }
            play(.completed)
        case .failed(let key):
            if let session = store[key] {
                announce(.idle, session: session, body: session.activity.detail ?? L("Stopped with an error"))
                show(Toast(key: key, title: session.title, kind: .failed))
            }
            play(.error)
        case .started(let key):
            notifier?.clear(session: key)
            play(.started)
        case .attention(let key):
            // Known only from its transcript: it can be shown and jumped to, not answered here.
            if let session = store[key] {
                announce(.question, session: session, body: L("Waiting for you in %@", session.host?.name ?? AgentRegistry.displayName(for: key.source)))
            }
            play(.attention)
        case .updated(let key):
            if store[key]?.phase == .working { notifier?.clear(session: key) }
        }
    }


    private func announce(_ kind: NikoSettings.EventKind, session: Session, body: String) {
        guard settings.notificationsEnabled(for: kind) else { return }
        notifier?.notify(kind: kind, session: session, body: body)
    }

    // MARK: Sounds

    /// Plays a cue if the user has it switched on. The same cue is not repeated
    /// within a second and a half, so a burst of events is one sound, not ten.
    func play(_ event: SoundEvent, now: Date = Date()) {
        guard settings.shouldPlay(event) else { return }
        if let last = lastPlayed[event], now.timeIntervalSince(last) < 1.5 { return }
        lastPlayed[event] = now
        soundPlayer?.play(event)
    }

    /// One warning when a rate-limit window crosses 90 %.
    private func noteRateLimits(previous: UsageSnapshot) {
        let threshold = 90.0
        let before = previous.rateLimits.map(\.usedPercent).max() ?? 0
        let after = usage.rateLimits.map(\.usedPercent).max() ?? 0
        if after >= threshold, before < threshold { play(.limit) }
    }

    // MARK: Island state

    public func expand(_ reason: ExpandReason) {
        // A deliberate open is never downgraded to a hover that closes by itself.
        if isExpanded, reason == .hover { return }
        expandReason = reason
        isExpanded = true
        toast = nil
    }

    public func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        route = .sessions
    }

    public func toggleExpanded() {
        if isExpanded { collapse() } else { expand(.click) }
    }

    /// The request shown in detail.
    public var focusedRequest: PendingRequest? {
        pending.first { $0.id == focusedRequestID } ?? pending.first
    }

    private func show(_ toast: Toast) {
        guard settings.showCompletionToast, !isExpanded else { return }
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.settings.toastSeconds ?? 5) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    public func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func requestWithdrawn(_ id: UInt64) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        if focusedRequestID == id { focusedRequestID = nil }
        if pending.isEmpty, expandReason == .attention { collapse() }
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
        if focusedRequestID == requestID { focusedRequestID = nil }
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
        // Opened for this request and nothing else is waiting: get out of the way.
        if pending.isEmpty, expandReason == .attention { collapse() }
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
        dismissedAt[key] = Date()
        grants.revoke(key)
        hub.forget(session: key)
        publish()
    }

    public func pendingRequests(for key: SessionKey) -> [PendingRequest] {
        pending.filter { $0.sessionKey == key }
    }
}

/// Thread-safe FIFO between the ingress queue and the main actor.
final class DeliveryInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [IngressDelivery] = []
    private var drainScheduled = false

    /// Returns true when the caller must schedule a drain.
    func push(_ delivery: IngressDelivery) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        queue.append(delivery)
        if drainScheduled { return false }
        drainScheduled = true
        return true
    }

    /// Takes up to `max` deliveries. `more` means another drain is needed (and is the caller's to schedule).
    func pop(max: Int) -> (batch: [IngressDelivery], more: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let count = min(max, queue.count)
        let batch = Array(queue.prefix(count))
        queue.removeFirst(count)
        if queue.isEmpty { drainScheduled = false }
        return (batch, !queue.isEmpty)
    }
}

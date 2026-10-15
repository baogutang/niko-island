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

    /// A finished turn, shown as a card under the closed island: what was
    /// asked, what the agent said last, and a way back to the session.
    public struct Completion: Equatable, Sendable {
        public var key: SessionKey
        public var source: String
        public var project: String
        public var title: String
        public var reply: String?
        public var failed = false
        public var progress: TaskProgress?
    }

    /// Turns that ended while the screen was locked or asleep.
    public struct Recap: Equatable, Sendable {
        public struct Item: Equatable, Sendable, Identifiable {
            public var key: SessionKey
            public var project: String
            public var title: String
            public var failed: Bool
            public var id: SessionKey { key }
        }
        public var items: [Item]
    }

    /// A short notice shown in the collapsed island.
    public struct Toast: Equatable, Sendable {
        public enum Kind: Sendable { case completed, failed, limitReset, limitWarning }
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
    /// The card for a turn that has just finished; nil most of the time.
    @Published public private(set) var completion: Completion?
    /// The screen is locked or asleep: nobody is there to hear or see anything.
    @Published public internal(set) var isAway = false {
        didSet { if oldValue, !isAway { welcomeBack() } }
    }
    /// What finished while nobody was there, shown once when somebody is back.
    @Published public private(set) var recap: Recap?
    /// How the last line to the phone went; nil until one was sent.
    @Published public internal(set) var pushStatus: PushClient.Outcome?
    @Published public internal(set) var hasPushKey = false
    /// Branch per working directory, for the rows that are listed.
    @Published public internal(set) var branches: [String: String] = [:]
    /// Says whether the island can be seen right now (it is away over a full-screen app). Set by the window.
    var islandIsVisible: () -> Bool = { true }
    private var completionTask: Task<Void, Never>?
    private var completionHeld = false
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
            if ProviderLimitsClient.providers.contains(where: { settings.asksProvider($0) != oldValue.asksProvider($0) })
                || settings.glmRegion != oldValue.glmRegion || settings.minimaxRegion != oldValue.minimaxRegion {
                reconcileProviderLimits()
            }
            if settings.claudeAsksItself != oldValue.claudeAsksItself {
                if settings.claudeAsksItself { askClaudeCode(force: true) } else { claudeLookup = nil }
            }
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
    /// What each provider answered the last time it was asked (opt-in lookups).
    @Published public internal(set) var providerLookups: [String: ProviderLimitsClient.Result] = [:]
    /// Whether a GLM Coding Plan key is in the Keychain (the key itself is never held here).
    @Published public internal(set) var hasGLMKey = false
    @Published public internal(set) var hasKimiKey = false
    @Published public internal(set) var hasMiniMaxKey = false
    /// A newer release, once GitHub has said so (only when the user switched the check on).
    @Published public internal(set) var availableUpdate: ReleaseInfo?
    public enum UpdateState: Equatable, Sendable { case idle, checking, upToDate, installing, failed(String) }
    @Published public internal(set) var updateState: UpdateState = .idle
    /// Tests replace this.
    var makeUpdater: () -> Updater = { Updater() }
    /// How the latest-version answer is turned into the running app being replaced (the app delegate sets it).
    var relaunch: (URL) -> Void = { _ in }

    /// How Claude Code's own look at the plan's usage last went; nil until it was asked to.
    @Published public internal(set) var claudeLookup: ClaudeCodeUsage.Outcome?
    @Published public internal(set) var claudeIsLooking = false
    var claudeLookedAt: Date?
    /// Tests replace this; the app runs the user's own `claude`.
    var claudeAsker: @Sendable (URL, NikoPaths) -> ClaudeCodeUsage.Outcome = { home, paths in ClaudeCodeUsage.ask(home: home, paths: paths) }
    var limitsClient: ProviderLimitsClient?
    /// Tests and previews replace this so that no Keychain is opened and no request leaves.
    var makeLimitsClient: (@escaping @Sendable ([String: ProviderLimitsClient.Result]) -> Void) -> ProviderLimitsClient? = { _ in nil }
    /// Agents whose app or command-line tool is running right now.
    @Published public internal(set) var runningAgents: [String] = []
    /// When each agent's hooks last reached the app (this run only): Settings shows it, so a hook
    /// that never fires is noticed. Updated at most every 20 seconds per agent.
    @Published public internal(set) var lastHeard: [String: Date] = [:]
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
    private var goneTimer: Timer?
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
            MainActor.assumeIsolated {
                self.pruneStaleSessions()
                self.checkForUpdates()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
        let goneTimer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handBackOverdueRequests()
                self.endGoneSessions()
            }
        }
        RunLoop.main.add(goneTimer, forMode: .common)
        self.goneTimer = goneTimer

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

    private var branchFolders: Set<String> = []

    /// Which branch each listed session's directory is on. Read off the main thread: it is a handful of small files.
    func refreshBranches() {
        guard settings.showsChip(.branch) else {
            if !branches.isEmpty { branches = [:] }
            return
        }
        let directories = Array(Set(sessions.compactMap(\.cwd))).prefix(32)
        guard !directories.isEmpty else { return }
        let apply: @MainActor @Sendable ([String: String]) -> Void = { [weak self] found in
            guard let self, self.branches != found else { return }
            self.branches = found
        }
        DispatchQueue.global(qos: .utility).async {
            var found: [String: String] = [:]
            for directory in directories { found[directory] = GitInfo.branch(cwd: directory) }
            let result = found
            DispatchQueue.main.async {
                MainActor.assumeIsolated { apply(result) }
            }
        }
    }

    // MARK: Deciding from the keyboard

    public enum KeyDecision { case allow, deny }

    /// ⌃⌥A / ⌃⌥D. A decision is only taken for a request that is on screen:
    /// if the island is closed, the first press opens it on the request and
    /// decides nothing. Questions are never answered this way.
    @discardableResult
    public func decideByKey(_ decision: KeyDecision) -> Bool {
        guard settings.decisionHotkeys, let request = focusedRequest else { return false }
        guard isExpanded, route == .sessions else {
            route = .sessions
            focusedRequestID = request.id
            expand(.attention)
            return false
        }
        guard !request.isQuestion else { return false }
        decide(request.id, decision == .allow ? .allowOnce : .deny)
        return true
    }

    /// Answers the oldest permission request of one session: what "Allow once" and
    /// "Deny" on its notification do. A question is never answered this way; if
    /// the request has gone, nothing happens.
    @discardableResult
    public func decide(forSession key: SessionKey, _ decision: KeyDecision) -> Bool {
        guard let request = pending.first(where: { $0.sessionKey == key && !$0.isQuestion }) else { return false }
        decide(request.id, decision == .allow ? .allowOnce : .deny)
        return true
    }

    /// Goes to whatever needs the user most: the request that is waiting (the
    /// island opens on it), else a session with a question, else the session
    /// that stopped last.
    @discardableResult
    public func jumpToWhatNeedsMe() -> Bool {
        if let request = pending.first {
            route = .sessions
            focusedRequestID = request.id
            expand(.attention)
            return true
        }
        let waiting = sessions.filter { $0.phase == .needsAttention } + sessions.filter { $0.phase == .waiting }.sorted { $0.phaseSince > $1.phaseSince }
        guard let session = waiting.first else { return false }
        jump(to: session.key)
        return true
    }

    func refreshPresence() {
        refreshBranches()
        remindAboutWaiting()
        askClaudeCode()
        noteLimitResets()
        let apps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task.detached(priority: .utility) {
            let running = AgentPresence.running(apps: apps, processes: AgentPresence.runningProcessNames())
            await MainActor.run {
                if self.runningAgents != running { self.runningAgents = running }
            }
        }
    }

    // MARK: Requests left waiting

    /// How often one request is brought up again before the app lets it be.
    nonisolated static let reminderLimit = 3
    private var reminders: [UInt64: (count: Int, last: Date)] = [:]

    /// An agent that is blocked on you is the one thing worth saying twice.
    /// After the wait the user chose, the cue plays again (and the island opens
    /// again, if it opens for requests); a few times, then it lets be.
    func remindAboutWaiting(now: Date = Date()) {
        reminders = reminders.filter { id, _ in pending.contains { $0.id == id } }
        let minutes = settings.reminderMinutes
        // Nobody at the screen: the wait is counted from when they are back.
        guard minutes > 0, !pending.isEmpty, !(isAway && settings.quietWhenAway) else { return }
        var due = false
        for request in pending {
            let state = reminders[request.id] ?? (count: 0, last: request.receivedAt)
            guard state.count < Self.reminderLimit, now.timeIntervalSince(state.last) >= Double(minutes) * 60 else { continue }
            reminders[request.id] = (state.count + 1, now)
            due = true
            // Still unanswered after the wait: whoever it is for is evidently not looking at this screen.
            if let session = store[request.sessionKey] {
                push(request.isQuestion ? .question : .permission, session: session,
                     detail: request.isQuestion ? request.questions.first?.text
                         : [request.event.toolName, request.summary.detail].compactMap { $0 }.joined(separator: ": "),
                     now: now, escalated: true)
            }
        }
        guard due else { return }
        play(.attention, now: now)
        if !isExpanded, settings.expandOnAttention { expand(.attention) }
        onAttentionNeeded?()
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
        for snapshot in snapshots {
            guard let window = snapshot.limitReached else { continue }
            usageEngine?.noteLimitReached(agent: snapshot.key.source, window: window, at: snapshot.updatedAt)
        }
        guard !changes.isEmpty else { return }
        for change in changes { react(to: change, replyIsIn: true) }
        publish()
    }

    public func stop() {
        pruneTimer?.invalidate()
        goneTimer?.invalidate()
        pruneTimer = nil
        presenceTimer?.invalidate()
        presenceTimer = nil
        toastTask?.cancel()
        usageEngine?.stop()
        usageEngine = nil
        if let client = limitsClient {
            limitsClient = nil
            Task { await client.configure(ProviderLimitsClient.Config()) }
        }
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
        if lastHeard[event.source].map({ now.timeIntervalSince($0) >= 20 }) ?? true { lastHeard[event.source] = now }
        // Answered in the agent's own dialog: the agent goes on, but leaves our hook waiting.
        for request in pending where event.settles(request.event) {
            request.replier.send(ReplyBuilder.line(for: .passToTerminal, event: request.event))
            requestWithdrawn(request.id, resolving: false)
        }

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
                        push(request.isQuestion ? .question : .permission, session: session,
                             detail: request.isQuestion ? request.questions.first?.text
                                 : [event.toolName, request.summary.detail].compactMap { $0 }.joined(separator: ": "), now: now)
                    }
                    play(.attention)
                    if settings.expandOnAttention { expand(.attention) }
                    onAttentionNeeded?()
                }
            }
        }

        // Some agents hand over their closing words with the event itself.
        let carried = (event.raw["last_assistant_message"] ?? event.raw["lastAssistantMessage"])?.stringValue
        react(to: change, replyIsIn: carried.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false)
    }

    /// `replyIsIn`: the agent's closing words are already on the session (they came with the event, or from its transcript).
    private func react(to change: SessionStore.Change, replyIsIn: Bool = false) {
        switch change {
        case .ended(let key):
            grants.revoke(key)
            notifier?.clear(session: key)
            // Its transcript is still recent: without this it would come straight back as "waiting".
            dismissedAt[key] = Date()
        case .becameIdle(let key):
            if let session = store[key] {
                announce(.idle, session: session, body: "")
                presentWhenSettled(key, failed: false, replyIsIn: replyIsIn)
            }
            play(.completed)
        case .failed(let key):
            if let session = store[key] {
                announce(.idle, session: session, body: session.activity.detail ?? L("Stopped with an error"))
                presentWhenSettled(key, failed: true, replyIsIn: replyIsIn)
            }
            play(.error)
        case .started(let key):
            // The session is at work again: what it said last time is no longer the news.
            if completion?.key == key { dismissCompletion() }
            if toast?.key == key { toast = nil }
            notifier?.clear(session: key)
            play(.started)
        case .attention(let key):
            // Known only from its transcript: it can be shown and jumped to, not answered here.
            if let session = store[key] {
                announce(.question, session: session, body: L("Waiting for you in %@", session.host?.name ?? AgentRegistry.displayName(for: key.source)))
                push(.question, session: session)
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
        guard settings.shouldPlay(event), !(isAway && settings.quietWhenAway), !settings.isQuiet(at: now) else { return }
        if let last = lastPlayed[event], now.timeIntervalSince(last) < 1.5 { return }
        lastPlayed[event] = now
        soundPlayer?.play(event)
    }

    /// Every reading of a plan window goes into the watch; a window crossing 90 %, or running
    /// out before its reset at the pace of late, is said once per cycle.
    private func noteRateLimits(previous: UsageSnapshot) {
        let now = Date()
        var alerts: [QuotaWatch.Alert] = []
        for agent in usage.agents where agent.id != "all" {
            for window in agent.limits {
                alerts += quotaWatch.record(agent: agent.id, window: window, at: agent.limitsCapturedAt ?? now, now: now)
            }
        }
        if now.timeIntervalSince(quotaSavedAt) > 300 {
            quotaSavedAt = now
            let watch = quotaWatch, file = paths.cache.appendingPathComponent("quota-history.json")
            DispatchQueue.global(qos: .utility).async { watch.save(to: file) }
        }
        for alert in alerts { warn(alert) }
        // A window that is used up is remembered with the time it opens again.
        for agent in usage.agents where agent.id != "all" {
            for window in agent.limits where window.usedPercent >= 99.5 {
                // Only a reset that is still to come: one that has passed was said already.
                guard let resets = window.resetsAt, resets > Date() else { continue }
                fullWindows[agent.id + "/" + window.id] = (agent.id, resets)
            }
        }
    }

    /// The pace a window has been used at lately, and where it leads.
    func outlook(agent: String, window: RateLimitWindow) -> QuotaOutlook? {
        quotaWatch.outlook(agent: agent, window: window)
    }

    private func warn(_ alert: QuotaWatch.Alert) {
        let title: String
        let agent: String
        switch alert {
        case .nearlyFull(let who, let window):
            agent = who
            title = L("%@: %@ %lld%% used", AgentRegistry.displayName(for: who), LimitWords.name(window), Int(window.usedPercent.rounded()))
        case .runsOutEarly(let who, let window, let at):
            agent = who
            title = L("%@: %@ runs out in about %@", AgentRegistry.displayName(for: who), LimitWords.name(window),
                      LimitWords.span(max(60, at.timeIntervalSinceNow.wholeSeconds)))
        }
        log.info("plan limit warning for \(agent)")
        play(.limit)
        if settings.pushEnabled, hasPushKey, !settings.isQuiet(at: Date()), !settings.pushOnlyWhenAway || isAway {
            send(PushMessage(title: AgentRegistry.displayName(for: agent), body: title), subject: "limit/" + agent)
        }
        guard !isExpanded, !(isAway && settings.quietWhenAway) else { return }
        // A finished turn's card or a request matters more than this.
        guard completion == nil, pending.isEmpty else { return }
        toast = Toast(key: SessionKey(source: agent, sessionID: ""), title: title, kind: .limitWarning)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Windows that were used up, with the agent and the time they open again.
    private var fullWindows: [String: (agent: String, resets: Date)] = [:]
    /// Readings of each plan window, for its pace (kept between launches: percentages and times only).
    private lazy var quotaWatch = QuotaWatch.load(from: paths.cache.appendingPathComponent("quota-history.json"))
    private var quotaSavedAt = Date.distantPast
    /// Limits that opened again while nobody was at the screen.
    private var resetsWhileAway: [String] = []

    /// A limit that stopped an agent has reset: that is the moment its user was waiting for,
    /// so it is said once, on the island, with the "finished" cue, and to the phone if that is on.
    func noteLimitResets(now: Date = Date()) {
        let due = fullWindows.filter { $0.value.resets <= now }
        guard !due.isEmpty else { return }
        for key in due.keys { fullWindows[key] = nil }
        // A reset that passed long ago (the Mac was asleep) is not news any more.
        let agents = Set(due.values.filter { now.timeIntervalSince($0.resets) < 3600 }.map(\.agent)).sorted()
        for agent in agents {
            // Another window of the same agent is still full: it cannot work yet.
            if fullWindows.values.contains(where: { $0.agent == agent }) { continue }
            let name = AgentRegistry.displayName(for: agent)
            if settings.pushEnabled, hasPushKey, !settings.isQuiet(at: now), !settings.pushOnlyWhenAway || isAway {
                send(PushMessage(title: name, body: L("Its limit has reset. It can work again.")), subject: "reset/" + agent)
            }
            if isAway && settings.quietWhenAway {
                resetsWhileAway.append(agent)
            } else {
                announceReset(of: agent)
            }
        }
    }

    private func announceReset(of agent: String) {
        play(.completed)
        guard !isExpanded else { return }
        dismissCompletion()
        toast = Toast(key: SessionKey(source: agent, sessionID: ""), title: L("%@'s limit has reset", AgentRegistry.displayName(for: agent)), kind: .limitReset)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Island state

    public func expand(_ reason: ExpandReason) {
        // A deliberate open is never downgraded to a hover that closes by itself.
        if isExpanded, reason == .hover { return }
        expandReason = reason
        isExpanded = true
        toast = nil
        dismissCompletion()
        dismissRecap()
    }

    /// Held open for a screenshot (`-NikoOpenIsland`): nothing closes it.
    public var heldOpen = false

    public func collapse() {
        guard isExpanded, !heldOpen else { return }
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

    // MARK: A turn has finished

    /// Shows a finished turn the way the user chose: not at all, as a notice
    /// on the closed island, or as a card with the agent's last words.
    func present(_ session: Session, failed: Bool) {
        push(failed ? .failed : .finished, session: session)
        if isAway && settings.quietWhenAway {
            // Nobody is there: it is kept for when somebody is.
            missed.removeAll { $0.key == session.key }
            missed.append(Recap.Item(key: session.key, project: session.projectName, title: session.headline, failed: failed))
            return
        }
        guard !isExpanded else { return }
        let toast = Toast(key: session.key, title: session.title, kind: failed ? .failed : .completed)
        switch settings.completionStyle {
        case .off:
            return
        case .notice:
            show(toast)
        case .card:
            // A card needs something to say, somewhere to be seen, and a user who is not already looking at the session.
            let reply = failed ? (session.activity.detail ?? session.lastReply) : session.lastReply
            guard let text = reply, !text.isEmpty, islandIsVisible(), pending.isEmpty, !isFrontmost(session) else {
                show(toast)
                return
            }
            self.toast = nil
            dismissRecap()
            completion = Completion(key: session.key, source: session.source, project: session.projectName, title: session.headline,
                                    reply: text, failed: failed, progress: session.progress)
            scheduleCompletionDismissal()
        }
    }

    /// A hook says "finished" the moment the turn ends; unless the agent's last
    /// words came with it, they reach us a moment later, when its transcript is
    /// read. A card waits for them; nothing else does.
    var completionSettleDelay: TimeInterval = 1.9

    private func presentWhenSettled(_ key: SessionKey, failed: Bool, replyIsIn: Bool) {
        guard let session = store[key] else { return }
        let wantsWords = settings.completionStyle == .card || (settings.pushEnabled && settings.pushDetails)
        let waits = wantsWords && !replyIsIn && session.origin == .hooks && session.transcriptPath != nil
            && scout != nil && completionSettleDelay > 0
        guard waits else {
            present(session, failed: failed)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.completionSettleDelay ?? 0) * 1_000_000_000))
            // Asked something new in the meantime: there is nothing finished to show.
            guard let self, let current = self.store[key], current.phase == .waiting else { return }
            self.present(current, failed: failed)
        }
    }

    /// Tests replace this; the app asks which application is in front.
    var isFrontmost: (Session) -> Bool = { _ in false }

    // MARK: Back at the screen

    private var missed: [Recap.Item] = []
    private var recapTask: Task<Void, Never>?
    private var recapHeld = false

    /// Somebody is back. What ended in the meantime is said once, in one card,
    /// instead of having been said to an empty room card by card.
    private func welcomeBack() {
        let items = missed.filter { item in store[item.key]?.phase == .waiting }
        missed = []
        // A limit that opened again in the meantime is said now.
        let reset = resetsWhileAway
        resetsWhileAway = []
        defer { if recap == nil, let agent = reset.first { announceReset(of: agent) } }
        guard settings.completionStyle != .off, !items.isEmpty, !isExpanded, islandIsVisible() else { return }
        toast = nil
        dismissCompletion()
        recap = Recap(items: Array(items.suffix(4)))
        scheduleRecapDismissal()
    }

    private func scheduleRecapDismissal() {
        recapTask?.cancel()
        guard !recapHeld else { return }
        recapTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.recap = nil
        }
    }

    public func holdRecap(_ held: Bool) {
        guard held != recapHeld else { return }
        recapHeld = held
        if held { recapTask?.cancel() } else if recap != nil { scheduleRecapDismissal() }
    }

    public func dismissRecap() {
        recapTask?.cancel()
        recapHeld = false
        if recap != nil { recap = nil }
    }

    /// A line of the recap was clicked: go to that session.
    public func openRecap(_ key: SessionKey) {
        dismissRecap()
        jump(to: key)
    }

    // MARK: Answering from the island (opt-in)

    public enum ReplyState: Equatable, Sendable { case sending, sent, failed }

    /// How the last follow-up to a session went.
    @Published public private(set) var replies: [SessionKey: ReplyState] = [:]
    /// Tests replace this; the app types into the session's terminal.
    var replySender: (Session, String) async -> Bool = { _, _ in false }

    /// A follow-up can be typed for a session that has stopped and whose terminal can be addressed exactly.
    public func canReply(to key: SessionKey) -> Bool {
        guard settings.replyFromIsland, let session = store[key], session.phase == .waiting else { return false }
        return TerminalReply.channel(for: session) != nil
    }

    /// Sends what was typed into the session's terminal, as if typed there.
    public func reply(to key: SessionKey, _ text: String) {
        guard canReply(to: key), let session = store[key], let line = TerminalReply.clean(text), replies[key] != .sending else { return }
        replies[key] = .sending
        Task { [weak self] in
            guard let self else { return }
            let sent = await self.replySender(session, line)
            self.replies[key] = sent ? .sent : .failed
            if sent, self.completion?.key == key { self.dismissCompletion() }
            try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
            if self.replies[key] != .sending { self.replies[key] = nil }
        }
    }

    // MARK: A line to the phone (opt-in)

    enum PushKind { case permission, question, finished, failed }

    /// Tests replace this with a client that sends nowhere.
    var makePushClient: () -> PushClient = { PushClient() }
    private var pushClient: PushClient?

    /// What a line says. Without "say what it is about" it names the agent, the project and the kind of moment, nothing else.
    func pushMessage(_ kind: PushKind, session: Session, detail: String? = nil) -> PushMessage {
        let title = AgentRegistry.displayName(for: session.source) + " · " + session.projectName
        let words = settings.pushDetails ? detail.map { Activity.oneLine($0, limit: 140) }.flatMap { $0.isEmpty ? nil : $0 } : nil
        switch kind {
        case .permission: return PushMessage(title: title, body: words.map { L("Needs your decision: %@", $0) } ?? L("Needs your decision"))
        case .question: return PushMessage(title: title, body: words ?? L("Has a question for you"))
        case .finished: return PushMessage(title: title, body: words ?? L("Finished"))
        case .failed: return PushMessage(title: title, body: words ?? L("Stopped with an error"))
        }
    }

    /// `escalated`: a request that has been left waiting; it goes out even at the Mac, and is a line of its own.
    func push(_ kind: PushKind, session: Session, detail: String? = nil, now: Date = Date(), escalated: Bool = false) {
        guard settings.pushEnabled, hasPushKey, !settings.isQuiet(at: now) else { return }
        if settings.pushOnlyWhenAway, !isAway, !escalated { return }
        if kind == .finished || kind == .failed {
            guard settings.pushWhenFinished else { return }
        }
        let words = detail ?? ((kind == .finished || kind == .failed) ? (kind == .failed ? (session.activity.detail ?? session.lastReply) : session.lastReply) : nil)
        send(pushMessage(kind, session: session, detail: words.map { ReplyText.flattened($0, limit: 140) }),
             subject: "\(session.key.source)/\(session.key.sessionID)/\(kind)" + (escalated ? "/again/\(Int(now.timeIntervalSince1970))" : ""))
    }

    private func send(_ message: PushMessage, subject: String?) {
        if pushClient == nil { pushClient = makePushClient() }
        guard let client = pushClient else { return }
        let server = settings.pushServer
        let service = PushService(rawValue: settings.pushService) ?? .bark
        Task { [weak self] in
            let outcome = await client.send(message, server: server, service: service, subject: subject)
            self?.pushStatus = outcome
        }
    }

    /// "Send a test" in Settings: goes out whatever the other switches say.
    public func sendTestPush() {
        send(PushMessage(title: NikoVersion.displayName, body: L("This is what a line from your Mac looks like.")), subject: nil)
    }

    /// Bark's device key or ntfy's topic, typed by the user. Kept in the Keychain, never in a file.
    public func setPushKey(_ key: String?) {
        ProviderKeychain.store(key, account: PushClient.account)
        hasPushKey = ProviderKeychain.exists(PushClient.account)
        if !hasPushKey { settings.pushEnabled = false }
        pushStatus = nil
    }

    private func scheduleCompletionDismissal() {
        completionTask?.cancel()
        guard !completionHeld else { return }
        let seconds = max(8, settings.toastSeconds * 2)
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.completion = nil
        }
    }

    /// The pointer is on the card: it stays for as long as it is being read.
    public func holdCompletion(_ held: Bool) {
        guard held != completionHeld else { return }
        completionHeld = held
        if held { completionTask?.cancel() } else if completion != nil { scheduleCompletionDismissal() }
    }

    public func dismissCompletion() {
        completionTask?.cancel()
        completionHeld = false
        if completion != nil { completion = nil }
    }

    /// The card was clicked: go to the session it is about.
    public func openCompletion() {
        guard let key = completion?.key else { return }
        dismissCompletion()
        jump(to: key)
    }

    private func show(_ toast: Toast) {
        guard settings.completionStyle != .off, !isExpanded else { return }
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

    /// `resolving`: the session is no longer waiting on the user (false when the event that
    /// settled the request has already said what the session does now, or the agent asks anew).
    private func requestWithdrawn(_ id: UInt64, resolving: Bool = true) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        if focusedRequestID == id { focusedRequestID = nil }
        if pending.isEmpty, expandReason == .attention { collapse() }
        if !pending.contains(where: { $0.sessionKey == request.sessionKey }) {
            if resolving { store.resolveAttention(request.sessionKey, activity: .thinking) }
            notifier?.clear(session: request.sessionKey)
        }
        publish()
    }

    /// A request nobody answered within Settings' wait goes back to the agent's own prompt,
    /// answered by nobody. The row keeps saying that the agent needs permission.
    func handBackOverdueRequests(now: Date = Date()) {
        let minutes = settings.approvalWaitMinutes
        guard minutes > 0 else { return }
        for request in pending where now.timeIntervalSince(request.receivedAt) >= TimeInterval(minutes * 60) {
            request.replier.send(ReplyBuilder.line(for: .passToTerminal, event: request.event))
            log.info("request handed back to \(request.sessionKey.source) after \(minutes) min")
            requestWithdrawn(request.id, resolving: false)
        }
    }

    private func publish() {
        sessions = store.ordered
        grantedSessions = Set(sessions.map(\.key).filter { grants.hasGrants(for: $0) })
        badge = Badge(active: sessions.filter { $0.phase == .working }.count, pending: pending.count)
        // A folder not seen before: its branch is looked up now rather than at the next tick.
        let folders = Set(sessions.compactMap(\.cwd))
        if folders != branchFolders {
            branchFolders = folders
            refreshBranches()
        }
    }

    /// Sessions that are over without having said so leave the list: a hook session
    /// whose agent process has exited, and a session found on disk whose desktop app
    /// has been quit. Like a dismissed row, it comes back only if it is written to again.
    func endGoneSessions(now: Date = Date(),
                         isAlive: (ProcessNode) -> Bool = { ProcessInspector.path(of: $0.pid) == $0.path },
                         runningApps: Set<String>? = nil) {
        let waiting = Set(pending.map(\.sessionKey))
        var ended = store.endGone(isAlive: isAlive, keeping: waiting)
        let apps = runningApps ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for session in store.sessions.values where session.origin == .transcript && !waiting.contains(session.key) {
            guard let app = session.host?.bundleID, !apps.contains(app) else { continue }
            store.remove(session.key)
            ended.append(session.key)
        }
        guard !ended.isEmpty else { return }
        for key in ended {
            dismissedAt[key] = now
            grants.revoke(key)
            hub.forget(session: key)
            notifier?.clear(session: key)
        }
        publish()
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

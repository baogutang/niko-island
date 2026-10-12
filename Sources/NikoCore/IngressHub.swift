import Foundation

/// Handle for answering one blocking event. The transport keeps the sender's
/// connection open until `send` is called or the sender goes away.
public final class IngressReplier: @unchecked Sendable {
    public let id: UInt64
    private let lock = NSLock()
    private var transmit: (@Sendable (Data) -> Void)?
    private var closeHandlers: [@Sendable () -> Void] = []
    private var finished = false

    init(id: UInt64, transmit: @escaping @Sendable (Data) -> Void) {
        self.id = id
        self.transmit = transmit
    }

    /// A replier that goes nowhere — for previews and tests of UI code.
    public static func detached(id: UInt64) -> IngressReplier {
        IngressReplier(id: id, transmit: { _ in })
    }

    /// `true` while the sender is still waiting and no reply has been sent.
    public var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished
    }

    /// Sends the single reply line. Returns `false` if the sender is already gone
    /// or a reply was already sent.
    @discardableResult
    public func send(_ reply: JSONValue) -> Bool {
        lock.lock()
        guard !finished, let transmit else {
            lock.unlock()
            return false
        }
        finished = true
        self.transmit = nil
        closeHandlers.removeAll()
        lock.unlock()
        transmit(reply.serializedData(.compact))
        return true
    }

    /// Runs `handler` if the sender disconnects before a reply was sent
    /// (the agent was interrupted, or the user answered in the terminal).
    public func onClose(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        closeHandlers.append(handler)
        lock.unlock()
    }

    func markClosed() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        transmit = nil
        let handlers = closeHandlers
        closeHandlers.removeAll()
        lock.unlock()
        handlers.forEach { $0() }
    }
}

public struct IngressDelivery: Sendable {
    public let event: AgentEvent
    public let evidence: AdmissionEvidence
    /// Present exactly when `event.isBlocking`.
    public let replier: IngressReplier?

    public init(event: AgentEvent, evidence: AdmissionEvidence, replier: IngressReplier?) {
        self.event = event
        self.evidence = evidence
        self.replier = replier
    }
}

/// What a transport knows about the sender of one frame.
public struct IngressContext: Sendable {
    public var channel: AdmissionEvidence.Channel
    public var peerUID: uid_t?
    public var peerPID: pid_t?
    public var directory: String?
    public var defaultSource: String?

    public init(channel: AdmissionEvidence.Channel, peerUID: uid_t? = nil, peerPID: pid_t? = nil,
                directory: String? = nil, defaultSource: String? = nil) {
        self.channel = channel
        self.peerUID = peerUID
        self.peerPID = peerPID
        self.directory = directory
        self.defaultSource = defaultSource
    }
}

public enum IngressOutcome: Sendable, Equatable {
    case accepted(blocking: Bool)
    case dropped(String)
}

/// Transport-independent ingress core: validation, admission, ring buffer, fan-out.
public final class IngressHub: @unchecked Sendable {
    public struct Counters: Sendable, Equatable {
        public var received = 0
        public var admitted = 0
        public var dropped = 0
        public var malformed = 0
        public var oversize = 0
    }

    private let lock = NSLock()
    private var policy: AdmissionPolicy
    private var ring: RingBuffer<AgentEvent>
    private var admitted: Set<SessionKey> = []
    private var deniedLogged: Set<String> = []
    private var handler: (@Sendable (IngressDelivery) -> Void)?
    private var stats = Counters()
    private var nextReplierID: UInt64 = 1
    private var noisyLogBudget = 20
    public let log: NikoLog

    public init(policy: AdmissionPolicy = AdmissionPolicy(), log: NikoLog = .shared, ringCapacity: Int = 1024) {
        self.policy = policy
        self.log = log
        self.ring = RingBuffer(capacity: ringCapacity)
    }

    public func setHandler(_ handler: (@Sendable (IngressDelivery) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func updatePolicy(_ policy: AdmissionPolicy) {
        lock.lock()
        self.policy = policy
        admitted.removeAll()
        deniedLogged.removeAll()
        lock.unlock()
    }

    public var counters: Counters {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    /// The most recent admitted events, oldest first (at most `ringCapacity`).
    public var recentEvents: [AgentEvent] {
        lock.lock()
        defer { lock.unlock() }
        return ring.elements
    }

    public func forget(session key: SessionKey) {
        lock.lock()
        admitted.remove(key)
        lock.unlock()
    }

    func noteOversize(channel: AdmissionEvidence.Channel) {
        lock.lock()
        stats.oversize += 1
        stats.dropped += 1
        let shouldLog = consumeNoisyBudget()
        lock.unlock()
        if shouldLog { log.warn("ingress(\(channel.rawValue)): dropped a frame larger than the 1 MiB limit") }
    }

    func noteMalformed(channel: AdmissionEvidence.Channel, reason: String) {
        lock.lock()
        stats.malformed += 1
        stats.dropped += 1
        let shouldLog = consumeNoisyBudget()
        lock.unlock()
        if shouldLog { log.warn("ingress(\(channel.rawValue)): dropped malformed frame (\(reason))") }
    }

    /// Caller holds `lock`. Keeps a misbehaving sender from flooding the log.
    private func consumeNoisyBudget() -> Bool {
        guard noisyLogBudget > 0 else { return false }
        noisyLogBudget -= 1
        return true
    }

    /// Validates, admits and dispatches one parsed frame. `transmit` is how the
    /// transport writes a reply line back to this sender; it is only retained
    /// for blocking events. Returns the replier so the transport can mark it
    /// closed when the connection drops.
    @discardableResult
    func ingest(_ json: JSONValue, context: IngressContext,
                transmit: @escaping @Sendable (Data) -> Void) -> (outcome: IngressOutcome, replier: IngressReplier?) {
        let event: AgentEvent
        do {
            event = try AgentEvent(json: json, defaultSource: context.defaultSource, fallbackCwd: context.directory)
        } catch {
            noteMalformed(channel: context.channel, reason: "\(error)")
            return (.dropped("\(error)"), nil)
        }

        lock.lock()
        stats.received += 1
        let policy = self.policy
        let alreadyAdmitted = admitted.contains(event.key)
        lock.unlock()

        // The uid check is cheap and kernel-backed, so it runs on every frame,
        // even for sessions that were admitted earlier.
        var evidence = AdmissionEvidence(channel: context.channel, peerUID: context.peerUID,
                                         peerPID: context.peerPID, cwd: event.cwd)
        var decision: AdmissionDecision
        if alreadyAdmitted {
            var quick = policy
            quick.requireDeveloperEvidence = false
            quick.deniedBundleIDs = []
            decision = quick.evaluate(evidence)
        } else {
            evidence = collectEvidence(for: event, context: context)
            decision = policy.evaluate(evidence)
        }

        guard decision.isAdmitted else {
            var reason = "denied"
            if case .deny(let why) = decision { reason = why }
            lock.lock()
            stats.dropped += 1
            let logKey = "\(event.key)#\(context.peerUID.map(String.init) ?? "-")"
            let firstDenial = deniedLogged.insert(logKey).inserted
            lock.unlock()
            if firstDenial {
                log.warn("ingress: session \(event.key) not admitted, events dropped: \(reason)")
            }
            return (.dropped(reason), nil)
        }

        var replier: IngressReplier?
        lock.lock()
        admitted.insert(event.key)
        stats.admitted += 1
        ring.append(event)
        if event.isBlocking {
            replier = IngressReplier(id: nextReplierID, transmit: transmit)
            nextReplierID += 1
        }
        let handler = self.handler
        lock.unlock()

        if event.name == HookEvent.sessionEnd { forget(session: event.key) }
        handler?(IngressDelivery(event: event, evidence: evidence, replier: replier))
        return (.accepted(blocking: event.isBlocking), replier)
    }

    private func collectEvidence(for event: AgentEvent, context: IngressContext) -> AdmissionEvidence {
        var ancestors: [ProcessNode] = []
        var selfReported = false
        if let pid = context.peerPID {
            ancestors = ProcessInspector.ancestors(of: pid)
        } else if let pid = event.terminal.pid, pid > 1 {
            // HTTP senders are in-process plugins: they tell us their pid and
            // we read the lineage from the kernel ourselves.
            ancestors = ProcessInspector.ancestors(of: pid)
            selfReported = true
        }
        if ancestors.count < 2, !event.terminal.ancestors.isEmpty {
            // Hook processes are short-lived: by now the peer has often exited.
            // Fall back to what the bridge said about its own lineage.
            ancestors = event.terminal.ancestors.prefix(16).map {
                ProcessNode(pid: 0, path: $0, bundleID: BundleIDCache.shared.bundleID(forExecutable: $0))
            }
            selfReported = true
        }
        return AdmissionEvidence(channel: context.channel, peerUID: context.peerUID, peerPID: context.peerPID,
                                 cwd: event.cwd, ancestors: ancestors, ancestorsAreSelfReported: selfReported)
    }
}

import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// The `initialize` values the engine depends on, in memory only. Its descriptions print none of them.
struct NottiInAppConfig: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let appId: String
    let clientKey: String
    let baseUrl: String

    var description: String { "NottiInAppConfig(<redacted>)" }
    var debugDescription: String { description }
}

/// The two In-App routes (the API client in production, a fake in tests).
protocol NottiInAppTransport: NottiInAppEventReporting {
    func eligible(deviceId: String, token: String, completion: @escaping (NottiInAppEligibleResult) -> Void)
}

extension NottiInAppApiClient: NottiInAppTransport {}

/// The routes that log the `403` inactive warning, at most once per session each (IAM-04, IAM-31).
enum NottiInAppRoute: Hashable {
    case eligible
    case events
}

/// Fetch progress of the current session; at most one `done` per session (RN `InAppFetchState`).
enum NottiInAppFetchState: Equatable {
    case idle
    case inFlight
    case done
    case gaveUp(transient: Bool)
}

enum NottiInAppDisplayState: Equatable {
    case preparing
    case visible
    case closed
}

/// The one message that is pending or visible. `id` is local (a UUID, not the message id) and names the
/// presenter's callbacks for this display. `state` is read and written on the engine queue only.
final class NottiInAppDisplay {
    let id: String
    let message: NottiInAppMessage
    var state: NottiInAppDisplayState = .preparing

    init(id: String, message: NottiInAppMessage) {
        self.id = id
        self.message = message
    }
}

/// Shows and removes the overlay; every call comes from the main thread. `close` removes a display after
/// its terminal event; `teardown` removes one silently (session ended before it was visible, config
/// change). Both must be idempotent.
protocol NottiInAppPresenting: AnyObject {
    func present(_ display: NottiInAppDisplay)
    func close(displayId: String)
    func teardown(_ display: NottiInAppDisplay)
}

/// Retry and pause values of both routes (RN `InAppTiming`, 0.8.0).
enum NottiInAppTiming {
    /// Requests per transient failure streak, 2/4/8/16 s apart.
    static let maxAttempts = 5
    static let baseBackoffSeconds: TimeInterval = 2
    /// `Retry-After` used when it is absent or not integer seconds.
    static let defaultRetryAfterSeconds = 60
    /// `eligible` 429: a `Retry-After` above this gives up for the session (IAM-04).
    static let eligibleGiveUpRetryAfterSeconds = 60
    static let eligibleMaxRateLimitWaits = 3
    /// Events 429: clamp of the stored pause (IAM-31).
    static let eventsRetryAfterRange = 1...300

    static func backoffSeconds(_ failures: Int) -> TimeInterval {
        baseBackoffSeconds * TimeInterval(1 << min(max(failures - 1, 0), 30))
    }
}

/// Production `NottiInAppScheduling`: one serial queue, delays by wall-clock deadline (never a sleeping
/// thread, and no uptime clock: D8).
final class NottiInAppQueueScheduler: NottiInAppScheduling {
    static let queueLabel = "app.notti.sdk.inapp"

    private let queue = DispatchQueue(label: NottiInAppQueueScheduler.queueLabel, qos: .utility)

    func execute(_ task: @escaping () -> Void) {
        queue.async(execute: task)
    }

    func schedule(after seconds: TimeInterval, _ task: @escaping () -> Void) {
        queue.asyncAfter(wallDeadline: .now() + max(seconds, 0), execute: task)
    }
}

/// Process-wide In-App engine (design D1): every input hops onto `scheduler` (the serial queue
/// `app.notti.sdk.inapp` in production) and all state lives there. Port of the session, fetch and flush
/// parts of RN `NottiInAppCoordinator.swift` and `NottiInAppSession.swift` (0.8.0); RN confines the same
/// state to the main thread. The presenter is called through `mainDispatcher`. Network and queue I/O
/// never run on the main thread or on `NottiCore.workQueue`. Never logs ids, names, URLs, tokens or
/// bodies (IAM-43).
final class NottiInAppEngine {

    static let inactiveWarning = "Notti: in-app messages are inactive on this device until the next registration (HTTP 403)"

    /// Builds the production client; nil when the base URL is not usable.
    static func clientFactory(session: URLSession = .shared) -> (NottiInAppConfig) -> NottiInAppTransport? {
        { config in
            NottiInAppApiClient(session: session, baseUrl: config.baseUrl, appId: config.appId, clientKey: config.clientKey)
        }
    }

    private let store: NottiInAppEventStore
    private let identity: () -> NottiInAppIdentity?
    private let presenter: NottiInAppPresenting
    private let scheduler: NottiInAppScheduling
    private let now: () -> Date
    private let uuid: () -> String
    private let mainDispatcher: NottiMainDispatcher
    private let clientFactory: (NottiInAppConfig) -> NottiInAppTransport?

    // MARK: State (engine queue only)

    private(set) var config: NottiInAppConfig?
    private var client: NottiInAppTransport?
    private var flusher: NottiInAppEventFlusher?
    /// Bumped by a config change: results of older flush work only release their flags.
    private var configEpoch = 0
    /// Bumped at session open, session end and config change: an older `eligible` result is dropped.
    private(set) var fetchGeneration = 0
    private(set) var sessionOpen = false
    private(set) var hasOpenedSession = false
    private(set) var appForeground = true
    /// A core session report arrived in background: the next foreground opens that session (D14).
    private(set) var sessionReportDeferred = false
    /// Set by `configure` until the first session of the process opens (D12).
    private(set) var awaitingFirstSession = false
    /// This process registered the device: only then are the id and token fresh enough (D13).
    private(set) var registeredInProcess = false
    private(set) var keyRejected = false
    private var inactiveWarned = Set<NottiInAppRoute>()
    private(set) var fetchState = NottiInAppFetchState.idle
    /// `429` deadlines; reset only by a config change (D13).
    private(set) var eligiblePauseUntil: Date?
    private(set) var eventsPauseUntil: Date?
    private(set) var flushRunning = false
    private(set) var flushAgain = false
    /// A flush pass is sending; queued passes wait for it (see `enqueuePass`).
    private var passRunning = false
    private var passQueue: [(@escaping () -> Void) -> Void] = []
    private(set) var selector = NottiInAppSelector()
    private(set) var display: NottiInAppDisplay?

    init(
        store: NottiInAppEventStore,
        identity: @escaping () -> NottiInAppIdentity?,
        presenter: NottiInAppPresenting,
        scheduler: NottiInAppScheduling = NottiInAppQueueScheduler(),
        now: @escaping () -> Date = Date.init,
        uuid: @escaping () -> String = { UUID().uuidString.lowercased() },
        mainDispatcher: @escaping NottiMainDispatcher = { DispatchQueue.main.async(execute: $0) },
        clientFactory: @escaping (NottiInAppConfig) -> NottiInAppTransport? = NottiInAppEngine.clientFactory()
    ) {
        self.store = store
        self.identity = identity
        self.presenter = presenter
        self.scheduler = scheduler
        self.now = now
        self.uuid = uuid
        self.mainDispatcher = mainDispatcher
        self.clientFactory = clientFactory
    }

    // MARK: - Inputs (any thread)

    /// From `NottiRuntime.start`, before `core.initialize`, so a same-thread `trackEvent` lands after it (D12).
    func configure(appId: String, clientKey: String, baseUrl: String) {
        let newConfig = NottiInAppConfig(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        scheduler.execute { self.handleConfigure(newConfig) }
    }

    /// Core hook: the process session gate opened. Idempotent; deferred while in background (D14).
    func sessionStarted() {
        scheduler.execute {
            guard !self.sessionOpen else { return }
            guard self.appForeground else {
                self.sessionReportDeferred = true
                return
            }
            self.openSession()
        }
    }

    /// Core hook: the device registration succeeded.
    func deviceRegistered() {
        scheduler.execute {
            self.registeredInProcess = true
            self.requestFlush()
            self.maybeFetch(allowTransientRetry: false)
        }
    }

    /// Runtime observer (`willEnterForeground`): opens every session after the first one without waiting
    /// for the core (IAM-51).
    func appForegrounded() {
        scheduler.execute {
            self.appForeground = true
            let reported = self.hasOpenedSession || self.sessionReportDeferred
            if reported, self.config != nil, !self.sessionOpen {
                self.openSession()
            }
            self.requestFlush()
        }
    }

    /// Runtime observer (`didEnterBackground`), called before `appBackgrounded`.
    func sessionEnded() {
        scheduler.execute { self.endSession() }
    }

    func appBackgrounded() {
        scheduler.execute { self.appForeground = false }
    }

    /// Network regained: flush, and resume a fetch that gave up on a transient failure (IAM-52).
    func networkAvailable() {
        scheduler.execute {
            self.requestFlush()
            self.maybeFetch(allowTransientRetry: true)
        }
    }

    /// Never sends, persists or logs `name` (IAM-08, IAM-11). Blank names are a silent no-op.
    func trackEvent(_ name: String) {
        scheduler.execute { self.handleTrackEvent(name) }
    }

    // MARK: - Session

    private func handleConfigure(_ newConfig: NottiInAppConfig) {
        let previous = config
        guard previous != newConfig else { return }
        config = newConfig
        awaitingFirstSession = !hasOpenedSession
        client = clientFactory(newConfig)
        flusher = client.map { NottiInAppEventFlusher(store: store, reporter: $0, scheduler: scheduler) }
        if previous != nil { resetForNewConfig(appId: newConfig.appId) }
    }

    /// D13, IAM-06: forget the old app's session state, drop in-flight results, tear a display down
    /// without any event, and purge the queue records of other apps.
    private func resetForNewConfig(appId: String) {
        configEpoch += 1
        fetchGeneration += 1
        selector.reset()
        fetchState = .idle
        eligiblePauseUntil = nil
        eventsPauseUntil = nil
        keyRejected = false
        inactiveWarned.removeAll()
        registeredInProcess = false
        if let current = display {
            display = nil
            current.state = .closed
            mainDispatcher { self.presenter.teardown(current) }
        }
        store.purgeOtherApps(appId)
    }

    private func openSession() {
        sessionReportDeferred = false
        fetchGeneration += 1
        sessionOpen = true
        hasOpenedSession = true
        awaitingFirstSession = false
        keyRejected = false
        inactiveWarned.removeAll()
        fetchState = .idle
        selector.startSession(visibleId: display?.message.id)
        maybeFetch(allowTransientRetry: false)
    }

    /// A visible display stays (OQ-9); one that never became visible is dropped with no event.
    private func endSession() {
        fetchGeneration += 1
        selector.endSession(wasOpen: sessionOpen)
        sessionOpen = false
        fetchState = .idle
        if let current = display, current.state != .visible {
            display = nil
            current.state = .closed
            mainDispatcher { self.presenter.teardown(current) }
        }
    }

    private func handleTrackEvent(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, config != nil else { return }
        guard sessionOpen || awaitingFirstSession else { return }
        if awaitingFirstSession || fetchState != .done {
            selector.noteEarly(name)
            return
        }
        present(selector.track(name, isVisible: display != nil))
    }

    private func present(_ message: NottiInAppMessage?) {
        guard let message = message else { return }
        let created = NottiInAppDisplay(id: uuid(), message: message)
        display = created
        mainDispatcher { self.presenter.present(created) }
    }

    private func warnInactive(_ route: NottiInAppRoute) {
        if inactiveWarned.insert(route).inserted {
            NottiLogger.log(.warn, Self.inactiveWarning, category: "inapp")
        }
    }

    // MARK: - Fetch (IAM-01, IAM-03, IAM-04, IAM-52)

    /// Port of RN `maybeFetch` (`NottiInAppCoordinator.swift:365-400`).
    private func maybeFetch(allowTransientRetry: Bool) {
        guard let config = config, let client = client, let flusher = flusher else { return }
        guard sessionOpen, !keyRejected, registeredInProcess else { return }
        if !allowTransientRetry && fetchState != .idle { return }
        if let pausedUntil = eligiblePauseUntil {
            let remaining = pausedUntil.timeIntervalSince(now())
            if remaining > 0 {
                // The 429 pause outlives the session that got it: fetch once it elapses.
                scheduleFetchAfterPause(remaining)
                return
            }
        }
        guard let identity = identity(), let generation = tryStartFetch() else { return }
        let epoch = configEpoch
        // An events 429 pause is shared by every trigger, this one included (IAM-03).
        let preFlush = eventsPauseUntil.map { now() >= $0 } ?? true
        guard preFlush else {
            sendEligible(client, identity: identity, generation: generation, transientFailures: 0, waits: 0)
            return
        }
        // A single pass may run while another pass holds the flag; it then leaves the flag alone.
        let ownsFlushFlag = !flushRunning
        if ownsFlushFlag { flushRunning = true }
        enqueuePass { finished in
            flusher.runPass(appId: config.appId, identity: identity, singleAttempt: true, headFailures: 0) { outcome in
                self.handleFlushOutcome(epoch: epoch, outcome, ownsFlag: ownsFlushFlag)
                finished()
                guard generation == self.fetchGeneration, self.sessionOpen else { return }
                if outcome == .unauthorized {
                    // A rejected key ends every In-App request of the session.
                    self.fetchGaveUp(generation: generation, transient: false)
                    return
                }
                self.sendEligible(client, identity: identity, generation: generation, transientFailures: 0, waits: 0)
            }
        }
    }

    private func tryStartFetch() -> Int? {
        switch fetchState {
        case .idle, .gaveUp(transient: true):
            fetchState = .inFlight
            return fetchGeneration
        default:
            return nil
        }
    }

    private func fetchGaveUp(generation: Int, transient: Bool) {
        guard generation == fetchGeneration, sessionOpen else { return }
        fetchState = .gaveUp(transient: transient)
    }

    private func scheduleFetchAfterPause(_ seconds: TimeInterval) {
        let generation = fetchGeneration
        scheduler.schedule(after: seconds) {
            if generation == self.fetchGeneration { self.maybeFetch(allowTransientRetry: false) }
        }
    }

    private func sendEligible(
        _ client: NottiInAppTransport,
        identity: NottiInAppIdentity,
        generation: Int,
        transientFailures: Int,
        waits: Int
    ) {
        client.eligible(deviceId: identity.deviceId, token: identity.token) { result in
            self.scheduler.execute {
                self.handleEligibleResult(result, generation: generation, transientFailures: transientFailures, waits: waits)
            }
        }
    }

    /// IAM-04. A result of an ended session, a newer session or an older config is dropped (IAM-06).
    private func handleEligibleResult(
        _ result: NottiInAppEligibleResult,
        generation: Int,
        transientFailures: Int,
        waits: Int
    ) {
        guard generation == fetchGeneration, sessionOpen else { return }
        switch result {
        case .messages(let messages):
            fetchState = .done
            present(selector.load(messages, visibleId: display?.message.id))
        case .rateLimited(let seconds):
            NottiLogger.log(.warn, "Notti.inapp: eligible failed (HTTP 429)", category: "inapp")
            let tooLong = seconds.map { $0 > NottiInAppTiming.eligibleGiveUpRetryAfterSeconds } ?? false
            if tooLong || waits >= NottiInAppTiming.eligibleMaxRateLimitWaits {
                fetchGaveUp(generation: generation, transient: false)
                return
            }
            let delay = TimeInterval(max(1, seconds ?? NottiInAppTiming.defaultRetryAfterSeconds))
            eligiblePauseUntil = now().addingTimeInterval(delay)
            scheduleEligibleRetry(generation: generation, after: delay, transientFailures: transientFailures, waits: waits + 1)
        case .transient:
            NottiLogger.log(.info, "Notti.inapp: eligible failed (network or server error)", category: "inapp")
            let failures = transientFailures + 1
            if failures >= NottiInAppTiming.maxAttempts {
                fetchGaveUp(generation: generation, transient: true)
            } else {
                scheduleEligibleRetry(
                    generation: generation,
                    after: NottiInAppTiming.backoffSeconds(failures),
                    transientFailures: failures,
                    waits: waits
                )
            }
        case .unauthorized:
            NottiLogger.log(.error, "Notti.inapp: eligible failed (HTTP 401)", category: "inapp")
            keyRejected = true
            fetchGaveUp(generation: generation, transient: false)
        case .forbidden:
            warnInactive(.eligible)
            fetchGaveUp(generation: generation, transient: false)
        case .terminal(let status):
            NottiLogger.log(.warn, "Notti.inapp: eligible failed (HTTP \(status))", category: "inapp")
            fetchGaveUp(generation: generation, transient: false)
        }
    }

    private func scheduleEligibleRetry(generation: Int, after seconds: TimeInterval, transientFailures: Int, waits: Int) {
        scheduler.schedule(after: seconds) {
            guard generation == self.fetchGeneration, self.sessionOpen, !self.keyRejected else { return }
            guard self.fetchState == .inFlight, let client = self.client else { return }
            guard let identity = self.identity() else {
                self.fetchGaveUp(generation: generation, transient: true)
                return
            }
            self.sendEligible(client, identity: identity, generation: generation, transientFailures: transientFailures, waits: waits)
        }
    }

    // MARK: - Event flush (IAM-31, IAM-33)

    /// Single-flight and coalesced: a request during a run asks for one more pass.
    private func requestFlush() {
        guard config != nil, client != nil, !keyRejected else { return }
        if let pausedUntil = eventsPauseUntil, now() < pausedUntil { return }
        if flushRunning {
            flushAgain = true
            return
        }
        startFlush(headFailures: 0)
    }

    private func startFlush(headFailures: Int) {
        guard let config = config, let flusher = flusher, let identity = identity() else {
            flushRunning = false
            return
        }
        flushRunning = true
        let epoch = configEpoch
        enqueuePass { finished in
            flusher.runPass(appId: config.appId, identity: identity, singleAttempt: false, headFailures: headFailures) { outcome in
                self.handleFlushOutcome(epoch: epoch, outcome)
                finished()
            }
        }
    }

    /// RN runs every flush pass on its serial, blocking executor, so two passes never send at the same time
    /// (a pre-fetch pass waits for a running one and then finds its records gone). The flusher here is
    /// asynchronous (T6), so passes go through this lane: one sends at a time, the rest wait in order. A
    /// backoff wait is not a pass, so the lane is free during it, as in RN.
    private func enqueuePass(_ pass: @escaping (_ finished: @escaping () -> Void) -> Void) {
        passQueue.append(pass)
        runNextPass()
    }

    private func runNextPass() {
        guard !passRunning, !passQueue.isEmpty else { return }
        passRunning = true
        let pass = passQueue.removeFirst()
        pass {
            self.passRunning = false
            self.runNextPass()
        }
    }

    /// `ownsFlag` is false for a pre-fetch pass that ran while another pass held the flag.
    private func handleFlushOutcome(epoch: Int, _ outcome: NottiInAppFlushOutcome, ownsFlag: Bool = true) {
        let current = epoch == configEpoch
        if !ownsFlag {
            if current { reportFlushOutcome(outcome) }
            return
        }
        if case .backoff(let failures) = outcome, current {
            // Still running: retry the same head (same `eventId`) after the backoff.
            scheduler.schedule(after: NottiInAppTiming.backoffSeconds(failures)) {
                if epoch == self.configEpoch && !self.keyRejected {
                    self.startFlush(headFailures: failures)
                } else {
                    self.finishFlush()
                }
            }
            return
        }
        if current { reportFlushOutcome(outcome) }
        finishFlush()
    }

    private func reportFlushOutcome(_ outcome: NottiInAppFlushOutcome) {
        switch outcome {
        case .paused(let retryAfter):
            let range = NottiInAppTiming.eventsRetryAfterRange
            let seconds = min(max(retryAfter ?? NottiInAppTiming.defaultRetryAfterSeconds, range.lowerBound), range.upperBound)
            NottiLogger.log(.warn, "Notti.inapp: events failed (HTTP 429)", category: "inapp")
            eventsPauseUntil = now().addingTimeInterval(TimeInterval(seconds))
            scheduler.schedule(after: TimeInterval(seconds)) { self.requestFlush() }
        case .unauthorized:
            NottiLogger.log(.error, "Notti.inapp: events failed (HTTP 401)", category: "inapp")
            keyRejected = true
        case .forbidden:
            warnInactive(.events)
        case .failed:
            NottiLogger.log(.info, "Notti.inapp: events failed (network or server error)", category: "inapp")
        case .done, .backoff:
            break
        }
    }

    private func finishFlush() {
        flushRunning = false
        if flushAgain {
            flushAgain = false
            requestFlush()
        }
    }
}

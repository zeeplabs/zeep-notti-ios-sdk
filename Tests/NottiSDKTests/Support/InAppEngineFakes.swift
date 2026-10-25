import Foundation
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// Runs engine work on the test thread: `execute` queues, `drain()` runs the queue, and scheduled tasks run
/// when virtual time reaches them (`advance`). Virtual time is whole milliseconds, so deadlines never drift;
/// the engine's clock reads `now`. No real sleeps.
final class InAppFakeScheduler: NottiInAppScheduling {
    private let base: Date
    private(set) var elapsedMs: Int64 = 0
    private var ready: [() -> Void] = []
    private struct Timer {
        let atMs: Int64
        let seq: Int
        let task: () -> Void
    }

    private var timers: [Timer] = []
    private var seq = 0
    private(set) var delays: [TimeInterval] = []
    /// Guards `ready`: core hooks enqueue from the core's work queue (wiring tests).
    private let readyLock = NSLock()

    init(base: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.base = base
    }

    var now: Date { base.addingTimeInterval(TimeInterval(elapsedMs) / 1000) }

    func execute(_ task: @escaping () -> Void) {
        readyLock.withLock { ready.append(task) }
    }

    func schedule(after seconds: TimeInterval, _ task: @escaping () -> Void) {
        delays.append(seconds)
        seq += 1
        timers.append(Timer(atMs: elapsedMs + Self.ms(seconds), seq: seq, task: task))
    }

    func drain() {
        while let next = readyLock.withLock({ ready.isEmpty ? nil : ready.removeFirst() }) { next() }
    }

    /// Runs the queue, then every timer due within `seconds`, in deadline order.
    func advance(_ seconds: TimeInterval) {
        let target = elapsedMs + Self.ms(seconds)
        drain()
        while let next = timers.filter({ $0.atMs <= target }).min(by: { ($0.atMs, $0.seq) < ($1.atMs, $1.seq) }) {
            timers.removeAll { $0.seq == next.seq }
            elapsedMs = next.atMs
            next.task()
            drain()
        }
        elapsedMs = target
    }

    var pendingTimers: Int { timers.count }

    private static func ms(_ seconds: TimeInterval) -> Int64 {
        Int64((max(seconds, 0) * 1000).rounded())
    }
}

/// Scripted HTTP for the two In-App routes. Replies are raw (status, body, `Retry-After`) and go through the
/// real status tables of `NottiInAppApiClient`, in FIFO order across both routes; an empty script answers
/// like a transport error. With `holding` the completions wait for `release`. Thread-safe.
final class InAppFakeNetwork {

    struct Reply {
        let status: Int
        let body: String
        let retryAfter: String?

        static func status(_ code: Int, retryAfter: String? = nil, body: String = "{}") -> Reply {
            Reply(status: code, body: body, retryAfter: retryAfter)
        }

        static let transport = Reply(status: -1, body: "", retryAfter: nil)

        static func messages(_ entries: String...) -> Reply {
            Reply(status: 200, body: #"{"messages":[\#(entries.joined(separator: ","))]}"#, retryAfter: nil)
        }
    }

    struct Request {
        /// `eligible`, or `events:<messageId>`.
        let route: String
        let appId: String
        let eventId: String?
        let deviceId: String
        let token: String
        let onMainThread: Bool
        let queueLabel: String
    }

    private let lock = NSLock()
    private var script: [Reply] = []
    private var recorded: [Request] = []
    private var waiting: [(Reply) -> Void] = []
    var holding: Bool {
        get { lock.withLock { isHolding } }
        set { lock.withLock { isHolding = newValue } }
    }
    private var isHolding = false

    func enqueue(_ replies: Reply...) {
        lock.withLock { script.append(contentsOf: replies) }
    }

    var requests: [Request] { lock.withLock { recorded } }
    var routes: [String] { requests.map(\.route) }
    var heldCount: Int { lock.withLock { waiting.count } }

    /// Answers the oldest held request with `reply`.
    func release(_ reply: Reply) {
        let next: ((Reply) -> Void)? = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?(reply)
    }

    func transport(appId: String) -> NottiInAppTransport {
        Transport(network: self, appId: appId)
    }

    fileprivate func handle(_ request: Request, answer: @escaping (Reply) -> Void) {
        let reply: Reply? = lock.withLock {
            recorded.append(request)
            if isHolding {
                waiting.append(answer)
                return nil
            }
            return script.isEmpty ? .transport : script.removeFirst()
        }
        if let reply = reply { answer(reply) }
    }

    private final class Transport: NottiInAppTransport {
        let network: InAppFakeNetwork
        let appId: String

        init(network: InAppFakeNetwork, appId: String) {
            self.network = network
            self.appId = appId
        }

        func eligible(deviceId: String, token: String, completion: @escaping (NottiInAppEligibleResult) -> Void) {
            network.handle(request(route: "eligible", eventId: nil, deviceId: deviceId, token: token)) { reply in
                completion(NottiInAppApiClient.eligibleResult(
                    status: reply.status, body: Data(reply.body.utf8), retryAfter: reply.retryAfter
                ))
            }
        }

        func report(
            _ event: NottiInAppEventRecord,
            deviceId: String,
            token: String,
            completion: @escaping (NottiInAppEventResult) -> Void
        ) {
            let route = "events:\(event.messageId)"
            network.handle(request(route: route, eventId: event.eventId, deviceId: deviceId, token: token)) { reply in
                completion(NottiInAppApiClient.eventResult(status: reply.status, retryAfter: reply.retryAfter))
            }
        }

        private func request(route: String, eventId: String?, deviceId: String, token: String) -> Request {
            Request(
                route: route,
                appId: appId,
                eventId: eventId,
                deviceId: deviceId,
                token: token,
                onMainThread: Thread.isMainThread,
                queueLabel: String(cString: __dispatch_queue_get_label(nil))
            )
        }
    }
}

/// Records what the engine asks the presenter to do, and on which thread. Thread-safe.
final class InAppFakePresenter: NottiInAppPresenting {
    private let lock = NSLock()
    private var shown: [NottiInAppDisplay] = []
    private var removed: [NottiInAppDisplay] = []
    private var closedIds: [String] = []
    private var offMain = 0
    var onPresent: ((NottiInAppDisplay) -> Void)?

    var presented: [NottiInAppDisplay] { lock.withLock { shown } }
    var presentedIds: [String] { presented.map(\.message.id) }
    var tornDown: [NottiInAppDisplay] { lock.withLock { removed } }
    var closed: [String] { lock.withLock { closedIds } }
    var callsOffMainThread: Int { lock.withLock { offMain } }

    func present(_ display: NottiInAppDisplay) {
        lock.withLock {
            shown.append(display)
            if !Thread.isMainThread { offMain += 1 }
        }
        onPresent?(display)
    }

    var onClose: ((String) -> Void)?

    func close(displayId: String) {
        lock.withLock { closedIds.append(displayId) }
        onClose?(displayId)
    }

    func teardown(_ display: NottiInAppDisplay) {
        lock.withLock { removed.append(display) }
    }
}

/// Captures `NottiLogger` lines with their level.
final class InAppLevelLogSink {
    private let lock = NSLock()
    private var storage: [(NottiLogLevel, String)] = []

    func append(_ level: NottiLogLevel, _ message: String) {
        lock.withLock { storage.append((level, message)) }
    }

    var messages: [String] { lock.withLock { storage.map(\.1) } }
    var warnings: [String] { lock.withLock { storage.filter { $0.0 == .warn }.map(\.1) } }
}

/// Synthetic `eligible` entries.
enum InAppFixtureJSON {
    static func sessionStart(_ id: String, extra: String = "") -> String {
        #"{"id":"\#(id)","title":"fixture","trigger":{"type":"session_start"}\#(extra)}"#
    }

    static func event(_ id: String, _ name: String) -> String {
        #"{"id":"\#(id)","title":"fixture","trigger":{"type":"event","name":"\#(name)"}}"#
    }
}

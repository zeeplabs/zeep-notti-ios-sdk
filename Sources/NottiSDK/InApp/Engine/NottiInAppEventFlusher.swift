import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// The engine's work port: its serial queue in production, a fake in tests. `execute` runs a task on the
/// queue; `schedule(after:)` runs one later without blocking anything (RN `InAppExecutor`, 0.8.0).
protocol NottiInAppScheduling: AnyObject {
    func execute(_ task: @escaping () -> Void)
    func schedule(after seconds: TimeInterval, _ task: @escaping () -> Void)
}

/// Sends one In-App event (the API client in production).
protocol NottiInAppEventReporting: AnyObject {
    func report(
        _ event: NottiInAppEventRecord,
        deviceId: String,
        token: String,
        completion: @escaping (NottiInAppEventResult) -> Void
    )
}

extension NottiInAppApiClient: NottiInAppEventReporting {}

/// Device identity read at send time (RN `InAppIdentity`, 0.8.0). Its descriptions never print either value.
struct NottiInAppIdentity: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let deviceId: String
    let token: String

    var description: String { "NottiInAppIdentity(<redacted>)" }
    var debugDescription: String { description }
}

/// How one flush pass ended (RN `InAppFlushOutcome`, 0.8.0). `backoff` means the head failed transiently
/// `failures` times in a row and should be retried after the engine's backoff; `failed` means give up.
enum NottiInAppFlushOutcome: Equatable {
    case done
    case paused(retryAfterSeconds: Int?)
    case unauthorized
    case forbidden
    case failed
    case backoff(failures: Int)
}

/// One flush pass over the In-App queue, a port of RN `runFlushPass` (`NottiInAppCoordinator.swift:568-603`,
/// 0.8.0): purge other apps, expire, then the current app's records oldest first, one request at a time,
/// strict FIFO (a failing head blocks the rest, IAM-32). The status table is IAM-31. The engine owns the
/// outcome: backoff delays, the `429` pause, `keyRejected`, the `403` warning and coalescing.
final class NottiInAppEventFlusher {

    /// Attempts on one head in full mode before the pass gives up (`failed`).
    static let maxAttempts = 5

    private let store: NottiInAppEventStore
    private let reporter: NottiInAppEventReporting
    private let scheduler: NottiInAppScheduling

    init(store: NottiInAppEventStore, reporter: NottiInAppEventReporting, scheduler: NottiInAppScheduling) {
        self.store = store
        self.reporter = reporter
        self.scheduler = scheduler
    }

    /// Call on the engine queue. Every response is handled back on it through `scheduler.execute`, and
    /// `completion` runs there. `singleAttempt` stops at the first transient failure; otherwise a transient
    /// failure returns `backoff` until `maxAttempts`, counting from `headFailures`.
    func runPass(
        appId: String,
        identity: NottiInAppIdentity,
        singleAttempt: Bool,
        headFailures: Int,
        completion: @escaping (NottiInAppFlushOutcome) -> Void
    ) {
        store.purgeOtherApps(appId)
        if !store.expire().isEmpty {
            NottiLogger.log(.info, "Notti.inapp: expired events dropped", category: "inapp")
        }
        sendHead(appId: appId, identity: identity, singleAttempt: singleAttempt, failures: headFailures, completion: completion)
    }

    private func sendHead(
        appId: String,
        identity: NottiInAppIdentity,
        singleAttempt: Bool,
        failures: Int,
        completion: @escaping (NottiInAppFlushOutcome) -> Void
    ) {
        guard let head = store.all(forApp: appId).first else {
            completion(.done)
            return
        }
        reporter.report(head, deviceId: identity.deviceId, token: identity.token) { [self] result in
            scheduler.execute { [self] in
                let next: () -> Void = {
                    self.sendHead(appId: appId, identity: identity, singleAttempt: singleAttempt, failures: 0, completion: completion)
                }
                switch result {
                case .recorded:
                    store.remove(id: head.id)
                    next()
                case .drop:
                    NottiLogger.log(.warn, "Notti.inapp: event rejected by the server, dropped", category: "inapp")
                    store.remove(id: head.id)
                    next()
                case .rateLimited(let seconds):
                    completion(.paused(retryAfterSeconds: seconds))
                case .unauthorized:
                    completion(.unauthorized)
                case .forbidden:
                    completion(.forbidden)
                case .transient:
                    let total = failures + 1
                    if singleAttempt || total >= Self.maxAttempts {
                        completion(.failed)
                    } else {
                        completion(.backoff(failures: total))
                    }
                }
            }
        }
    }
}

// Ported from react-native-notti 52e4b55 ios/NottiNetworkObserver.swift (AD-002).
// Changes: `public` -> internal; `static let shared` (and its `NottiImpl.activeCore` callback) removed: the owner injects `onNetworkAvailable` (CORE-03).

import Foundation
import Network

/// The connectivity signal the observer needs, abstracted away from a real
/// `NWPathMonitor` so tests can drive status transitions without fabricating an
/// `NWPath` (which has no public initializer). The production adapter is
/// `NottiPathMonitorAdapter`; a test can conform with a fake that invokes
/// `pathUpdateHandler` directly.
protocol NottiPathMonitoring: AnyObject {
    /// Delivered on the queue passed to `start(queue:)` for every path update.
    var pathUpdateHandler: ((NWPath.Status) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

/// Default `NottiPathMonitoring` backed by a real `NWPathMonitor`, translating
/// each path update into the status the observer consumes.
final class NottiPathMonitorAdapter: NottiPathMonitoring {

    private let monitor = NWPathMonitor()

    init() {}

    var pathUpdateHandler: ((NWPath.Status) -> Void)? {
        didSet {
            monitor.pathUpdateHandler = { [weak self] path in
                self?.pathUpdateHandler?(path.status)
            }
        }
    }

    func start(queue: DispatchQueue) {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

/// Watches for the device regaining network connectivity and triggers an
/// offline-event flush the moment a usable path appears (design.md offline
/// event queue). Mirrors Android's connectivity observer: events enqueued
/// while offline (`NottiEventStore`) are drained as soon as the network is
/// back, instead of waiting for the next launch, foreground, or registration.
///
/// Only a *transition* into `.satisfied` fires — repeated updates while
/// already connected do not (that would flush on every interface change).
/// `NWPathMonitor` delivers an initial path right after `start`, so a device
/// that is already online fires once up front.
final class NottiNetworkObserver {

    private let monitor: NottiPathMonitoring
    private let onNetworkAvailable: () -> Void
    private let queue = DispatchQueue(label: "app.notti.sdk.network", qos: .utility)

    private let lock = NSLock()
    private var didStart = false

    /// Read/written only from `handlePathUpdate`, which runs on `queue` (serial),
    /// so no lock is needed for it.
    private var lastStatus: NWPath.Status?

    init(
        monitor: NottiPathMonitoring = NottiPathMonitorAdapter(),
        onNetworkAvailable: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.onNetworkAvailable = onNetworkAvailable
    }

    /// Starts monitoring on the observer's dedicated serial queue. Idempotent: a
    /// second call is a no-op, so the "once per process" contract holds even if
    /// the delegate singleton is initialized again.
    func start() {
        lock.lock()
        guard !didStart else {
            lock.unlock()
            return
        }
        didStart = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        lock.unlock()
        monitor.start(queue: queue)
    }

    /// Stops the underlying monitor. Not required for the shared observer
    /// (process-lifetime); provided for symmetry and tests.
    func cancel() {
        lock.lock()
        guard didStart else {
            lock.unlock()
            return
        }
        didStart = false
        lock.unlock()
        monitor.cancel()
    }

    private func handlePathUpdate(_ status: NWPath.Status) {
        if status == .satisfied && lastStatus != .satisfied {
            onNetworkAvailable()
        }
        lastStatus = status
    }
}

import Foundation

/// Hops a block to the main thread. Production uses `DispatchQueue.main.async`;
/// tests inject a recording executor (public-api API-12).
typealias NottiMainDispatcher = (@escaping () -> Void) -> Void

/// Handle returned by every `add...Listener` call.
///
/// A listener stays registered until `remove()` is called: there is no
/// auto-removal on `deinit`, so a host may drop the subscription and keep
/// listening (RN `EventSubscription` parity). `remove()` is idempotent, thread
/// safe, and releases the handler.
public final class NottiSubscription {
    private let lock = NSLock()
    private var onRemove: (() -> Void)?

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    /// Stops delivery to the handler this subscription was returned for.
    /// Calling it again is a no-op.
    public func remove() {
        let action: (() -> Void)? = lock.withLock {
            let current = onRemove
            onRemove = nil
            return current
        }
        action?()
    }
}

/// Multiplexes many host listeners over the core's single handler per event type.
///
/// - `attach` is called when the first listener arrives (a synchronous replay
///   inside it reaches that listener only) and `detach` when the last one leaves,
///   so the core buffers events again while nobody listens.
/// - Delivery always hops through `dispatcher` and never runs inline, so the order
///   of emission equals the order of delivery.
/// - Each event is delivered to the listeners registered when it was received, in
///   registration order. A listener removed before its turn is skipped.
final class NottiListenerHub<Payload> {
    typealias Handler = (Payload) -> Void

    private struct Entry {
        let id: UInt64
        let handler: Handler
    }

    private let attach: (_ handler: @escaping Handler) -> Void
    private let detach: () -> Void
    private let dispatcher: NottiMainDispatcher

    /// Serializes list mutation together with the `attach` / `detach` call, so a
    /// concurrent add and remove can never leave the source attached to an empty
    /// list (which would drop events instead of buffering them). No listener
    /// callback runs while it is held, so a re-entrant add or remove cannot
    /// deadlock.
    private let attachLock = NSLock()
    /// Guards `entries` and `nextId`. Never held across `attach`, `detach` or a callback.
    private let stateLock = NSLock()
    private var entries: [Entry] = []
    private var nextId: UInt64 = 0

    init(
        attach: @escaping (_ handler: @escaping Handler) -> Void,
        detach: @escaping () -> Void,
        dispatcher: @escaping NottiMainDispatcher = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.attach = attach
        self.detach = detach
        self.dispatcher = dispatcher
    }

    /// Number of registered listeners.
    var count: Int {
        stateLock.withLock { entries.count }
    }

    func add(_ handler: @escaping Handler) -> NottiSubscription {
        attachLock.lock()
        defer { attachLock.unlock() }
        let id: UInt64 = stateLock.withLock {
            nextId += 1
            entries.append(Entry(id: nextId, handler: handler))
            return nextId
        }
        // The list is updated before `attach`: the buffer replays synchronously
        // inside it, and that replay must find the first listener.
        if count == 1 {
            attach { [weak self] payload in self?.receive(payload) }
        }
        return NottiSubscription { [weak self] in self?.remove(id: id) }
    }

    /// Idempotent; called by the subscription.
    func remove(id: UInt64) {
        attachLock.lock()
        defer { attachLock.unlock() }
        let removedLast: Bool = stateLock.withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
            entries.remove(at: index)
            return entries.isEmpty
        }
        if removedLast {
            detach()
        }
    }

    /// Source side. Hops to the main dispatcher and calls the listeners that were
    /// registered at the moment of reception, in registration order.
    func receive(_ payload: Payload) {
        let recipients = stateLock.withLock { entries }
        dispatcher { [weak self] in
            for entry in recipients {
                guard let self, self.isRegistered(entry.id) else { continue }
                entry.handler(payload)
            }
        }
    }

    private func isRegistered(_ id: UInt64) -> Bool {
        stateLock.withLock { entries.contains { $0.id == id } }
    }
}

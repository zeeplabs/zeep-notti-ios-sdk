import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// Event types accepted by `POST .../in-app-messages/{id}/events` (RN `InAppEventType`, 0.8.0).
enum NottiInAppEventType {
    static let impression = "impression"
    static let click = "click"
    static let dismiss = "dismiss"
}

/// An In-App event waiting to be reported, RN `InAppPendingEvent` (0.8.0) field for field so a queue
/// written by `react-native-notti` decodes here (AD-019 decision 2). `id` is local to the queue;
/// `eventId` is the UUID v4 sent to the server (idempotency key, IAM-29). `appId` is the app the event
/// was created for. No token and no device id: both are read at send time.
struct NottiInAppEventRecord: Codable, Equatable {
    let id: String
    let eventId: String
    let appId: String
    let messageId: String
    let type: String
    let buttonId: String?
    let reason: String?
    let occurredAtMs: Int64
}

/// Persisted write-ahead queue of `NottiInAppEventRecord`, a port of RN `NottiInAppEventStore.swift`
/// (0.8.0): the whole queue as one JSON array (`Data`) under `notti_pending_inapp_events`, rewritten
/// per mutation (IAM-30). Independent of the CTR `NottiEventStore`: filling one never evicts the other.
final class NottiInAppEventStore {

    static let keyPendingEvents = "notti_pending_inapp_events"

    /// At most 3 events per display, so 100 covers weeks offline.
    static let maxPendingEvents = 100

    /// Records older than this (by `occurredAtMs`) are dropped. Exactly this old is kept.
    static let ttlMs: Int64 = 7 * 24 * 60 * 60 * 1000

    /// Process-wide: the engine queue removes flushed records while the main thread enqueues, and two
    /// store instances can be built over the same suite.
    private static let lock = NSLock()

    private let defaults: UserDefaults
    private let clock: () -> Int64
    private let uuid: () -> String

    init(
        defaults: UserDefaults,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        uuid: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.defaults = defaults
        self.clock = clock
        self.uuid = uuid
    }

    /// Appends a new record and persists it before returning. Expired records are dropped first, then
    /// the oldest above `maxPendingEvents`.
    @discardableResult
    func enqueue(
        appId: String,
        messageId: String,
        type: String,
        buttonId: String? = nil,
        reason: String? = nil
    ) -> NottiInAppEventRecord {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let now = clock()
        let record = NottiInAppEventRecord(
            id: uuid(),
            eventId: uuid(),
            appId: appId,
            messageId: messageId,
            type: type,
            buttonId: buttonId,
            reason: reason,
            occurredAtMs: now
        )
        var live = readLocked().filter { !Self.isExpired($0, now: now) }
        live.append(record)
        if live.count > Self.maxPendingEvents {
            live.removeFirst(live.count - Self.maxPendingEvents)
        }
        writeLocked(live)
        return record
    }

    /// Every queued record, in insertion order.
    func all() -> [NottiInAppEventRecord] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return readLocked()
    }

    /// Only the records created for `appId`, in insertion order.
    func all(forApp appId: String) -> [NottiInAppEventRecord] {
        all().filter { $0.appId == appId }
    }

    /// Removes the record with `id`, persisting the rest.
    func remove(id: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let current = readLocked()
        let kept = current.filter { $0.id != id }
        if kept.count != current.count { writeLocked(kept) }
    }

    /// Drops the records older than `ttlMs` at `now` (the clock when nil) and returns them.
    @discardableResult
    func expire(now: Int64? = nil) -> [NottiInAppEventRecord] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let instant = now ?? clock()
        let current = readLocked()
        let expired = current.filter { Self.isExpired($0, now: instant) }
        if !expired.isEmpty { writeLocked(current.filter { !Self.isExpired($0, now: instant) }) }
        return expired
    }

    /// Removes every record whose `appId` differs from `appId`, keeping the order of the rest.
    func purgeOtherApps(_ appId: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let current = readLocked()
        let kept = current.filter { $0.appId == appId }
        if kept.count != current.count { writeLocked(kept) }
    }

    private static func isExpired(_ record: NottiInAppEventRecord, now: Int64) -> Bool {
        now - record.occurredAtMs > ttlMs
    }

    /// Caller must hold `lock`. A stored value that is not a well-formed queue is removed so the queue
    /// self-heals to empty, with one fixed warning and no content.
    private func readLocked() -> [NottiInAppEventRecord] {
        guard defaults.object(forKey: Self.keyPendingEvents) != nil else { return [] }
        guard
            let data = defaults.data(forKey: Self.keyPendingEvents),
            let records = try? JSONDecoder().decode([NottiInAppEventRecord].self, from: data)
        else {
            defaults.removeObject(forKey: Self.keyPendingEvents)
            NottiLogger.log(.warn, "Notti.inapp: pending event queue failed to decode; the queue is dropped", category: "inapp")
            return []
        }
        return records
    }

    /// Caller must hold `lock`.
    private func writeLocked(_ records: [NottiInAppEventRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.keyPendingEvents)
        }
    }
}

// Ported from react-native-notti 52e4b55 ios/NottiEventStore.swift (AD-002).
// Changes: `public` -> internal; `.warn` log when `notti_pending_events` fails to decode (the queue is still dropped).
// Lint rules the RN code breaks are disabled for this file only (AD-007).
// swiftlint:disable unneeded_synthesized_initializer

import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// A single push-notification lifecycle event queued for later reporting to
/// the backend (design.md offline event queue). `id` is a locally generated
/// UUID used only to address the record within the queue — it is never sent
/// to the backend. `type` is one of `NottiEventType`.
struct PendingEvent: Codable {
    let id: String
    let notificationId: String
    let deliveryId: String
    let type: String
    let createdAtMs: Int64

    init(
        id: String,
        notificationId: String,
        deliveryId: String,
        type: String,
        createdAtMs: Int64
    ) {
        self.id = id
        self.notificationId = notificationId
        self.deliveryId = deliveryId
        self.type = type
        self.createdAtMs = createdAtMs
    }
}

/// Event types accepted by `POST .../notifications/{id}/events`.
///
/// - `received`: the notification arrived while the app was in the foreground.
/// - `opened`: the user tapped the notification body (the app was opened from it).
/// - `clicked`: the user tapped the notification body (sent together with
///   `opened`) or an action button (sent alone).
///
/// The backend counts a delivery as opened when it has an `opened` or a
/// `clicked` event, and as clicked only with a `clicked` event
/// (`.specs/features/opened-event-reporting/spec.md`).
enum NottiEventType {
    static let received = "received"
    static let opened = "opened"
    static let clicked = "clicked"
}

/// UserDefaults-backed disk queue of `PendingEvent` records waiting to be
/// flushed to the backend. Zero-dependency by design (usable before the rest
/// of the SDK exists): the whole queue is encoded as JSON under a single
/// `UserDefaults` key and rewritten on every mutation, so a pending event
/// survives process death and can be flushed on the next launch.
///
/// The queue is capped at 32 records, mirroring the SDK core's pending-mutation
/// cap: once it would exceed the cap, the oldest (first-inserted) record is
/// dropped.
///
/// **Threading**: guarded by an `NSLock` — detection sites fire on the main
/// thread / notification-delegate callbacks while the flush runs on the core's
/// work queue.
class NottiEventStore {

    private static let maxPendingEvents = 32
    private static let keyPendingEvents = "notti_pending_events"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Appends a new pending event and writes it immediately. Assigns the
    /// record's local `id` (`UUID().uuidString`) and a `createdAtMs` timestamp;
    /// drops the oldest record when the queue is already at capacity. Returns
    /// the stored record.
    func enqueue(notificationId: String, deliveryId: String, type: String) -> PendingEvent {
        let event = PendingEvent(
            id: UUID().uuidString,
            notificationId: notificationId,
            deliveryId: deliveryId,
            type: type,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        lock.lock()
        defer { lock.unlock() }

        var events = readLocked()
        events.append(event)
        if events.count > Self.maxPendingEvents {
            events.removeFirst()
        }
        writeLocked(events)
        return event
    }

    /// Every not-yet-removed event, in insertion order.
    func all() -> [PendingEvent] {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()
    }

    /// Removes the event with the given `id`, rewriting the queue without it.
    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }

        var events = readLocked()
        let before = events.count
        events.removeAll { $0.id == id }
        if events.count != before {
            writeLocked(events)
        }
    }

    /// Test hook: drops every persisted event (mirrors `NottiEventBuffer.reset()`).
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.keyPendingEvents)
    }

    /// Caller must already hold `lock`. Returns the stored queue, or `[]` when
    /// nothing has been persisted yet or the stored data fails to decode.
    private func readLocked() -> [PendingEvent] {
        guard let data = defaults.data(forKey: Self.keyPendingEvents) else {
            return []
        }
        guard let events = try? JSONDecoder().decode([PendingEvent].self, from: data) else {
            NottiLogger.log(.warn, "notti_pending_events failed to decode; the queue is dropped")
            return []
        }
        return events
    }

    /// Caller must already hold `lock`.
    private func writeLocked(_ events: [PendingEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.keyPendingEvents)
        }
    }
}

// swiftlint:enable unneeded_synthesized_initializer

import Foundation

/// Pure per-session selection state, a port of RN `NottiInAppSession.swift:156-242,298-315` (0.8.0).
/// It decides what to show; every side effect belongs to the engine that owns it. A returned message
/// is already counted as shown for the session. Event names are kept in memory only, never logged.
struct NottiInAppSelector {

    /// Distinct names remembered before the held messages are known; later new names are ignored (IAM-11).
    static let maxEarlyNames = 32

    /// The session's `event` messages, in server order (IAM-08).
    private(set) var held: [NottiInAppMessage] = []
    /// Ids returned in this session, plus a display still visible from the previous one (IAM-09, IAM-12).
    private(set) var shown: Set<String> = []
    private(set) var earlyNames: [String] = []
    /// True once this session's messages were loaded.
    private(set) var fetchDone = false

    /// Loads the session's messages: holds the `event` ones, returns the first `session_start` one not
    /// shown when nothing is visible (IAM-07, IAM-12), then replays the early names in call order, once,
    /// returning at most one message (IAM-11).
    mutating func load(_ messages: [NottiInAppMessage], visibleId: String?) -> NottiInAppMessage? {
        let firstLoad = !fetchDone
        fetchDone = true
        if let visibleId = visibleId { shown.insert(visibleId) }

        let renderable = messages.filter(\.renderable)
        held = renderable.filter {
            if case .event = $0.trigger { return true }
            return false
        }

        var selected: NottiInAppMessage?
        if visibleId == nil, firstLoad,
           let first = renderable.first(where: { $0.trigger == .sessionStart && !shown.contains($0.id) }) {
            selected = first
            shown.insert(first.id)
        }

        let names = earlyNames
        earlyNames.removeAll()
        for name in names where selected == nil && visibleId == nil {
            selected = matchHeld(name)
        }
        return selected
    }

    /// Before the messages are loaded the name is remembered (IAM-11); while a message is visible it is
    /// ignored and nothing is consumed (IAM-09); otherwise the oldest held, not shown message with that
    /// exact name (IAM-08).
    mutating func track(_ name: String, isVisible: Bool) -> NottiInAppMessage? {
        guard fetchDone else {
            noteEarly(name)
            return nil
        }
        guard !isVisible else { return nil }
        return matchHeld(name)
    }

    mutating func noteEarly(_ name: String) {
        guard !earlyNames.contains(name), earlyNames.count < Self.maxEarlyNames else { return }
        earlyNames.append(name)
    }

    /// Clears held and shown messages and keeps the early names. A display still visible from the
    /// previous session counts as shown in this one (IAM-12).
    mutating func startSession(visibleId: String?) {
        held.removeAll()
        shown.removeAll()
        fetchDone = false
        if let visibleId = visibleId { shown.insert(visibleId) }
    }

    /// Drops the held messages. The early names are dropped only when a session was open: names noted
    /// before the first session belong to it (RN `onSessionEnded`).
    mutating func endSession(wasOpen: Bool) {
        held.removeAll()
        fetchDone = false
        if wasOpen { earlyNames.removeAll() }
    }

    /// Config change: forget everything.
    mutating func reset() {
        self = NottiInAppSelector()
    }

    private mutating func matchHeld(_ name: String) -> NottiInAppMessage? {
        let match = held.first { message in
            guard case .event(let triggerName) = message.trigger else { return false }
            return triggerName == name && !shown.contains(message.id)
        }
        if let match = match { shown.insert(match.id) }
        return match
    }
}

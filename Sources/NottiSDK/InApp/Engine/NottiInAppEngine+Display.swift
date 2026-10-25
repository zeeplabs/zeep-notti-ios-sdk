import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

enum NottiInAppDisplayState: Equatable {
    case preparing
    case visible
    case closed
}

/// `reason` values of a `dismiss` event (IAM-28).
enum NottiInAppDismissReason {
    static let closeButton = "close_button"
    static let swipe = "swipe"
    static let outsideTap = "outside_tap"
    static let auto = "auto"
}

/// The one message that is pending or visible. `id` is local (a UUID, not the message id) and names the
/// presenter's callbacks for this display. `state`, `impressed` and `clock` belong to the engine queue.
final class NottiInAppDisplay {
    let id: String
    let message: NottiInAppMessage
    /// Nil when the message has no auto dismiss (IAM-34).
    let clock: NottiInAppDisplayClock?
    var state: NottiInAppDisplayState = .preparing
    var impressed = false

    init(id: String, message: NottiInAppMessage, clock: NottiInAppDisplayClock? = nil) {
        self.id = id
        self.message = message
        self.clock = clock
    }
}

/// Visible-time accounting for `dismiss_after_seconds`, a port of RN `NottiInAppDisplayClock`
/// (`NottiInAppSession.swift:318-379`). Time runs only after `start()` and while the display is attached and
/// the app is in the foreground; a pause keeps the remaining time. The source is the wall clock in whole
/// milliseconds (D8: RN reads an uptime clock, a required-reason API this SDK does not declare). A clock
/// that moves backwards counts as no time elapsed.
final class NottiInAppDisplayClock {

    private static let secondsRange = 1...300

    /// Nil when `seconds` is absent or outside 1...300 (no auto dismiss).
    static func make(seconds: Int?, nowMs: @escaping () -> Int64) -> NottiInAppDisplayClock? {
        guard let seconds = seconds, secondsRange.contains(seconds) else { return nil }
        return NottiInAppDisplayClock(durationMs: Int64(seconds) * 1000, nowMs: nowMs)
    }

    private let nowMs: () -> Int64
    private var remainingAtPauseMs: Int64
    private var runningSinceMs: Int64?
    private var started = false
    private var attached = false
    private var foreground = true

    private init(durationMs: Int64, nowMs: @escaping () -> Int64) {
        self.remainingAtPauseMs = durationMs
        self.nowMs = nowMs
    }

    var isRunning: Bool { runningSinceMs != nil }

    func start() {
        started = true
        update()
    }

    func setAttached(_ value: Bool) {
        attached = value
        update()
    }

    func setForeground(_ value: Bool) {
        foreground = value
        update()
    }

    func remainingMs() -> Int64 {
        guard let since = runningSinceMs else { return remainingAtPauseMs }
        return max(remainingAtPauseMs - max(nowMs() - since, 0), 0)
    }

    var isExpired: Bool { remainingMs() == 0 }

    private func update() {
        let shouldRun = started && attached && foreground
        if shouldRun, runningSinceMs == nil {
            runningSinceMs = nowMs()
        } else if !shouldRun, runningSinceMs != nil {
            remainingAtPauseMs = remainingMs()
            runningSinceMs = nil
        }
    }
}

/// Display lifecycle (design "Display state machine", RN `NottiInAppCoordinator.swift:247-357`). Every
/// presenter callback hops onto the engine queue and is ignored unless it names the current display.
extension NottiInAppEngine {

    static let noListenerWarning = "Notti.inapp: click reported but no click listener is registered"

    /// Engine input: sets the `push_permission` platform action under the engine's confinement (RN `396d320`).
    func setPushPermissionPort(_ port: (() -> Void)?) {
        scheduler.execute { self.pushPermissionPort = port }
    }

    /// The display's window joined (true) or left (false) a scene: the clock runs only while attached.
    func displayAttached(displayId: String, attached: Bool) {
        scheduler.execute {
            guard let current = self.display, current.id == displayId else { return }
            current.clock?.setAttached(attached)
            self.scheduleClockCheck()
        }
    }

    /// First layout while attached and active: one impression per display (D9, IAM-27).
    func becameVisible(displayId: String) {
        scheduler.execute {
            guard let current = self.display, current.id == displayId,
                  current.state == .preparing, !current.impressed else { return }
            current.state = .visible
            current.impressed = true
            current.clock?.start()
            self.record(current, type: NottiInAppEventType.impression)
            self.scheduleClockCheck()
            self.requestFlush()
        }
    }

    /// A button, the image or a bar body was tapped (IAM-25, IAM-26, IAM-49): `click` queued, listeners
    /// called, display closed, then the `push_permission` port. Ignored unless the display is visible.
    func userTapped(displayId: String, buttonId: String, action: NottiInAppButtonAction?) {
        scheduler.execute { self.handleTap(displayId: displayId, buttonId: buttonId, action: action) }
    }

    /// The user closed the message (`close_button`, `swipe`, `outside_tap`). Ignored unless visible.
    func userDismissed(displayId: String, reason: String) {
        scheduler.execute { self.dismiss(displayId: displayId, reason: reason) }
    }

    /// The display could not be presented: a preparing display is dropped with no event.
    func displayFailed(displayId: String) {
        scheduler.execute {
            guard let current = self.display, current.id == displayId, current.state == .preparing else { return }
            current.state = .closed
            self.display = nil
        }
    }

    // MARK: - Engine queue

    func handleTap(displayId: String, buttonId: String, action: NottiInAppButtonAction?) {
        guard let current = closeVisible(displayId) else { return }
        record(current, type: NottiInAppEventType.click, buttonId: buttonId)
        let link: NottiInAppLinkAction?
        let runsPushPermission: Bool
        switch action {
        case .link(let value)?:
            link = value
            runsPushPermission = false
        case .pushPermission?:
            link = nil
            runsPushPermission = true
        case nil:
            link = nil
            runsPushPermission = false
        }
        // The listener never sees a push_permission action: it is not a link to handle.
        let click = NottiInAppClick(
            messageId: current.message.id,
            buttonId: buttonId,
            action: link.map(NottiInAppAction.init(link:))
        )
        let delivered = emitClick(click)
        if !delivered && !runsPushPermission {
            NottiLogger.log(.warn, Self.noListenerWarning, category: "inapp")
        }
        mainDispatcher { self.presenter.close(displayId: displayId) }
        if runsPushPermission, let port = pushPermissionPort {
            mainDispatcher(port)
        }
        requestFlush()
    }

    func dismiss(displayId: String, reason: String) {
        guard let current = closeVisible(displayId) else { return }
        record(current, type: NottiInAppEventType.dismiss, reason: reason)
        mainDispatcher { self.presenter.close(displayId: displayId) }
        requestFlush()
    }

    /// Closes a visible display exactly once; nil before visible, after the close, or for an old id.
    private func closeVisible(_ displayId: String) -> NottiInAppDisplay? {
        guard let current = display, current.id == displayId, current.state == .visible else { return nil }
        current.state = .closed
        display = nil
        return current
    }

    /// Persists the event with a fresh `eventId` before anything is sent (IAM-29).
    private func record(_ display: NottiInAppDisplay, type: String, buttonId: String? = nil, reason: String? = nil) {
        guard let appId = config?.appId else { return }
        store.enqueue(appId: appId, messageId: display.message.id, type: type, buttonId: buttonId, reason: reason)
    }

    /// Schedules a check at the remaining time while the clock runs; the check closes the display with
    /// `auto` only if it is still the same display and its time is up (a pause or a close makes it a no-op).
    func scheduleClockCheck() {
        guard let current = display, let clock = current.clock, clock.isRunning else { return }
        let displayId = current.id
        scheduler.schedule(after: TimeInterval(clock.remainingMs()) / 1000) {
            guard let latest = self.display, latest.id == displayId, latest.clock?.isExpired == true else { return }
            self.dismiss(displayId: displayId, reason: NottiInAppDismissReason.auto)
        }
    }

    /// Wall-clock milliseconds for the display clock (D8).
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

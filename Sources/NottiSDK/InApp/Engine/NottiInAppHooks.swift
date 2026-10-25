import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// The two `NottiCore` edges the In-App engine needs (design D4, RN `NottiInAppHooks`). Both run on the
/// core's `workQueue` and must only hand off (the engine hops onto its own queue). The default does nothing.
struct NottiInAppHooks {
    /// The process session gate opened for this core (`tryOpen() == true`); never for an adopted session.
    var onSessionStarted: (() -> Void)?
    /// A device registration answered `.success`, after the id and token were stored.
    var onDeviceRegistered: (() -> Void)?

    init(onSessionStarted: (() -> Void)? = nil, onDeviceRegistered: (() -> Void)? = nil) {
        self.onSessionStarted = onSessionStarted
        self.onDeviceRegistered = onDeviceRegistered
    }

    /// Forwards both edges to `engine`.
    static func forwarding(to engine: NottiInAppEngine) -> NottiInAppHooks {
        NottiInAppHooks(
            onSessionStarted: { engine.sessionStarted() },
            onDeviceRegistered: { engine.deviceRegistered() }
        )
    }
}

/// Carries the engine's clicks to whoever listens (IAM-24, IAM-25). The engine is built before the facade,
/// so the runtime owns this relay and the facade's `NottiListenerHub` attaches to it, as the device-id hub
/// attaches to `NottiRuntime.onDeviceIdChanged`. `emit` runs on the engine queue and only hands off: the hub
/// hops to the main thread.
final class NottiInAppClickRelay {
    private let lock = NSLock()
    private var _handler: ((NottiInAppClick) -> Void)?

    /// Set by the hub while at least one listener is registered, nil otherwise.
    var handler: ((NottiInAppClick) -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    /// False when no listener is registered (the engine then logs its one warning).
    func emit(_ click: NottiInAppClick) -> Bool {
        guard let handler = handler else { return false }
        handler(click)
        return true
    }
}

/// Stands in for the UIKit presenter until it exists (T17): shows nothing, so no display ever becomes
/// visible and no impression is recorded; a pending display is dropped at session end.
final class NottiInAppPlaceholderPresenter: NottiInAppPresenting {
    func present(_ display: NottiInAppDisplay) {}
    func close(displayId: String) {}
    func teardown(_ display: NottiInAppDisplay) {}
}

extension NottiInAppEngine {

    /// The production engine over the `notti_prefs` suite (`defaults`): the RN-compatible event queue, the
    /// identity read from `NottiDeviceStore` at send time, the queue scheduler and the `URLSession.shared`
    /// client factory. Clicks go to `clicks` (the facade's listener hub attaches there).
    static func live(
        defaults: UserDefaults,
        clicks: NottiInAppClickRelay,
        presenter: NottiInAppPresenting = NottiInAppPlaceholderPresenter()
    ) -> NottiInAppEngine {
        NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults),
            identity: deviceIdentity(defaults: defaults),
            presenter: presenter,
            emitClick: { clicks.emit($0) }
        )
    }

    /// The persisted device id and last token, both written by a registration `.success`; nil while either is
    /// missing or empty. Read at call time, never cached.
    static func deviceIdentity(defaults: UserDefaults) -> () -> NottiInAppIdentity? {
        let deviceStore = NottiDeviceStore(defaults: defaults)
        return {
            guard let deviceId = deviceStore.getDeviceId(), !deviceId.isEmpty,
                  let token = deviceStore.getLastToken(), !token.isEmpty else { return nil }
            return NottiInAppIdentity(deviceId: deviceId, token: token)
        }
    }
}

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
    /// client factory.
    static func live(defaults: UserDefaults, presenter: NottiInAppPresenting = NottiInAppPlaceholderPresenter()) -> NottiInAppEngine {
        NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults),
            identity: deviceIdentity(defaults: defaults),
            presenter: presenter
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

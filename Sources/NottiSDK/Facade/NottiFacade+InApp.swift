import Foundation

/// In-App messages behind the public `Notti.trackEvent` and `Notti.InAppMessages` (IAM-08, IAM-11, IAM-24).
@available(iOSApplicationExtension, unavailable)
extension NottiFacade {

    /// Hands the name to the engine, which ignores a blank name, a call before `initialize` and a call with
    /// no session open, and never sends, stores or logs it.
    func trackEvent(_ name: String) {
        runtime.inAppEngine.trackEvent(name)
    }

    /// Main-thread delivery through the click hub. With no listener the engine still reports the click and
    /// logs one warning.
    func addInAppClickListener(_ handler: @escaping (NottiInAppClick) -> Void) -> NottiSubscription {
        inAppClickHub.add(handler)
    }
}

import Foundation

/// SDK verbosity as the example screens show it. Mapped to `Notti.LogLevel` by `LiveSDKClient`.
enum ExampleLogLevel: String, CaseIterable, Identifiable {
    case none, error, warn, info, debug, verbose
    var id: String { rawValue }
}

typealias PayloadHandler = @MainActor @Sendable ([String]) -> Void
/// An In-App click reaches the model as the action type only: the link value and the ids stay in `LiveSDKClient`.
typealias InAppClickHandler = @MainActor @Sendable (InAppActionKind) -> Void

/// The calls `ExampleModel` makes into the SDK. A seam so hosted tests drive the model without
/// touching the real SDK (its delegate hooks are live in the test host process). Payloads reach the
/// model as key names only: values never leave `LiveSDKClient` (EXR-03).
protocol ExampleSDKClient {
    func initialize(appId: String, clientKey: String, baseUrl: String?)
    func requestPermission() async -> Bool
    func requestPermission(completion: @escaping (Bool) -> Void)
    func login(_ externalUserId: String)
    func logout()
    func setEmail(_ email: String)
    func clearEmail()
    func setPhone(_ phone: String)
    func clearPhone()
    func addTag(_ key: String, value: String)
    func addTags(_ tags: [String: String])
    func removeTag(_ key: String)
    func removeTags(_ keys: [String])
    func setSubscription(_ enabled: Bool)
    func setLocationSharingEnabled(_ enabled: Bool)
    func setLogLevel(_ level: ExampleLogLevel)
    func currentLogLevel() -> ExampleLogLevel
    func deviceId() -> String?
    /// Each `add…Listener` returns a closure that removes it.
    func addReceivedListener(_ handler: @escaping PayloadHandler) -> () -> Void
    func addClickedListener(_ handler: @escaping PayloadHandler) -> () -> Void
    func addDeviceIdChangedListener(_ handler: @escaping @MainActor @Sendable (String) -> Void) -> () -> Void
    func takeInitialClick() -> [String]?
    func trackEvent(_ name: String)
    func addInAppClickListener(_ handler: @escaping InAppClickHandler) -> () -> Void
}

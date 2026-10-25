import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// All the logic behind the public `Notti` API that the core cannot provide:
/// initialize idempotency, the pre-initialize core, listener multiplexing and
/// main-thread delivery. Everything else is a one-line forward to `NottiCore`.
///
/// The public shell forwards to `NottiFacade.shared`. Tests build isolated
/// instances over an isolated `NottiRuntime` and never touch `shared`.
@available(iOSApplicationExtension, unavailable)
final class NottiFacade {

    /// Host used when the integrator passes no `baseUrl` (RN `SAAS_BASE_URL`,
    /// `react-native-notti/src/index.tsx`). The only place it is written.
    static let defaultBaseUrl = "https://app.zeepnotti.app"

    /// The configuration of the running core. `baseUrl` is the normalized form,
    /// so `https://x/` and `https://x` count as the same.
    struct Config: Equatable {
        let appId: String
        let clientKey: String
        let baseUrl: String
    }

    let runtime: NottiRuntime
    private let dispatcher: NottiMainDispatcher
    private let installDelegates: () -> Void

    /// Behind the manual forwarding API (`Notti.Notifications.didReceive(_:)` and the others), the same
    /// entry points the swizzled path uses. Ignores a call while swizzling is active (DEL-09).
    let pushAdapter: NottiPushAdapter

    // One hub per event type, multiplexed over the core's single handler.
    private let receivedHub: NottiListenerHub<NottiNotificationPayload>
    private let clickedHub: NottiListenerHub<NottiNotificationPayload>
    private let deviceIdHub: NottiListenerHub<String>
    /// In-App clicks, attached to the runtime's click relay (`NottiFacade+InApp.swift`).
    let inAppClickHub: NottiListenerHub<NottiInAppClick>

    /// Guards `activeConfig` and makes "decide + `runtime.start`" one step, so two
    /// racing different `initialize` calls end with one consistent core.
    private let lock = NSLock()
    private var _activeConfig: Config?

    /// - Parameter installDelegates: runs at the start of every `initialize`: the idempotent safety net for
    ///   the delegate integration if the launch hook did not run. Production passes
    ///   `NottiDelegateInstaller.ensureInstalled`; tests keep the no-op and never touch the real `UIApplication`.
    /// - Parameter isSwizzlingActive: read by the manual forwarding API; production passes `NottiSwizzlingState`.
    init(
        runtime: NottiRuntime,
        dispatcher: @escaping NottiMainDispatcher = { DispatchQueue.main.async(execute: $0) },
        installDelegates: @escaping () -> Void = {},
        isSwizzlingActive: @escaping () -> Bool = { false }
    ) {
        self.runtime = runtime
        self.dispatcher = dispatcher
        self.installDelegates = installDelegates
        self.pushAdapter = NottiPushAdapter(runtime: runtime, isSwizzlingActive: isSwizzlingActive)
        let buffer = runtime.eventBuffer
        receivedHub = Self.makeNotificationHub(buffer: buffer, event: .received, dispatcher: dispatcher)
        clickedHub = Self.makeNotificationHub(buffer: buffer, event: .clicked, dispatcher: dispatcher)
        deviceIdHub = NottiListenerHub<String>(
            attach: { handler in runtime.onDeviceIdChanged = handler },
            detach: { runtime.onDeviceIdChanged = nil },
            dispatcher: dispatcher
        )
        let clicks = runtime.inAppClicks
        inAppClickHub = NottiListenerHub<NottiInAppClick>(
            attach: { handler in clicks.handler = handler },
            detach: { clicks.handler = nil },
            dispatcher: dispatcher
        )
    }

    private static func makeNotificationHub(
        buffer: NottiEventBuffer,
        event: NottiNotificationEvent,
        dispatcher: @escaping NottiMainDispatcher
    ) -> NottiListenerHub<NottiNotificationPayload> {
        NottiListenerHub<NottiNotificationPayload>(
            attach: { handler in
                buffer.setHandler(event) { handler(NottiNotificationPayload(eventPayload: $0)) }
            },
            detach: { buffer.setHandler(event, nil) },
            dispatcher: dispatcher
        )
    }

    /// The configuration `initialize` last accepted, or nil.
    var activeConfig: Config? {
        lock.withLock { _activeConfig }
    }

    // MARK: - Initialize (API-01, API-02)

    /// Starts the runtime. Never throws or crashes:
    /// - invalid arguments are logged (without their values) and ignored, and a
    ///   running core is left alone, so a typo in a second call cannot turn a
    ///   working SDK into a silent outage;
    /// - the same configuration as the running one is a no-op (no second
    ///   registration);
    /// - a different one stops the old core and starts a new one.
    ///
    /// `opensInAppURLs` (AD-020) is applied on every valid call, before that check, and is not part of
    /// `Config`: changing only it never restarts the core.
    func initialize(appId: String, clientKey: String, baseUrl: String?, opensInAppURLs: Bool = true) {
        installDelegates()
        guard
            !appId.isEmpty,
            !clientKey.isEmpty,
            let normalizedBaseUrl = NottiApiClient.validatedBaseUrl(baseUrl ?? Self.defaultBaseUrl)
        else {
            NottiLogger.log(.error, "Notti.initialize ignored: invalid appId, clientKey or baseUrl")
            return
        }
        let config = Config(appId: appId, clientKey: clientKey, baseUrl: normalizedBaseUrl)
        lock.lock()
        defer { lock.unlock() }
        runtime.setOpensInAppURLs(opensInAppURLs)
        guard _activeConfig != config else { return }
        _activeConfig = config
        runtime.start(appId: config.appId, clientKey: config.clientKey, baseUrl: config.baseUrl)
    }

    // MARK: - Identity and profile (API-04 ... API-08)
    //
    // One-line forwards. They go through `ensureCore()` so email and phone are
    // persisted even before `initialize` (DPF-19), and `logout`'s unlink is kept
    // (AD-018). The core drops `login`, tags and `setSubscription` before
    // `initialize` (no API client, RN parity); the facade only makes that visible
    // with one fixed warning per dropped call (PRF-02).

    /// The persisted device id, also before `initialize`; nil for a device that never registered.
    var deviceId: String? {
        runtime.ensureCore().getDeviceId()
    }

    func login(_ externalUserId: String) {
        warnIfDroppedBeforeInitialize("login")
        runtime.ensureCore().login(externalUserId)
    }

    func logout() {
        runtime.ensureCore().logout()
    }

    func addTags(_ tags: [String: String]) {
        warnIfDroppedBeforeInitialize("addTags")
        runtime.ensureCore().mutateTags(add: tags, remove: nil)
    }

    func removeTags(_ keys: [String]) {
        warnIfDroppedBeforeInitialize("removeTags")
        runtime.ensureCore().mutateTags(add: nil, remove: keys)
    }

    func setEmail(_ email: String) {
        runtime.ensureCore().setEmail(email)
    }

    func clearEmail() {
        runtime.ensureCore().clearEmail()
    }

    func setPhone(_ phone: String) {
        runtime.ensureCore().setPhone(phone)
    }

    func clearPhone() {
        runtime.ensureCore().clearPhone()
    }

    func setSubscription(_ enabled: Bool) {
        warnIfDroppedBeforeInitialize("setSubscription")
        runtime.ensureCore().setSubscription(enabled)
    }

    /// One fixed `.warn` line naming the method, never an argument, while no valid `initialize` was accepted.
    private func warnIfDroppedBeforeInitialize(_ method: StaticString) {
        guard activeConfig == nil else { return }
        NottiLogger.log(.warn, "Notti: \(method) called before initialize was dropped; call Notti.initialize first")
    }

    /// Runs on the caller's thread: the core writes the preference synchronously
    /// (LGPD B1), so an opt-out survives a process kill right after the call.
    func setLocationSharingEnabled(_ enabled: Bool) {
        runtime.ensureCore().setLocationSharingEnabled(enabled)
    }

    // MARK: - Permission (API-09, API-12)

    /// Asks the OS for notification permission and reports the dialog result on
    /// the main thread, once. Before `initialize` the core answers `false`
    /// without prompting. A second invocation of the core callback is ignored.
    func requestPermission(completion: @escaping (Bool) -> Void) {
        let once = Once()
        runtime.ensureCore().requestPermission { [dispatcher] granted in
            guard once.claim() else { return }
            dispatcher { completion(granted) }
        }
    }

    /// `async` variant of `requestPermission(completion:)`. The once-guard above
    /// guarantees the continuation is resumed exactly once.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            requestPermission { continuation.resume(returning: $0) }
        }
    }

    /// One-shot flag: `claim()` is true for the first caller only.
    private final class Once {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                if claimed { return false }
                claimed = true
                return true
            }
        }
    }

    // MARK: - Listeners and initial click (API-05, API-10 ... API-12)

    /// Works before `initialize` too: the event buffer lives in the runtime. The
    /// first listener also receives the events buffered so far.
    func addReceivedListener(_ handler: @escaping (NottiNotificationPayload) -> Void) -> NottiSubscription {
        receivedHub.add(handler)
    }

    /// Live clicks only. A cold-start click is never replayed here: it waits for
    /// `takeInitialClick()`.
    func addClickedListener(_ handler: @escaping (NottiNotificationPayload) -> Void) -> NottiSubscription {
        clickedHub.add(handler)
    }

    /// Called once per real device-id change, not on a re-registration with the same id.
    func addDeviceIdChangedListener(_ handler: @escaping (String) -> Void) -> NottiSubscription {
        deviceIdHub.add(handler)
    }

    /// The click that launched the app, once; nil afterwards.
    func takeInitialClick() -> NottiNotificationPayload? {
        runtime.eventBuffer.takeInitialClick().map { NottiNotificationPayload(eventPayload: $0) }
    }

    // MARK: - Log level (API-14)

    /// Maps to `NottiLogger.level`. Starts at `.error` (CORE-13).
    var logLevel: NottiLogLevelObjC {
        get { NottiLogLevelObjC(NottiLogger.level) }
        set { NottiLogger.level = newValue.coreLevel }
    }
}

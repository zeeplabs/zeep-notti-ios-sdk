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

    private let runtime: NottiRuntime
    private let dispatcher: NottiMainDispatcher

    /// Guards `activeConfig` and makes "decide + `runtime.start`" one step, so two
    /// racing different `initialize` calls end with one consistent core.
    private let lock = NSLock()
    private var _activeConfig: Config?

    init(
        runtime: NottiRuntime,
        dispatcher: @escaping NottiMainDispatcher = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.runtime = runtime
        self.dispatcher = dispatcher
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
    func initialize(appId: String, clientKey: String, baseUrl: String?) {
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
        guard _activeConfig != config else { return }
        _activeConfig = config
        runtime.start(appId: config.appId, clientKey: config.clientKey, baseUrl: config.baseUrl)
    }

    // MARK: - Identity and profile (API-04 ... API-08)
    //
    // One-line forwards. They go through `ensureCore()` so email and phone are
    // persisted even before `initialize` (DPF-19); the core itself drops what
    // needs a registered device (login, tags, subscription).

    /// The persisted device id, also before `initialize`; nil for a device that never registered.
    var deviceId: String? {
        runtime.ensureCore().getDeviceId()
    }

    func login(_ externalUserId: String) {
        runtime.ensureCore().login(externalUserId)
    }

    func logout() {
        runtime.ensureCore().logout()
    }

    func addTags(_ tags: [String: String]) {
        runtime.ensureCore().mutateTags(add: tags, remove: nil)
    }

    func removeTags(_ keys: [String]) {
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
        runtime.ensureCore().setSubscription(enabled)
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
}

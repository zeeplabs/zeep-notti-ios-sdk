import Foundation
import UIKit
#if canImport(NottiShared)
import NottiShared
#endif

/// Owns the SDK's process-wide state and the live `NottiCore` (CORE-03).
///
/// Replaces the RN statics: `NottiImpl.activeCore`, `processSessionGate`,
/// `processBackgroundObserver`, `eventStore`, `NottiEventBuffer.shared` and
/// `NottiNetworkObserver.shared`. Its event store, buffer, session gate and
/// observers exist before any core, so a notification handled before `start`
/// is persisted and flushed once a core registers (CORE-04).
///
/// Tests build isolated instances with `init(...)` and never touch `shared`.
final class NottiRuntime {

    /// UserDefaults suite shared with react-native-notti 0.6.0 (CORE-09). Renaming
    /// it would orphan every migrated device's registration and pending events.
    static let defaultsSuiteName = "notti_prefs"

    /// The process-wide runtime, wired to `defaultsSuiteName` and the OS providers.
    @available(iOSApplicationExtension, unavailable)
    static let shared: NottiRuntime = {
        let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        let clicks = NottiInAppClickRelay()
        return NottiRuntime(
            defaults: defaults,
            providers: .live(),
            inAppEngine: .live(defaults: defaults, clicks: clicks, presenter: NottiInAppPresenter()),
            inAppClicks: clicks,
            pushPermissionPlatform: .system,
            urlOpenPlatform: .system
        )
    }()

    let eventStore: NottiEventStore
    let eventBuffer = NottiEventBuffer()
    let sessionGate = NottiCore.SessionGate()
    /// Process-wide In-App engine: survives core replacement, hears the two core hooks and the process
    /// observers (design D4, D14).
    let inAppEngine: NottiInAppEngine
    /// Where `inAppEngine` hands its clicks; the facade's click hub attaches here.
    let inAppClicks: NottiInAppClickRelay

    private let defaults: UserDefaults
    private let providers: NottiPlatformProviders
    private let apiClientFactory: (_ appId: String, _ clientKey: String, _ baseUrl: String) -> NottiApiClient
    private let sdkVersion: String

    /// Guards `_core` and `_onDeviceIdChanged`.
    private let lock = NSLock()
    /// Serializes `start` / `stop`, so two callers never build two live cores.
    private let lifecycleLock = NSLock()
    private var _core: NottiCore?
    private var _onDeviceIdChanged: ((String) -> Void)?

    private var networkObserver: NottiNetworkObserver?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private let notificationCenter: NotificationCenter
    private let pushPermissionPlatform: NottiPushPermissionAction.Platform?

    /// - Parameters:
    ///   - sdkVersion: value sent as `sdk_version`. Production passes the native
    ///     constant (CORE-05); an empty value omits the field, as in RN.
    ///   - startObservers: starts the background observer (closes the session
    ///     gate on `didEnterBackground`) and the network observer (flushes on
    ///     reconnect). Tests that don't need them pass `false`.
    ///   - inAppEngine: `shared` passes the production engine; when nil the
    ///     runtime gets one with no client, which sends nothing (tests).
    ///   - inAppClicks: the relay `inAppEngine` emits clicks to; pass the same
    ///     relay the engine was built with.
    ///   - notificationCenter: where the process observers listen.
    ///   - pushPermissionPlatform: the OS side of the In-App `push_permission`
    ///     button (`shared` passes `.system`); nil sets no port (tests).
    ///   - urlOpenPlatform: the OS side of opening an In-App `url` action in the
    ///     browser (AD-020; `shared` passes `.system`); nil sets no port, so the
    ///     SDK opens nothing (tests).
    init(
        defaults: UserDefaults,
        providers: NottiPlatformProviders,
        pathMonitor: NottiPathMonitoring = NottiPathMonitorAdapter(),
        apiClientFactory: @escaping (_ appId: String, _ clientKey: String, _ baseUrl: String) -> NottiApiClient = {
            NottiApiClient(baseUrl: $2, appId: $0, clientKey: $1)
        },
        sdkVersion: String = NottiSDKVersion.current,
        startObservers: Bool = true,
        inAppEngine: NottiInAppEngine? = nil,
        inAppClicks: NottiInAppClickRelay = NottiInAppClickRelay(),
        notificationCenter: NotificationCenter = .default,
        pushPermissionPlatform: NottiPushPermissionAction.Platform? = nil,
        urlOpenPlatform: NottiInAppURLOpener.Platform? = nil
    ) {
        self.defaults = defaults
        self.inAppClicks = inAppClicks
        self.inAppEngine = inAppEngine ?? NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults),
            identity: NottiInAppEngine.deviceIdentity(defaults: defaults),
            presenter: NottiInAppPlaceholderPresenter(),
            clientFactory: { _ in nil },
            emitClick: { inAppClicks.emit($0) }
        )
        self.notificationCenter = notificationCenter
        self.pushPermissionPlatform = pushPermissionPlatform
        self.providers = providers
        self.apiClientFactory = apiClientFactory
        self.sdkVersion = sdkVersion
        self.eventStore = NottiEventStore(defaults: defaults)
        let observer = NottiNetworkObserver(monitor: pathMonitor) { [weak self] in
            self?.onNetworkAvailable()
        }
        self.networkObserver = observer
        // AD-020: the engine holds the opener through its port; no port, no SDK open.
        if let platform = urlOpenPlatform {
            let opener = NottiInAppURLOpener(platform: platform)
            self.inAppEngine.setURLOpenPort { opener.open($0) }
        }
        guard startObservers else { return }
        // RN `processBackgroundObserver`: close the gate on background even when
        // no core is alive to hear about it, then end the In-App session and pause
        // its display clock (RN `handleProcessBackground`).
        let gate = sessionGate
        let engine = self.inAppEngine
        backgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            gate.close()
            engine.sessionEnded()
            engine.appBackgrounded()
        }
        // RN `processForegroundObserver`: later In-App sessions open here, without
        // waiting for the core's work queue (IAM-51).
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            engine.appForegrounded()
        }
        observer.start()
    }

    deinit {
        if let backgroundObserver {
            notificationCenter.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            notificationCenter.removeObserver(foregroundObserver)
        }
        networkObserver?.cancel()
        _core?.invalidate()
    }

    /// The live core, or nil before `start` / `ensureCore` and after `stop`.
    ///
    /// Since `ensureCore()` exists, a non-nil core no longer implies "initialized":
    /// it may be an uninitialized core that only holds persisted state.
    var core: NottiCore? {
        lock.withLock { _core }
    }

    /// Called on the core's work queue whenever the persisted device id changes.
    var onDeviceIdChanged: ((String) -> Void)? {
        get { lock.withLock { _onDeviceIdChanged } }
        set { lock.withLock { _onDeviceIdChanged = newValue } }
    }

    /// Builds a core and initializes it. A previous core is invalidated first;
    /// the new one adopts the open session through `sessionGate` (RN JS-reload
    /// parity, SEGTEL-08).
    func start(appId: String, clientKey: String, baseUrl: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        invalidateCurrentCore()
        // In-App first, from this thread, so a `trackEvent` right after `start`
        // finds the config (D12). Invalid input is left to the core, which logs it.
        var inAppConfig: NottiInAppConfig?
        if !appId.isEmpty, !clientKey.isEmpty, let normalized = NottiApiClient.validatedBaseUrl(baseUrl) {
            inAppEngine.configure(appId: appId, clientKey: clientKey, baseUrl: normalized)
            inAppConfig = NottiInAppConfig(appId: appId, clientKey: clientKey, baseUrl: normalized)
        }
        wirePushPermissionPort()
        let core = makeCore(inAppConfig: inAppConfig)
        lock.withLock { _core = core }
        core.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkVersion: sdkVersion)
    }

    /// Returns the live core, or builds an uninitialized one and stores it as the
    /// current core. Lets the facade call `getDeviceId`, `setEmail` and `setPhone`
    /// before `initialize`, as RN's eagerly built core does (DPF-19). An
    /// uninitialized core sends nothing, but it is not inert (RN parity): it
    /// registers its foreground/background observers, and when the app is active
    /// it opens the process session gate, writes session telemetry and reports
    /// the session start to the In-App engine; later cores adopt that session.
    /// `start` still invalidates whichever core is current and installs a new one.
    func ensureCore() -> NottiCore {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lock.withLock {
            if let existing = _core { return existing }
            let created = makeCore(inAppConfig: nil)
            _core = created
            return created
        }
    }

    /// `Notti.Options.opensInAppURLs` (AD-020): whether the In-App engine opens `url` actions itself. Local
    /// behavior only: it never restarts the core.
    func setOpensInAppURLs(_ enabled: Bool) {
        inAppEngine.setOpensURLs(enabled)
    }

    /// Invalidates and drops the live core. Persisted state is left alone.
    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        invalidateCurrentCore()
    }

    /// Flush trigger (RN `NottiNetworkObserver.shared`'s callback): the core's part
    /// is a no-op without a core; the In-App engine flushes and resumes a fetch
    /// that gave up on a transient failure (IAM-52).
    func onNetworkAvailable() {
        core?.onNetworkAvailable()
        inAppEngine.networkAvailable()
    }

    /// APNs token callback. Hex conversion from RN `NottiBridge` (NottiPushDelegate.swift:17-20).
    /// The token is never logged. Without a core the token is dropped, as in RN.
    func onApnsToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        core?.onTokenRefreshed(token)
    }

    /// APNs registration failure (SDK-04): logged, never thrown. Logs
    /// `domain#code` instead of RN's `localizedDescription` (CORE-12).
    func onApnsRegistrationFailed(_ error: Error) {
        let nsError = error as NSError
        NottiLogger.log(.error, "Notti: failed to register for remote notifications - \(nsError.domain)#\(nsError.code)")
    }

    /// Keeps only string keys with string values (RN `NottiImpl.addTags`,
    /// NottiImpl.swift:325-341): a non-string value is dropped, not coerced.
    static func sanitizeTags(_ tags: [AnyHashable: Any]) -> [String: String] {
        var add: [String: String] = [:]
        for (key, value) in tags {
            if let key = key as? String, let stringValue = value as? String {
                add[key] = stringValue
            }
        }
        return add
    }

    /// Hands the engine the `push_permission` action (D15, RN `wirePushPermissionPort`). The prompt goes
    /// through whichever core is current when the button is tapped, so a replaced core is never used.
    private func wirePushPermissionPort() {
        guard let platform = pushPermissionPlatform else { return }
        let action = NottiPushPermissionAction(
            readState: platform.readState,
            requestPermission: { [weak self] in self?.core?.requestPermission { _ in } },
            openNotificationSettings: platform.openNotificationSettings
        )
        inAppEngine.setPushPermissionPort { action.run() }
    }

    /// Caller holds `lifecycleLock`.
    private func invalidateCurrentCore() {
        let previous: NottiCore? = lock.withLock {
            let current = _core
            _core = nil
            return current
        }
        guard let previous else { return }
        previous.invalidate()
        // Mutations already queued on the old core capture it weakly, so releasing
        // it here would silently drop them (a `setEmail` made before `initialize`
        // would be lost when `start` replaces the ensured core). Hold it until its
        // queue has drained; the bounded wait only pins one utility thread.
        DispatchQueue.global(qos: .utility).async {
            _ = previous.waitForPendingWork(timeout: Self.retireTimeout)
        }
    }

    /// How long a replaced core is kept alive to finish the work already queued on it.
    private static let retireTimeout: TimeInterval = 60

    /// - Parameter inAppConfig: the config `start` gave the In-App engine; nil for the pre-`initialize` core.
    private func makeCore(inAppConfig: NottiInAppConfig?) -> NottiCore {
        NottiCore(
            deviceStore: NottiDeviceStore(defaults: defaults),
            eventStore: eventStore,
            apiClientFactory: apiClientFactory,
            tokenProvider: providers.tokenProvider,
            permissionRequester: providers.permissionRequester,
            versionProvider: providers.versionProvider,
            hasLocationPermission: providers.hasLocationPermission,
            countryProvider: providers.countryProvider,
            deviceOsProvider: providers.deviceOsProvider,
            deviceModelProvider: providers.deviceModelProvider,
            timezoneProvider: providers.timezoneProvider,
            languageProvider: providers.languageProvider,
            permissionStatusProvider: providers.permissionStatusProvider,
            appStateProvider: providers.appStateProvider,
            beginBackgroundTask: providers.beginBackgroundTask,
            logger: { level, message in NottiLogger.log(level, message) },
            onDeviceIdChanged: { [weak self] deviceId in self?.onDeviceIdChanged?(deviceId) },
            inAppHooks: .forwarding(to: inAppEngine, config: inAppConfig),
            sessionGate: sessionGate
        )
    }
}

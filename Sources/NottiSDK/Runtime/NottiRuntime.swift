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

    /// The process-wide runtime, wired to `notti_prefs` and the OS providers.
    @available(iOSApplicationExtension, unavailable)
    static let shared = NottiRuntime(
        defaults: UserDefaults(suiteName: "notti_prefs") ?? .standard,
        providers: .live()
    )

    let eventStore: NottiEventStore
    let eventBuffer = NottiEventBuffer()
    let sessionGate = NottiCore.SessionGate()

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

    /// - Parameters:
    ///   - sdkVersion: value sent as `sdk_version`. Production passes the native
    ///     constant (CORE-05); an empty value omits the field, as in RN.
    ///   - startObservers: starts the background observer (closes the session
    ///     gate on `didEnterBackground`) and the network observer (flushes on
    ///     reconnect). Tests that don't need them pass `false`.
    init(
        defaults: UserDefaults,
        providers: NottiPlatformProviders,
        pathMonitor: NottiPathMonitoring = NottiPathMonitorAdapter(),
        apiClientFactory: @escaping (_ appId: String, _ clientKey: String, _ baseUrl: String) -> NottiApiClient = {
            NottiApiClient(baseUrl: $2, appId: $0, clientKey: $1)
        },
        sdkVersion: String = NottiSDKVersion.current,
        startObservers: Bool = true
    ) {
        self.defaults = defaults
        self.providers = providers
        self.apiClientFactory = apiClientFactory
        self.sdkVersion = sdkVersion
        self.eventStore = NottiEventStore(defaults: defaults)
        let observer = NottiNetworkObserver(monitor: pathMonitor) { [weak self] in
            self?.onNetworkAvailable()
        }
        self.networkObserver = observer
        guard startObservers else { return }
        // RN `processBackgroundObserver`: close the gate on background even when
        // no core is alive to hear about it.
        let gate = sessionGate
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            gate.close()
        }
        observer.start()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        networkObserver?.cancel()
        _core?.invalidate()
    }

    /// The live core, or nil before `start` / after `stop`.
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
        let core = makeCore()
        lock.withLock { _core = core }
        core.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkVersion: sdkVersion)
    }

    /// Invalidates and drops the live core. Persisted state is left alone.
    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        invalidateCurrentCore()
    }

    /// Flush trigger (RN `NottiNetworkObserver.shared`'s callback). No-op without a core.
    func onNetworkAvailable() {
        core?.onNetworkAvailable()
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

    /// Caller holds `lifecycleLock`.
    private func invalidateCurrentCore() {
        let previous: NottiCore? = lock.withLock {
            let current = _core
            _core = nil
            return current
        }
        previous?.invalidate()
    }

    private func makeCore() -> NottiCore {
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
            sessionGate: sessionGate
        )
    }
}

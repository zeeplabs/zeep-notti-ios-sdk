// Ported from react-native-notti 52e4b55 ios/NottiImpl.swift:112-214 (the OS-backed closures `NottiImpl.init` passes to `NottiCore`) (AD-002).
// Changes: the closures move into `NottiPlatformProviders.live()` (a struct with one field per `NottiCore.init` provider
// parameter); `NottiImpl.beginBackgroundTask()` -> `NottiBackgroundTask.begin()`; one comment no longer names the RN
// promise type (CORE-01: no RN symbols in Sources); an explicit `.ephemeral` -> nil case (see SPEC_DEVIATION below).
// Closure bodies and their main-thread hops are otherwise unchanged.

import Foundation
import UIKit
import UserNotifications

/// The OS-backed reads and prompts `NottiCore` takes as injected closures, one
/// field per provider parameter of `NottiCore.init`. `live()` is the production
/// wiring; tests build their own values.
struct NottiPlatformProviders {
    var tokenProvider: (_ callback: @escaping (String?) -> Void) -> Void
    var permissionRequester: (_ callback: @escaping (Bool) -> Void) -> Void
    var versionProvider: () -> String?
    var hasLocationPermission: () -> Bool
    var countryProvider: (@escaping (String?) -> Void) -> Void
    var deviceOsProvider: () -> String?
    var deviceModelProvider: () -> String?
    var timezoneProvider: () -> String?
    var languageProvider: () -> String?
    var permissionStatusProvider: (@escaping (String?) -> Void) -> Void
    var appStateProvider: (@escaping (_ isActive: Bool) -> Void) -> Void
    var beginBackgroundTask: () -> (() -> Void)

    /// Defaults match `NottiCore.init`'s defaults for the same parameters.
    init(
        tokenProvider: @escaping (_ callback: @escaping (String?) -> Void) -> Void,
        permissionRequester: @escaping (_ callback: @escaping (Bool) -> Void) -> Void,
        versionProvider: @escaping () -> String? = { nil },
        hasLocationPermission: @escaping () -> Bool = { false },
        countryProvider: @escaping (@escaping (String?) -> Void) -> Void = { $0(nil) },
        deviceOsProvider: @escaping () -> String? = { nil },
        deviceModelProvider: @escaping () -> String? = { nil },
        timezoneProvider: @escaping () -> String? = { nil },
        languageProvider: @escaping () -> String? = { nil },
        permissionStatusProvider: @escaping (@escaping (String?) -> Void) -> Void = { $0(nil) },
        appStateProvider: @escaping (@escaping (_ isActive: Bool) -> Void) -> Void = { $0(false) },
        beginBackgroundTask: @escaping () -> (() -> Void) = { {} }
    ) {
        self.tokenProvider = tokenProvider
        self.permissionRequester = permissionRequester
        self.versionProvider = versionProvider
        self.hasLocationPermission = hasLocationPermission
        self.countryProvider = countryProvider
        self.deviceOsProvider = deviceOsProvider
        self.deviceModelProvider = deviceModelProvider
        self.timezoneProvider = timezoneProvider
        self.languageProvider = languageProvider
        self.permissionStatusProvider = permissionStatusProvider
        self.appStateProvider = appStateProvider
        self.beginBackgroundTask = beginBackgroundTask
    }

    /// Production providers. Creates the `NottiLocationReader` up front, as
    /// `NottiImpl.init` did, so its permission seed is enqueued on main before
    /// a core built from these providers enqueues its `appStateProvider` read.
    @available(iOSApplicationExtension, unavailable)
    static func live() -> NottiPlatformProviders {
        let locationReader = NottiLocationReader()
        return NottiPlatformProviders(
            tokenProvider: { _ in
                // APNs delivers the device token asynchronously via
                // application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
                // (T15, host AppDelegate-forwarded) — there is no synchronous
                // "get current token" API on iOS, so this never invokes the
                // callback itself; T15's forwarded callback calls
                // `NottiCore.onTokenRefreshed` once the real token arrives,
                // which performs the actual registration (both the first-time
                // and any later refresh, uniformly).
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            },
            permissionRequester: { callback in
                // No main-thread hop: `NottiCore` hops the result onto its own
                // background work queue (where the blocking PATCH runs), and the
                // caller's completion may be resolved from any thread. Hopping to
                // main here would have put the blocking API-client call chain back on
                // the main thread.
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    callback(granted)
                }
            },
            // Segment telemetry P1 (T7): reads the host app's marketing version once
            // per launch; `Bundle.main.infoDictionary` has no entry for it in an
            // odd host build, in which case this returns nil and `NottiCore` skips
            // the sync (SEGTEL edge: no crash, no registration block).
            versionProvider: {
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            },
            // Segment telemetry P3 (T9): check-only OS location permission read —
            // the SDK never calls `requestWhenInUseAuthorization` (SEGTEL-14); it
            // only reports country when the host app has already granted permission
            // for its own purposes.
            hasLocationPermission: { locationReader.hasPermission() },
            // Device profile fields P1 (T7, DPF-01): OS version / model / timezone /
            // language reads. Each fails to nil - never a crash (DPF-04/09).
            // Segment telemetry P3 (T9): best-effort, async country resolution from
            // the last cached fix reverse-geocoded to its ISO 3166-1 alpha-2 code.
            // A stale fix is acceptable at country-level granularity (SEGTEL edge
            // case); nil on any failure (services disabled, no fix, geocode error,
            // a geocode already in flight) → the field is omitted.
            countryProvider: { callback in locationReader.readCountry(callback) },
            // Device profile fields P1 (T7, DPF-01): OS version / model / timezone /
            // language reads. Each fails to nil - never a crash (DPF-04/09).
            deviceOsProvider: {
                UIDevice.current.systemVersion
            },
            deviceModelProvider: {
                var systemInfo = utsname()
                uname(&systemInfo)
                let mirror = Mirror(reflecting: systemInfo.machine)
                let bytes = mirror.children.map { $0.value as? Int8 ?? 0 }
                let model = String(bytes: bytes.map { UInt8(bitPattern: $0) }, encoding: .ascii)?
                    .trimmingCharacters(in: .controlCharacters)
                return model?.isEmpty == false ? model : nil
            },
            timezoneProvider: {
                TimeZone.current.identifier
            },
            languageProvider: {
                // ISO 639-1 primary subtag; "" / "und" -> nil (parity with Android).
                NottiCore.normalizedLanguageCode(Locale.current.languageCode)
            },
            // Device profile fields P3 (T8, DPF-10): OS push-permission state read
            // via `getNotificationSettings` (callback-based). Maps authorization
            // status to the enum; unknown/transitional resolves nil (omit, never
            // fabricate - DPF edge case).
            permissionStatusProvider: { callback in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    let status: String?
                    switch settings.authorizationStatus {
                    case .authorized: status = "granted"
                    case .denied: status = "denied"
                    case .notDetermined: status = "notDetermined"
                    case .provisional: status = "provisional"
                    // SPEC_DEVIATION: explicit `.ephemeral` case, not in RN.
                    // Reason: RN reached it through `@unknown default` (nil); the compiler warns
                    // "switch must be exhaustive" and `pod lib lint` fails on warnings. Same value (nil).
                    case .ephemeral: status = nil
                    @unknown default: status = nil
                    }
                    callback(status)
                }
            },
            // Review item 2: the cold-start `didBecomeActive` usually fired before
            // this module was constructed; report whether the app is already active
            // (read on the main thread, asynchronously - never `main.sync`, which
            // could deadlock a module constructed while main waits on it).
            appStateProvider: { callback in
                DispatchQueue.main.async {
                    callback(UIApplication.shared.applicationState == .active)
                }
            },
            // Review item 3: keep the process alive while the session-end
            // bookkeeping + PATCH queued at `didEnterBackground` run.
            beginBackgroundTask: { NottiBackgroundTask.begin() }
        )
    }
}

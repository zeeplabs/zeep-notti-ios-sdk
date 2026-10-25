import Foundation

/// Entry point of the Notti SDK for Swift hosts.
///
/// Call `Notti.initialize(appId:clientKey:)` once at launch, as early as
/// possible. Every other call is safe before it, but not every call is kept:
/// email, phone and `logout` are kept and sent at registration (`logout` is the
/// only identity call kept from before `initialize`), while `login`, tags and
/// `setSubscription` are dropped, each with one warning (level `warn`), as in the
/// React Native SDK. Call them after `initialize`.
///
/// All callbacks (`requestPermission`, listeners) run on the main thread. No
/// method throws, and none logs email, phone, push token, external user id,
/// country or tag values.
///
/// Not available in app extensions: use `NottiSDKExtension` in a Notification
/// Service Extension.
@available(iOSApplicationExtension, unavailable)
public enum Notti {

    /// Verbosity of the SDK's own logs. Default `.error`.
    public typealias LogLevel = NottiLogLevelObjC

    /// Optional configuration for `initialize`.
    public struct Options {
        /// Backend host (`https://...`). `nil` uses the Notti default host.
        public var baseUrl: String?

        /// Whether the SDK opens an In-App `url` action in the external browser, after the click listeners
        /// ran. Default `true`. Only `http` and `https` links with a host are opened; a `deeplink` or any
        /// other scheme is never opened by the SDK and reaches the listener only. With `false` the SDK opens
        /// no In-App link: handle `url` actions in `Notti.InAppMessages.addClickListener`.
        ///
        /// Every valid `initialize` sets the option to the value it carries, like `baseUrl` (PRF-08): a later
        /// `initialize` without options turns it back on. Pass the same `Options` on every call.
        public var opensInAppURLs: Bool

        public init(baseUrl: String? = nil, opensInAppURLs: Bool = true) {
            self.baseUrl = baseUrl
            self.opensInAppURLs = opensInAppURLs
        }
    }

    // MARK: - Initialize and identity

    /// Starts the SDK. Calling it again with the same values does nothing; with
    /// a different app id, client key or base URL it restarts the SDK, and a
    /// different `opensInAppURLs` alone is applied without a restart. Each valid
    /// call applies all of `options`: omitted values fall back to their defaults
    /// (default host, `opensInAppURLs` true). Invalid values are logged (without
    /// the values) and ignored.
    public static func initialize(appId: String, clientKey: String, options: Options = Options()) {
        NottiFacade.shared.initialize(
            appId: appId,
            clientKey: clientKey,
            baseUrl: options.baseUrl,
            opensInAppURLs: options.opensInAppURLs
        )
    }

    /// Associates this device with the host's own user id. Dropped before
    /// `initialize` (one warning): call it after `initialize`.
    public static func login(_ externalUserId: String) {
        NottiFacade.shared.login(externalUserId)
    }

    /// Clears the user id, email and phone on this device.
    public static func logout() {
        NottiFacade.shared.logout()
    }

    /// The device id issued by the backend, also before `initialize` for an
    /// already registered device; `nil` for a device that never registered.
    public static var deviceId: String? {
        NottiFacade.shared.deviceId
    }

    /// Calls `handler` on the main thread each time the device id changes.
    /// Keep the subscription and call `remove()` to stop; it is not removed on
    /// `deinit`.
    @discardableResult
    public static func addDeviceIdChangedListener(_ handler: @escaping (String) -> Void) -> NottiSubscription {
        NottiFacade.shared.addDeviceIdChangedListener(handler)
    }

    /// Opts the device in or out of sharing its country. Off by default. The
    /// preference is stored before the call returns.
    public static func setLocationSharingEnabled(_ enabled: Bool) {
        NottiFacade.shared.setLocationSharingEnabled(enabled)
    }

    /// Verbosity of the SDK's own logs. Default `.error`.
    public static var logLevel: LogLevel {
        get { NottiFacade.shared.logLevel }
        set { NottiFacade.shared.logLevel = newValue }
    }

    // MARK: - User profile

    /// Profile data of the current user: tags, email, phone and subscription.
    /// Tag and subscription calls are dropped before `initialize` (one warning
    /// each); email and phone are kept and sent at registration.
    public enum User {
        /// Adds or updates one tag.
        public static func addTag(_ key: String, value: String) {
            NottiFacade.shared.addTags([key: value])
        }

        /// Adds or updates several tags.
        public static func addTags(_ tags: [String: String]) {
            NottiFacade.shared.addTags(tags)
        }

        public static func removeTag(_ key: String) {
            NottiFacade.shared.removeTags([key])
        }

        public static func removeTags(_ keys: [String]) {
            NottiFacade.shared.removeTags(keys)
        }

        public static func setEmail(_ email: String) {
            NottiFacade.shared.setEmail(email)
        }

        public static func clearEmail() {
            NottiFacade.shared.clearEmail()
        }

        public static func setPhone(_ phone: String) {
            NottiFacade.shared.setPhone(phone)
        }

        public static func clearPhone() {
            NottiFacade.shared.clearPhone()
        }

        /// Subscribes or unsubscribes this device from notifications.
        public static func setSubscription(_ enabled: Bool) {
            NottiFacade.shared.setSubscription(enabled)
        }
    }

    // MARK: - Notifications

    /// Permission prompt, listeners and the launch notification.
    public enum Notifications {
        /// Asks the user for notification permission. Returns `false` before
        /// `initialize`, without prompting.
        public static func requestPermission() async -> Bool {
            await NottiFacade.shared.requestPermission()
        }

        /// Completion-handler variant of `requestPermission()`. `completion`
        /// runs once, on the main thread.
        public static func requestPermission(completion: @escaping (Bool) -> Void) {
            NottiFacade.shared.requestPermission(completion: completion)
        }

        /// Calls `handler` on the main thread for each notification received
        /// while the app runs. The first listener also gets the ones buffered
        /// before it was added.
        @discardableResult
        public static func addReceivedListener(
            _ handler: @escaping (NottiNotificationPayload) -> Void
        ) -> NottiSubscription {
            NottiFacade.shared.addReceivedListener(handler)
        }

        /// Calls `handler` on the main thread when the user taps a notification
        /// while at least one clicked listener is attached. A tap that arrives
        /// with none attached is not replayed: it is kept for
        /// `takeInitialClick()`. On UIKit the launch tap arrives after
        /// `didFinishLaunching` returns, so a listener added there receives it
        /// live. Handle a launch from both paths, whichever comes first.
        @discardableResult
        public static func addClickedListener(
            _ handler: @escaping (NottiNotificationPayload) -> Void
        ) -> NottiSubscription {
            NottiFacade.shared.addClickedListener(handler)
        }

        /// The latest tap that arrived while no clicked listener was attached
        /// (normally the one that launched the app), once; `nil` afterwards and
        /// when a listener already received it.
        public static func takeInitialClick() -> NottiNotificationPayload? {
            NottiFacade.shared.takeInitialClick()
        }
    }
}

// MARK: - Shared facade and test seam

@available(iOSApplicationExtension, unavailable)
extension NottiFacade {
    private static let sharedLock = NSLock()
    private static let production = NottiFacade(
        runtime: .shared,
        installDelegates: { NottiDelegateInstaller.ensureInstalled() },
        isSwizzlingActive: { NottiSwizzlingState.shared.isActive }
    )
    private static var override: NottiFacade?

    /// The facade behind the public `Notti` API, built on `NottiRuntime.shared`.
    static var shared: NottiFacade {
        sharedLock.withLock { override ?? production }
    }

    /// Test seam (internal, no public setter): routes `Notti` to a facade built
    /// on an isolated runtime. Pass `nil` to restore the production facade.
    static func setSharedForTesting(_ facade: NottiFacade?) {
        sharedLock.withLock { override = facade }
    }
}

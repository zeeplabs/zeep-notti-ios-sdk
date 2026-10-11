import Foundation
import ObjectiveC
import UIKit
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// `UNUserNotificationCenter.current()` looked up lazily, and only in a process whose main bundle is an
/// `.app` (`current()` raises `NSInternalInconsistencyException` in a process with no bundle proxy, such as
/// the XCTest agent, even though `bundleIdentifier` is set there). The installer is built at process launch,
/// so the center must not be touched until the end of launch or a later `initialize`.
@available(iOSApplicationExtension, unavailable)
final class NottiCurrentNotificationCenter: NottiNotificationCenterHost {

    var delegate: UNUserNotificationCenterDelegate? {
        get { Self.current()?.delegate }
        set { Self.current()?.delegate = newValue }
    }

    private static func current() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }
}

/// Installs the delegate integration (DEL-01, DEL-02, DEL-06, DEL-07): reads `NottiDisableSwizzling` and,
/// when swizzling is on, swizzles `UIApplication.setDelegate:` and `UNUserNotificationCenter.setDelegate:`,
/// arms the fallback delegate for the end of launch and flips `NottiSwizzlingState.isActive`.
///
/// Entry points:
/// - `install()` is what `NottiBootstrap` sends from `+load`. It touches no UIKit object, no network, no file
///   and no `NottiRuntime`: classes are looked up by name and the adapter resolves the runtime on first use.
/// - `ensureInstalled()` is what `Notti.initialize` calls. It is the same idempotent install plus a look at
///   delegates that already exist, which `+load` cannot see.
///
/// The swizzled setters capture the swizzlers with `[weak self]`, so the process-wide instance retains the
/// method swizzler (its registry), both delegate swizzlers and the fallback assigner for the life of the
/// process.
@available(iOSApplicationExtension, unavailable)
@objc(NottiDelegateInstaller)
final class NottiDelegateInstaller: NSObject {

    /// Everything the installer touches, injected so tests use fakes and never the real `UIApplication`.
    struct Environment {
        var configuration: () -> NottiSwizzlingConfiguration
        var applicationClass: AnyClass
        var centerClass: AnyClass
        /// The app delegate that already exists, if any. Called only outside the `+load` path.
        var existingApplicationDelegate: () -> AnyObject?
        var center: NottiNotificationCenterHost
        var notificationCenter: NotificationCenter
        /// Whether launch ended before the installer could observe it (an install after launch). Called only
        /// outside the `+load` path and only while the end of launch has not been seen.
        var isLaunchFinished: () -> Bool
        var adapter: NottiPushAdapter
        var state: NottiSwizzlingState

        /// The real classes and the process-wide runtime and state. Nothing here creates an object that
        /// touches I/O: the adapter resolves `NottiRuntime.shared` on first use.
        static func production() -> Environment {
            let state = NottiSwizzlingState.shared
            return Environment(
                configuration: { NottiSwizzlingConfiguration() },
                applicationClass: UIApplication.self,
                centerClass: UNUserNotificationCenter.self,
                existingApplicationDelegate: NottiDelegateInstaller.currentApplicationDelegate,
                center: NottiCurrentNotificationCenter(),
                notificationCenter: .default,
                isLaunchFinished: NottiDelegateInstaller.applicationIsActive,
                adapter: NottiPushAdapter(runtimeProvider: { .shared }, isSwizzlingActive: { state.isActive }),
                state: state
            )
        }
    }

    private static let shared = NottiDelegateInstaller(environment: .production())

    private let environment: Environment
    private let lock = NSLock()
    private var decided = false
    private var enabled = false
    private var launchFinished = false
    private var launchObserver: NSObjectProtocol?
    private var methodSwizzler: NottiMethodSwizzler?
    private var appDelegateSwizzler: NottiAppDelegateSwizzler?
    private var centerSwizzler: NottiNotificationCenterSwizzler?
    private var fallbackAssigner: NottiFallbackDelegateAssigner?

    init(environment: Environment) {
        self.environment = environment
        super.init()
    }

    deinit {
        if let launchObserver { environment.notificationCenter.removeObserver(launchObserver) }
    }

    // MARK: - Entry points

    /// Sent by `NottiBootstrap` from `+load`. Idempotent.
    @objc static func install() {
        shared.performInstall(fromLaunchHook: true)
    }

    /// Called by `Notti.initialize`: the safety net if `+load` did not run, and the late look at delegates
    /// that exist by then. Idempotent.
    static func ensureInstalled() {
        shared.performInstall(fromLaunchHook: false)
    }

    // MARK: - Install

    /// - Parameter fromLaunchHook: true from `+load`, where no delegate can exist yet and `UIApplication`
    ///   must not be probed.
    func performInstall(fromLaunchHook: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if !decided {
            decided = true
            installFirstTime()
        }
        guard enabled else { return }

        if !fromLaunchHook {
            appDelegateSwizzler?.observe(delegate: environment.existingApplicationDelegate())
            centerSwizzler?.observe(delegate: environment.center.delegate)
            if !launchFinished, environment.isLaunchFinished() {
                launchFinished = true
            }
        }
        if launchFinished {
            fallbackAssigner?.evaluateNow()
        }
    }

    /// Runs once, with the lock held.
    private func installFirstTime() {
        let configuration = environment.configuration()
        if configuration.invalidValueWarning {
            NottiLogger.log(
                .warn,
                "Notti: \(NottiSwizzlingConfiguration.infoPlistKey) must be a Boolean; swizzling stays on",
                category: "delegates"
            )
        }
        guard configuration.isEnabled else {
            NottiLogger.log(
                .info,
                "Notti: delegate swizzling is disabled by \(NottiSwizzlingConfiguration.infoPlistKey); "
                    + "forward the delegate callbacks manually",
                category: "delegates"
            )
            return
        }
        enabled = true

        let adapter = environment.adapter
        let method = NottiMethodSwizzler()
        let app = NottiAppDelegateSwizzler(swizzler: method, adapter: adapter)
        let center = NottiNotificationCenterSwizzler(swizzler: method, adapter: adapter)
        let assigner = NottiFallbackDelegateAssigner(
            isEnabled: true,
            center: environment.center,
            notificationCenter: environment.notificationCenter,
            adapter: adapter
        )
        methodSwizzler = method
        appDelegateSwizzler = app
        centerSwizzler = center
        fallbackAssigner = assigner

        let appInstalled = app.swizzleSetDelegate(on: environment.applicationClass)
        let centerInstalled = center.swizzleSetDelegate(on: environment.centerClass)

        launchObserver = environment.notificationCenter.addObserver(
            forName: UIApplication.didFinishLaunchingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.launchDidFinish()
        }
        assigner.start()

        // Active only after both hooks are in. A failed hook was already logged at `.error` by the swizzler.
        environment.state.setActive(appInstalled && centerInstalled)
    }

    private func launchDidFinish() {
        lock.withLock {
            launchFinished = true
            if let launchObserver {
                environment.notificationCenter.removeObserver(launchObserver)
                self.launchObserver = nil
            }
        }
    }

    // MARK: - Production probes

    /// `UIApplication.shared.delegate`, read through the ObjC runtime: `UIApplication.shared` is not optional
    /// and the property is main-actor isolated, while this runs on whatever thread called `initialize`.
    private static func currentApplicationDelegate() -> AnyObject? {
        guard let application = sharedApplication() else { return nil }
        return application.perform(NSSelectorFromString("delegate"))?.takeUnretainedValue()
    }

    /// An app in the `active` state finished launching. [Provável] heuristic for an install after launch
    /// when the launch notification was missed; only trusted on the main thread, where UIKit allows the read.
    private static func applicationIsActive() -> Bool {
        guard Thread.isMainThread, let application = sharedApplication() else { return false }
        let state = (application.value(forKey: "applicationState") as? NSNumber)?.intValue
        return state == UIApplication.State.active.rawValue
    }

    private static func sharedApplication() -> AnyObject? {
        UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue()
    }
}

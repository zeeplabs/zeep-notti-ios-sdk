import ObjectiveC
import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared
#if canImport(NottiSDKBootstrap)
import NottiSDKBootstrap
#endif

/// The installer over fakes: a fake application class, a fake center class and a fake center host. Neither
/// `UIApplication` nor `UNUserNotificationCenter` is swizzled here (the process-wide hook is tested in T9).
final class NottiDelegateInstallerTests: XCTestCase {

    private typealias SetDelegateCall = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias PresentCompletion = @convention(block) (UNNotificationPresentationOptions) -> Void
    private typealias PresentCall = @convention(c) (AnyObject, Selector, AnyObject, UNNotification, PresentCompletion) -> Void

    private let setDelegateSel = NSSelectorFromString("setDelegate:")
    private let presentSel = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    private let fetchSel = NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")

    private final class FakeCenter: NottiNotificationCenterHost {
        weak var delegate: UNUserNotificationCenterDelegate?
    }

    private final class FakeHostDelegate: NSObject, UNUserNotificationCenterDelegate {}

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var sessions: [URLSession] = []
    private var logs: [(NottiLogLevel, String)] = []
    private let logLock = NSLock()
    private var savedLevel: NottiLogLevel = .error
    private var appSetterCalls = 0
    private var centerSetterCalls = 0
    private var notifications: NotificationCenter!
    private var center: FakeCenter!
    private var state: NottiSwizzlingState!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiDelegateInstallerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        logs = []
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
        runtime = makeRuntime()
        appSetterCalls = 0
        centerSetterCalls = 0
        notifications = NotificationCenter()
        center = FakeCenter()
        state = NottiSwizzlingState()
    }

    override func tearDown() {
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeRuntime() -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        return NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
    }

    private func uniqueName(_ prefix: String) -> String {
        "\(prefix)\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    /// A class with a recording `setDelegate:`.
    private func makeSetterClass(_ prefix: String, onSet: @escaping () -> Void) -> AnyClass {
        guard let cls = objc_allocateClassPair(NSObject.self, uniqueName(prefix), 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in onSet() }
        class_addMethod(cls, setDelegateSel, imp_implementationWithBlock(block), "v@:@")
        objc_registerClassPair(cls)
        return cls
    }

    private func makeUNDelegateClass() -> AnyClass {
        guard let cls = objc_allocateClassPair(NSObject.self, uniqueName("NottiFixtureUNDelegate"), 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if let proto = objc_getProtocol("UNUserNotificationCenterDelegate") {
            class_addProtocol(cls, proto)
        }
        objc_registerClassPair(cls)
        return cls
    }

    private func makeInstance(_ cls: AnyClass) -> AnyObject {
        (cls as? NSObject.Type)?.init() ?? NSObject()
    }

    private func makeNotification() -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = ["aps": ["alert": ["title": "t", "body": "b"]], "notification_id": "n-1", "delivery_id": "d-1"]
        let request = UNNotificationRequest(identifier: "req-1", content: content, trigger: nil)
        guard let notification = (UNNotification.self as NSObject.Type).init() as? UNNotification else {
            fatalError("could not allocate UNNotification")
        }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    private struct Fakes {
        let installer: NottiDelegateInstaller
        let appClass: AnyClass
        let centerClass: AnyClass
    }

    private func makeInstaller(
        info: [String: Any]? = [:],
        existingAppDelegate: AnyObject? = nil,
        launchFinished: Bool = false,
        runtimeProvider: (() -> NottiRuntime)? = nil
    ) -> Fakes {
        let appClass: AnyClass = makeSetterClass("NottiFixtureApplication") { [weak self] in self?.appSetterCalls += 1 }
        let centerClass: AnyClass = makeSetterClass("NottiFixtureCenter") { [weak self] in self?.centerSetterCalls += 1 }
        let runtime = self.runtime!
        let adapter = NottiPushAdapter(runtimeProvider: runtimeProvider ?? { runtime })
        let environment = NottiDelegateInstaller.Environment(
            configuration: { NottiSwizzlingConfiguration(infoDictionary: info) },
            applicationClass: appClass,
            centerClass: centerClass,
            existingApplicationDelegate: { existingAppDelegate },
            center: center,
            notificationCenter: notifications,
            isLaunchFinished: { launchFinished },
            adapter: adapter,
            state: state
        )
        return Fakes(installer: NottiDelegateInstaller(environment: environment), appClass: appClass, centerClass: centerClass)
    }

    private func imp(_ cls: AnyClass) -> IMP? {
        class_getMethodImplementation(cls, setDelegateSel)
    }

    private func setDelegate(on cls: AnyClass, to delegate: AnyObject?) {
        let object = makeInstance(cls)
        unsafeBitCast(object.method(for: setDelegateSel), to: SetDelegateCall.self)(object, setDelegateSel, delegate)
    }

    private func sendWillPresent(_ delegate: AnyObject) -> [UNNotificationPresentationOptions] {
        var results: [UNNotificationPresentationOptions] = []
        let completion: PresentCompletion = { results.append($0) }
        let send = unsafeBitCast(delegate.method(for: presentSel), to: PresentCall.self)
        send(delegate, presentSel, NSObject(), makeNotification(), completion)
        return results
    }

    private var storedTypes: [String] { runtime.eventStore.all().map(\.type) }

    // MARK: - State

    func test_swizzlingStateStartsInactiveAndFollowsTheSetter() {
        let fresh = NottiSwizzlingState()
        XCTAssertFalse(fresh.isActive)
        fresh.setActive(true)
        XCTAssertTrue(fresh.isActive)
        fresh.setActive(false)
        XCTAssertFalse(fresh.isActive)
    }

    // MARK: - Opt-out

    func test_optOutChangesNoSelectorAssignsNoDelegateAndLogsOneInfoLine() {
        let fakes = makeInstaller(info: [NottiSwizzlingConfiguration.infoPlistKey: true])
        let appBefore = imp(fakes.appClass)
        let centerBefore = imp(fakes.centerClass)

        fakes.installer.performInstall(fromLaunchHook: true)
        fakes.installer.performInstall(fromLaunchHook: false)
        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)

        XCTAssertEqual(imp(fakes.appClass), appBefore)
        XCTAssertEqual(imp(fakes.centerClass), centerBefore)
        XCTAssertNil(center.delegate, "the fallback is never assigned")
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(logs.filter { $0.0 == .info }.count, 1)
        XCTAssertEqual(logs.count, 1, "nothing else is logged")
    }

    func test_aNonBooleanValueKeepsSwizzlingOnAndWarnsOnce() {
        let fakes = makeInstaller(info: [NottiSwizzlingConfiguration.infoPlistKey: "YES"])
        let appBefore = imp(fakes.appClass)

        fakes.installer.performInstall(fromLaunchHook: true)
        fakes.installer.performInstall(fromLaunchHook: true)

        XCTAssertNotEqual(imp(fakes.appClass), appBefore)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(logs.filter { $0.0 == .warn }.count, 1)
    }

    // MARK: - Enabled

    func test_enabledInstallReplacesBothSettersOnceAndASecondInstallChangesNothing() {
        let fakes = makeInstaller()
        let appBefore = imp(fakes.appClass)
        let centerBefore = imp(fakes.centerClass)

        fakes.installer.performInstall(fromLaunchHook: true)
        let appAfter = imp(fakes.appClass)
        let centerAfter = imp(fakes.centerClass)
        fakes.installer.performInstall(fromLaunchHook: true)
        fakes.installer.performInstall(fromLaunchHook: false)

        XCTAssertNotEqual(appAfter, appBefore)
        XCTAssertNotEqual(centerAfter, centerBefore)
        XCTAssertEqual(imp(fakes.appClass), appAfter)
        XCTAssertEqual(imp(fakes.centerClass), centerAfter)
    }

    func test_isActiveIsTrueOnlyAfterTheInstall() {
        let fakes = makeInstaller()
        XCTAssertFalse(state.isActive)

        fakes.installer.performInstall(fromLaunchHook: true)

        XCTAssertTrue(state.isActive)
    }

    func test_theInstalledSettersKeepObservingWhileOnlyTheInstallerIsRetainedAndObserveOncePerCallback() {
        var fakes: Fakes? = makeInstaller()
        let installer = fakes!.installer
        installer.performInstall(fromLaunchHook: true)
        installer.performInstall(fromLaunchHook: false)
        let centerClass = fakes!.centerClass
        fakes = nil // the swizzlers are owned by the installer, not by the test

        let delegateClass: AnyClass = makeUNDelegateClass()
        setDelegate(on: centerClass, to: makeInstance(delegateClass))
        setDelegate(on: centerClass, to: makeInstance(delegateClass))
        let results = sendWillPresent(makeInstance(delegateClass))

        XCTAssertEqual(centerSetterCalls, 2, "the original setter still runs")
        XCTAssertEqual(results, [[.banner, .list, .sound, .badge]])
        XCTAssertEqual(storedTypes, ["received"], "one observation per callback")
        withExtendedLifetime(installer) {}
    }

    // MARK: - Launch hook path versus initialize path

    func test_theLaunchHookPathDoesNotLookForExistingDelegates() {
        let existingClass: AnyClass = makeUNDelegateClass()
        var asked = false
        let appClass: AnyClass = makeSetterClass("NottiFixtureApplication") {}
        let centerClass: AnyClass = makeSetterClass("NottiFixtureCenter") {}
        let runtime = self.runtime!
        let environment = NottiDelegateInstaller.Environment(
            configuration: { NottiSwizzlingConfiguration(infoDictionary: [:]) },
            applicationClass: appClass,
            centerClass: centerClass,
            existingApplicationDelegate: { asked = true; return self.makeInstance(existingClass) },
            center: center,
            notificationCenter: notifications,
            isLaunchFinished: { asked = true; return false },
            adapter: NottiPushAdapter(runtime: runtime),
            state: state
        )
        let installer = NottiDelegateInstaller(environment: environment)

        installer.performInstall(fromLaunchHook: true)

        XCTAssertFalse(asked, "+load must not probe UIKit")
    }

    func test_ensureInstalledObservesDelegatesThatAlreadyExist() {
        let appDelegateClass: AnyClass = makeUNDelegateClass()
        let centerDelegateClass: AnyClass = makeUNDelegateClass()
        let centerDelegate = makeInstance(centerDelegateClass)
        center.delegate = centerDelegate as? UNUserNotificationCenterDelegate
        XCTAssertNotNil(center.delegate, "the fixture class conforms to the protocol")
        let fakes = makeInstaller(existingAppDelegate: makeInstance(appDelegateClass))

        fakes.installer.performInstall(fromLaunchHook: true)
        XCTAssertFalse(appDelegateClass.instancesRespond(to: fetchSel), "+load saw nothing yet")

        fakes.installer.performInstall(fromLaunchHook: false)
        fakes.installer.performInstall(fromLaunchHook: false)

        XCTAssertTrue(appDelegateClass.instancesRespond(to: fetchSel))
        XCTAssertTrue(centerDelegateClass.instancesRespond(to: presentSel))
        XCTAssertEqual(sendWillPresent(centerDelegate).count, 1)
        XCTAssertEqual(storedTypes, ["received"], "observed once after two ensure calls")
    }

    // MARK: - Fallback delegate (D1) and the late install

    func test_theFallbackIsAssignedAtTheEndOfLaunchWhenTheHostLeftTheDelegateNil() {
        let fakes = makeInstaller()
        fakes.installer.performInstall(fromLaunchHook: true)
        XCTAssertNil(center.delegate)

        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)

        XCTAssertTrue(center.delegate is NottiNotificationCenterDelegate)
        withExtendedLifetime(fakes.installer) {}
    }

    func test_aHostDelegateSetDuringLaunchIsNeverReplaced() {
        let fakes = makeInstaller()
        fakes.installer.performInstall(fromLaunchHook: true)
        let host = FakeHostDelegate()

        center.delegate = host
        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)

        XCTAssertTrue(center.delegate === host)
        withExtendedLifetime(fakes.installer) {}
    }

    func test_anInstallAfterTheEndOfLaunchAssignsTheFallbackImmediately() {
        let fakes = makeInstaller(launchFinished: true)

        fakes.installer.performInstall(fromLaunchHook: false)

        XCTAssertTrue(center.delegate is NottiNotificationCenterDelegate, "the launch notification already fired")
        withExtendedLifetime(fakes.installer) {}
    }

    func test_anInstallAfterTheEndOfLaunchNeverOverridesAHostDelegate() {
        let host = FakeHostDelegate()
        center.delegate = host
        let fakes = makeInstaller(launchFinished: true)

        fakes.installer.performInstall(fromLaunchHook: false)

        XCTAssertTrue(center.delegate === host)
    }

    func test_aLaunchNotificationSeenByTheInstallerMakesALaterEnsureAssignImmediately() {
        let fakes = makeInstaller()
        fakes.installer.performInstall(fromLaunchHook: true)
        let host = FakeHostDelegate()
        center.delegate = host
        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        center.delegate = nil // the host cleared it after launch

        fakes.installer.performInstall(fromLaunchHook: false)

        XCTAssertTrue(center.delegate is NottiNotificationCenterDelegate, "launch is known to be over")
        withExtendedLifetime(fakes.installer) {}
    }

    // MARK: - No I/O at install

    func test_installNeverResolvesTheRuntimeAndLeavesTheIsolatedSuiteEmpty() {
        var resolved = false
        let runtime = self.runtime!
        let fakes = makeInstaller(runtimeProvider: { resolved = true; return runtime })

        fakes.installer.performInstall(fromLaunchHook: true)
        fakes.installer.performInstall(fromLaunchHook: false)
        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)

        XCTAssertFalse(resolved, "the adapter resolves the runtime only when a callback arrives")
        XCTAssertTrue(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true, "no UserDefaults write")
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty, "no network")
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
        withExtendedLifetime(fakes.installer) {}
    }

    // MARK: - Facade

    func test_initializeRunsTheInstallClosureOnEveryCallEvenWithInvalidArguments() {
        var installs = 0
        let facade = NottiFacade(runtime: runtime, dispatcher: { $0() }, installDelegates: { installs += 1 })

        facade.initialize(appId: "", clientKey: "", baseUrl: nil)
        facade.initialize(appId: "", clientKey: "key-fixture", baseUrl: nil)
        facade.initialize(appId: "app-fixture", clientKey: "", baseUrl: nil)

        XCTAssertEqual(installs, 3)
    }

    // MARK: - Launch hook (T9)

    #if canImport(NottiSDKBootstrap)
    func test_theLaunchHookRanOnceInThisProcessAndFoundTheSwiftInstaller() {
        XCTAssertEqual(NottiBootstrap.loadCount, 1, "+load runs once per process")
        XCTAssertEqual(NottiBootstrap.installCount, 1, "+load found NottiDelegateInstaller and sent install")
    }
    #endif

    func test_theInstallerClassIsReachableByTheNameTheHookUses() {
        let cls: AnyObject? = NSClassFromString("NottiDelegateInstaller")
        XCTAssertNotNil(cls)
        XCTAssertTrue((cls as? NSObject.Type)?.responds(to: NSSelectorFromString("install")) ?? false)
    }
}

#if os(macOS)
import AppKit
import ObjectiveC
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// AD-025, macOS delegate integration over an isolated runtime. Fake `NSApplicationDelegate` classes are built per
/// test with a unique name and a private `NottiMethodSwizzler` registry; `NSApplication` and
/// `UNUserNotificationCenter` are never swizzled here. Covers MAC-06..15 and MAC-18: token, failure and silent push
/// with and without each host original (forwarded once, same arguments), the double-swizzle guard, the SwiftUI
/// skip and adaptor, the manual API, the registration body, the cold-start click and a log sentinel sweep.
final class NottiAppDelegateSwizzlerMacTests: XCTestCase {

    private typealias TokenCall = @convention(c) (AnyObject, Selector, AnyObject, NSData) -> Void
    private typealias FailureCall = @convention(c) (AnyObject, Selector, AnyObject, NSError) -> Void
    private typealias RemoteCall = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary) -> Void
    private typealias SetDelegateCall = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    private let tokenSel = NSSelectorFromString("application:didRegisterForRemoteNotificationsWithDeviceToken:")
    private let failureSel = NSSelectorFromString("application:didFailToRegisterForRemoteNotificationsWithError:")
    private let remoteSel = NSSelectorFromString("application:didReceiveRemoteNotification:")
    private let fetchSel = NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")
    private let setDelegateSel = NSSelectorFromString("setDelegate:")

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var adapter: NottiPushAdapter!
    private var swizzler: NottiMethodSwizzler!
    private var swizzlingActive = false
    private var sessions: [URLSession] = []
    private var calls: [String] = []
    private var seenToken: Data?
    private var seenUserInfo: NSDictionary?
    private var logs: [(NottiLogLevel, String)] = []
    private let logLock = NSLock()
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiAppDelegateSwizzlerMacTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        calls = []
        seenToken = nil
        seenUserInfo = nil
        logs = []
        swizzlingActive = false
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
        runtime = makeRuntime()
        adapter = NottiPushAdapter(runtime: runtime, isSwizzlingActive: { [unowned self] in self.swizzlingActive })
        swizzler = NottiMethodSwizzler()
    }

    override func tearDown() {
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        adapter = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// `sdkName` nil keeps the production default under test (`macos`); `sdkVersion` empty skips that PATCH.
    private func makeRuntime(sdkName: String? = "") -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let factory: (String, String, String) -> NottiApiClient = { appId, clientKey, baseUrl in
            NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
        }
        let providers = NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) })
        if let sdkName {
            return NottiRuntime(
                defaults: defaults, providers: providers, pathMonitor: FakePathMonitor(),
                apiClientFactory: factory, sdkVersion: "", sdkName: sdkName, startObservers: false
            )
        }
        return NottiRuntime(
            defaults: defaults, providers: providers, pathMonitor: FakePathMonitor(),
            apiClientFactory: factory, sdkVersion: "", startObservers: false
        )
    }

    private func startCore(sdkName: String? = nil) {
        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid", sdkName: sdkName)
        drain()
    }

    /// Replaces the runtime (and the adapter over it) with one that keeps the production default `sdk_name`.
    private func useProductionSdkName() {
        runtime = makeRuntime(sdkName: nil)
        adapter = NottiPushAdapter(runtime: runtime, isSwizzlingActive: { false })
    }

    /// Delivers a token through a swizzled fake delegate and waits for the registration and its `PATCH`es.
    private func registerThroughASwizzledDelegate(token: Data, replies: Int) {
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        for _ in 0..<replies { StubURLProtocol.enqueue(.echoDevice()) }
        sendToken(makeInstance(cls), token)
        drain()
    }

    private func drain() {
        XCTAssertTrue(runtime.core?.waitForPendingWork(timeout: 25) ?? false, "core work queue did not drain")
    }

    private func makeSwizzler(isSwiftUI: @escaping (AnyClass) -> Bool = { _ in false }) -> NottiAppDelegateSwizzler {
        NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapter, isSwiftUIInternalDelegate: isSwiftUI)
    }

    private struct Methods: OptionSet {
        let rawValue: Int
        static let token = Methods(rawValue: 1)
        static let failure = Methods(rawValue: 2)
        static let remote = Methods(rawValue: 4)
        static let fetch = Methods(rawValue: 8)
        static let all: Methods = [.token, .failure, .remote]
    }

    /// A fake app delegate class implementing `methods`. Each original records `original:<name>` and its arguments.
    private func makeDelegateClass(_ methods: Methods, superclass: AnyClass = NSObject.self) -> AnyClass {
        let name = "NottiFixtureMacDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(superclass, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if methods.contains(.token) {
            let block: @convention(block) (AnyObject, AnyObject, NSData) -> Void = { [weak self] _, _, token in
                self?.calls.append("original:token")
                self?.seenToken = token as Data
            }
            class_addMethod(cls, tokenSel, imp_implementationWithBlock(block), "v@:@@")
        }
        if methods.contains(.failure) {
            let block: @convention(block) (AnyObject, AnyObject, NSError) -> Void = { [weak self] _, _, _ in
                self?.calls.append("original:failure")
            }
            class_addMethod(cls, failureSel, imp_implementationWithBlock(block), "v@:@@")
        }
        if methods.contains(.remote) {
            let block: @convention(block) (AnyObject, AnyObject, NSDictionary) -> Void = { [weak self] _, _, userInfo in
                self?.calls.append("original:remote")
                self?.seenUserInfo = userInfo
            }
            class_addMethod(cls, remoteSel, imp_implementationWithBlock(block), "v@:@@")
        }
        objc_registerClassPair(cls)
        return cls
    }

    private func makeInstance(_ cls: AnyClass) -> AnyObject {
        (cls as? NSObject.Type)?.init() ?? NSObject()
    }

    private func sendToken(_ object: AnyObject, _ token: Data) {
        unsafeBitCast(object.method(for: tokenSel), to: TokenCall.self)(object, tokenSel, NSObject(), token as NSData)
    }

    private func sendFailure(_ object: AnyObject, _ error: NSError) {
        unsafeBitCast(object.method(for: failureSel), to: FailureCall.self)(object, failureSel, NSObject(), error)
    }

    private func sendRemote(_ object: AnyObject, _ userInfo: [AnyHashable: Any]) {
        unsafeBitCast(object.method(for: remoteSel), to: RemoteCall.self)(object, remoteSel, NSObject(), userInfo as NSDictionary)
    }

    private func responds(_ cls: AnyClass, _ selector: Selector) -> Bool {
        class_getInstanceMethod(cls, selector) != nil
    }

    private func silentUserInfo() -> [AnyHashable: Any] {
        ["aps": ["content-available": 1], "notification_id": "n-1", "delivery_id": "d-1"]
    }

    private func visibleUserInfo() -> [AnyHashable: Any] {
        ["aps": ["alert": ["title": "Hello", "body": "World"]], "notification_id": "n-1", "delivery_id": "d-1"]
    }

    private func bodies(_ method: String) -> [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == method }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
    }

    private var capturedLogs: [(NottiLogLevel, String)] {
        logLock.withLock { logs }
    }

    private func adapterRecordingFirstUse() -> NottiPushAdapter {
        NottiPushAdapter(runtimeProvider: { [weak self] in
            self?.calls.append("adapter")
            return self?.runtime ?? NottiRuntime.shared
        })
    }

    // MARK: - Order: the adapter first, then the host's original

    func test_theAdapterHandlesTheTokenCallbackBeforeTheHostOriginal() {
        let cls = makeDelegateClass(.token)
        XCTAssertTrue(NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapterRecordingFirstUse()).swizzle(delegateClass: cls))

        sendToken(makeInstance(cls), Data([0x01]))

        XCTAssertEqual(calls, ["adapter", "original:token"])
    }

    func test_theAdapterHandlesTheFailureCallbackBeforeTheHostOriginal() {
        let cls = makeDelegateClass(.failure)
        XCTAssertTrue(NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapterRecordingFirstUse()).swizzle(delegateClass: cls))

        sendFailure(makeInstance(cls), NSError(domain: "fixture.apns", code: 1))

        XCTAssertEqual(calls, ["adapter", "original:failure"])
    }

    func test_theAdapterHandlesTheRemoteNotificationBeforeTheHostOriginal() {
        let cls = makeDelegateClass(.remote)
        XCTAssertTrue(NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapterRecordingFirstUse()).swizzle(delegateClass: cls))

        sendRemote(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(calls, ["adapter", "original:remote"])
    }

    // MARK: - All implemented: adapter once, each original once, same arguments

    func test_delegateWithAllThreeMethodsReachesTheAdapterOnceAndEachOriginalOnce() {
        startCore()
        StubURLProtocol.reset()
        let cls = makeDelegateClass(.all)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        StubURLProtocol.enqueue(.echoDevice())
        sendToken(delegate, Data([0xAB, 0xCD]))
        drain()
        sendFailure(delegate, NSError(domain: "fixture.apns", code: 3000))
        sendRemote(delegate, silentUserInfo())

        XCTAssertEqual(bodies("POST").map { $0["token"] as? String }, ["abcd"], "the adapter registered the token once")
        let errors = capturedLogs.filter { $0.0 == .error }.map(\.1)
        XCTAssertEqual(errors, ["Notti: failed to register for remote notifications - fixture.apns#3000"])
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"], "the silent push was reported once")
        XCTAssertEqual(calls, ["original:token", "original:failure", "original:remote"], "each original once")
    }

    func test_hostOriginalsReceiveTheSameArguments() {
        let cls = makeDelegateClass([.token, .remote])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        sendToken(delegate, Data([0x01, 0x02, 0x03]))
        sendRemote(delegate, silentUserInfo())

        XCTAssertEqual(seenToken, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(seenUserInfo?["notification_id"] as? String, "n-1")
        XCTAssertEqual(seenUserInfo?["delivery_id"] as? String, "d-1")
        XCTAssertNotNil((seenUserInfo?["aps"] as? [String: Any])?["content-available"])
    }

    // MARK: - Some or none implemented

    func test_delegateWithNoMethodsGetsTheSdkImplementationsAndTheRemoteNotificationIsReportedOnce() {
        startCore()
        StubURLProtocol.reset()
        let cls = makeDelegateClass([])
        XCTAssertFalse(responds(cls, tokenSel))
        XCTAssertFalse(responds(cls, remoteSel))

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        XCTAssertTrue(responds(cls, tokenSel))
        XCTAssertTrue(responds(cls, failureSel))
        XCTAssertTrue(responds(cls, remoteSel), "design S3 (unconfirmed): the SDK adds the silent-push callback")
        XCTAssertFalse(responds(cls, fetchSel), "macOS has no fetch variant to add")

        StubURLProtocol.enqueue(.echoDevice())
        sendToken(delegate, Data([0x0A]))
        drain()
        XCTAssertEqual(bodies("POST").map { $0["token"] as? String }, ["0a"])

        sendRemote(delegate, silentUserInfo())
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, [])
    }

    func test_aHostWithOnlyTheTokenCallbackStillGetsTheRemoteNotificationObservedAndKeepsItsToken() {
        let cls = makeDelegateClass(.token)

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)
        sendRemote(delegate, silentUserInfo())
        sendToken(delegate, Data([0x01]))

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, ["original:token"])
    }

    func test_aVisiblePushOnTheRemoteNotificationPathReportsNothing() {
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        sendRemote(makeInstance(cls), visibleUserInfo())

        XCTAssertTrue(runtime.eventStore.all().isEmpty, "a visible push is reported once by willPresent, not here")
    }

    // MARK: - Subclass, repeat install, SwiftUI

    func test_aSubclassOfASwizzledDelegateClassIsObservedOncePerCallback() {
        let base = makeDelegateClass(.all)
        let child = makeDelegateClass([], superclass: base)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: base))
        XCTAssertTrue(sdk.swizzle(delegateClass: child))
        sendRemote(makeInstance(child), silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, ["original:remote"])
    }

    func test_swizzlingTheSameClassTwiceChangesNothing() {
        let cls = makeDelegateClass(.all)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        sendRemote(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"], "double swizzle guard: one report")
        XCTAssertEqual(calls, ["original:remote"], "and one original call")
    }

    func test_theSwiftUIInternalDelegateWarnsOnceAndSwizzlesNothing() {
        let cls = makeDelegateClass([])
        let sdk = makeSwizzler(isSwiftUI: { $0 == cls })

        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        XCTAssertTrue(sdk.swizzle(delegateClass: cls))

        XCTAssertFalse(responds(cls, tokenSel))
        XCTAssertFalse(responds(cls, failureSel))
        XCTAssertFalse(responds(cls, remoteSel))
        XCTAssertEqual(capturedLogs.filter { $0.0 == .warn }.count, 1)
    }

    /// A fake SwiftUI-internal delegate: implements no callback and forwards every selector to `target`, the way
    /// `SwiftUI.AppDelegate` forwards to the `@NSApplicationDelegateAdaptor` object.
    private func makeForwardingDelegateClass(target: @escaping () -> AnyObject?) -> AnyClass {
        let name = "NottiFixtureMacSwiftUIDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(NSObject.self, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        let block: @convention(block) (AnyObject, Selector) -> AnyObject? = { _, _ in target() }
        class_addMethod(cls, NSSelectorFromString("forwardingTargetForSelector:"), imp_implementationWithBlock(block), "@@::")
        let responds: @convention(block) (AnyObject, Selector) -> Bool = { _, selector in
            class_respondsToSelector(cls, selector) || (target()?.responds(to: selector) ?? false)
        }
        class_addMethod(cls, NSSelectorFromString("respondsToSelector:"), imp_implementationWithBlock(responds), "B@::")
        objc_registerClassPair(cls)
        return cls
    }

    func test_theSwiftUIInternalDelegateWithAnAdaptorSwizzlesTheAdaptorClassAndLeavesSwiftUIsClassAlone() {
        let hostClass = makeDelegateClass(.token)
        let host = makeInstance(hostClass)
        let internalClass = makeForwardingDelegateClass { host }
        let swiftUIDelegate = makeInstance(internalClass)
        let sdk = NottiAppDelegateSwizzler(
            swizzler: swizzler,
            adapter: adapterRecordingFirstUse(),
            isSwiftUIInternalDelegate: { $0 == internalClass }
        )

        XCTAssertTrue(sdk.observe(delegate: swiftUIDelegate))
        sendToken(swiftUIDelegate, Data([0x01]))

        XCTAssertEqual(calls, ["adapter", "original:token"], "the token sent to SwiftUI's delegate reaches the SDK, then the host")
        XCTAssertFalse(responds(internalClass, tokenSel), "SwiftUI's own class gets no method")
        XCTAssertTrue(responds(hostClass, failureSel))
        XCTAssertTrue(responds(hostClass, remoteSel))
        XCTAssertTrue(capturedLogs.filter { $0.0 == .warn }.isEmpty, "no SwiftUI warning when an adaptor exists")
    }

    func test_theDefaultSwiftUIPredicateMatchesOnlySwiftUINamedClasses() {
        XCTAssertFalse(NottiAppDelegateSwizzler.isSwiftUIInternal(NSObject.self))
        XCTAssertFalse(NottiAppDelegateSwizzler.isSwiftUIInternal(makeDelegateClass([])))
    }

    // MARK: - NSApplication.setDelegate: (on a fake application class)

    private func makeApplicationClass(onSet: @escaping (AnyObject?) -> Void) -> AnyClass {
        let name = "NottiFixtureMacApplication\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(NSObject.self, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { _, delegate in onSet(delegate) }
        class_addMethod(cls, setDelegateSel, imp_implementationWithBlock(block), "v@:@")
        objc_registerClassPair(cls)
        return cls
    }

    func test_setDelegateHookSwizzlesTheNewDelegateClassBeforeTheOriginalSetterRuns() {
        let delegateClass = makeDelegateClass([])
        var respondedWhenSet: Bool?
        var delegatesSet = 0
        let appClass = makeApplicationClass { delegate in
            delegatesSet += 1
            if let delegate { respondedWhenSet = delegate.responds(to: self.tokenSel) }
        }
        let sdk = makeSwizzler()
        XCTAssertTrue(sdk.swizzleSetDelegate(on: appClass))

        let application = makeInstance(appClass)
        let delegate = makeInstance(delegateClass)
        unsafeBitCast(application.method(for: setDelegateSel), to: SetDelegateCall.self)(application, setDelegateSel, delegate)

        XCTAssertEqual(delegatesSet, 1, "the original setter runs once")
        XCTAssertEqual(respondedWhenSet, true, "the class was swizzled before the original setter ran")
        XCTAssertTrue(responds(delegateClass, remoteSel))
    }

    func test_theProductionApplicationClassIsNSApplicationAsAClassReferenceOnly() {
        XCTAssertTrue(NottiDelegateInstaller.applicationClass == NSApplication.self)
    }

    // MARK: - Manual API (hosts that disabled swizzling)

    func test_manualRemoteNotificationReportsASilentPushOnceWhenSwizzlingIsOff() {
        startCore()

        adapter.manualDidReceiveRemoteNotification(userInfo: silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertTrue(capturedLogs.filter { $0.0 == .warn }.isEmpty)
    }

    func test_manualRemoteNotificationIsIgnoredWithOneWarningWhileSwizzlingIsActive() {
        startCore()
        swizzlingActive = true

        adapter.manualDidReceiveRemoteNotification(userInfo: silentUserInfo())

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
        let warnings = capturedLogs.filter { $0.0 == .warn }.map(\.1)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("didReceiveRemoteNotification ignored"))
        XCTAssertFalse(warnings[0].contains("n-1"), "no value from the payload in the line")
    }

    func test_theManualAdapterCallReturnsVoidOnMacOS() {
        // Compiles only while the macOS variant has no return value (design D4, unconfirmed). The public
        // `Notti.Notifications` and ObjC variants are pinned by `PUBLIC_SURFACE.txt`.
        let result: Void = adapter.manualDidReceiveRemoteNotification(userInfo: silentUserInfo())
        XCTAssertTrue(result == ())
    }

    // MARK: - Registration and profile on macOS (literals, not the constants)

    func test_registrationBodyCarriesPlatformMacosAndTheHexTokenOnly() {
        startCore()
        registerThroughASwizzledDelegate(token: Data([0x00, 0x0F, 0xA0, 0xFF]), replies: 1)

        let posts = bodies("POST")
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?["platform"] as? String, "macos")
        XCTAssertEqual(posts.first?["token"] as? String, "000fa0ff")
        XCTAssertEqual(Set(posts.first?.keys.map { $0 } ?? []), ["token", "platform"], "no web-push keys")
    }

    func test_theProductionDefaultSdkNameIsMacosOnThePatch() {
        useProductionSdkName()
        startCore()
        registerThroughASwizzledDelegate(token: Data([0x01]), replies: 2)

        XCTAssertEqual(bodies("PATCH").compactMap { $0["sdk_name"] as? String }, ["macos"])
    }

    func test_aWrapperSdkNameWinsOverMacos() {
        useProductionSdkName()
        startCore(sdkName: "react-native")
        registerThroughASwizzledDelegate(token: Data([0x01]), replies: 2)

        XCTAssertEqual(bodies("PATCH").compactMap { $0["sdk_name"] as? String }, ["react-native"])
    }

    // MARK: - Failure logging and the sentinel sweep (MAC-12, MAC-18)

    func test_aRegistrationFailureIsLoggedAsDomainAndCodeOnly() {
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        sendFailure(
            makeInstance(cls),
            NSError(domain: "fixture.apns", code: 3000, userInfo: [NSLocalizedDescriptionKey: "sentinel-error-description https://sentinel.example.invalid/x"])
        )

        XCTAssertEqual(
            capturedLogs.filter { $0.0 == .error }.map(\.1),
            ["Notti: failed to register for remote notifications - fixture.apns#3000"]
        )
    }

    func test_noLogLineAtVerboseCarriesATokenAnErrorDescriptionOrAPayloadValue() {
        startCore()
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        StubURLProtocol.enqueue(.echoDevice())
        sendToken(delegate, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        drain()
        sendFailure(delegate, NSError(domain: "fixture.apns", code: 1, userInfo: [NSLocalizedDescriptionKey: "sentinel-error-description"]))
        sendRemote(delegate, [
            "aps": ["content-available": 1], "notification_id": "sentinel-notification", "delivery_id": "sentinel-delivery",
            "link": "https://sentinel.example.invalid/secret"
        ])
        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["aps": ["alert": ["title": "sentinel-title", "body": "sentinel-body"]],
                       "notification_id": "sentinel-notification", "delivery_id": "sentinel-delivery"],
            identifier: "sentinel-request"
        )
        let described = [NSLocalizedDescriptionKey: "sentinel-error-description"]
        adapter.manualDidFail(error: NSError(domain: "fixture.apns", code: 2, userInfo: described))
        drain()

        let sentinels = ["deadbeef", "sentinel", "example.invalid"]
        for (_, line) in capturedLogs {
            for sentinel in sentinels {
                XCTAssertFalse(line.lowercased().contains(sentinel), "\(sentinel) leaked into: \(line)")
            }
        }
    }

    // MARK: - No application is created by a library call (MAC-06)

    func test_theLiveTokenProviderNeverInstantiatesAnApplicationWhenThereIsNone() throws {
        try XCTSkipIf(NSApp != nil, "an NSApplication already exists in this test process")
        let providers = NottiPlatformProviders.live()
        let done = expectation(description: "main hop ran")

        providers.tokenProvider { _ in XCTFail("the token callback is never called synchronously") }
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertNil(NSApp, "registerForRemoteNotifications must not create NSApplication.shared")
    }

    // MARK: - The cold-start click (MAC-14)

    func test_aClickHeldByTheBufferIsReplayedOnceThroughTakeInitialClick() {
        startCore()

        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: visibleUserInfo(),
            identifier: "req-1"
        )

        let click = runtime.eventBuffer.takeInitialClick()
        XCTAssertEqual(click?["title"] as? String, "Hello")
        XCTAssertNil(runtime.eventBuffer.takeInitialClick(), "replayed once")
    }
}
#endif

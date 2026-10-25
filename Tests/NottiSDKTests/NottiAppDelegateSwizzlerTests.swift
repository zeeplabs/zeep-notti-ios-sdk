import ObjectiveC
import UIKit
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// Fake app delegates and a fake application class, each built per test with a unique name and a private
/// `NottiMethodSwizzler` registry. `UIApplication` itself is never swizzled here.
final class NottiAppDelegateSwizzlerTests: XCTestCase {

    private typealias TokenCall = @convention(c) (AnyObject, Selector, AnyObject, NSData) -> Void
    private typealias FailureCall = @convention(c) (AnyObject, Selector, AnyObject, NSError) -> Void
    private typealias Completion = @convention(block) (UIBackgroundFetchResult) -> Void
    private typealias FetchCall = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary, Completion) -> Void
    private typealias FetchBlock = @convention(block) (AnyObject, AnyObject, NSDictionary, @escaping Completion) -> Void
    private typealias LegacyCall = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary) -> Void
    private typealias SetDelegateCall = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    private let tokenSel = NSSelectorFromString("application:didRegisterForRemoteNotificationsWithDeviceToken:")
    private let failureSel = NSSelectorFromString("application:didFailToRegisterForRemoteNotificationsWithError:")
    private let fetchSel = NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")
    private let legacySel = NSSelectorFromString("application:didReceiveRemoteNotification:")
    private let setDelegateSel = NSSelectorFromString("setDelegate:")

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var adapter: NottiPushAdapter!
    private var swizzler: NottiMethodSwizzler!
    private var sessions: [URLSession] = []
    private var calls: [String] = []
    private var logs: [(NottiLogLevel, String)] = []
    private let logLock = NSLock()
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiAppDelegateSwizzlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        calls = []
        logs = []
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
        runtime = makeRuntime()
        adapter = NottiPushAdapter(runtime: runtime)
        swizzler = NottiMethodSwizzler()
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

    private func startCore() {
        StubURLProtocol.enqueue(.echoDevice())
        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        drain()
        StubURLProtocol.reset()
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
        static let fetch = Methods(rawValue: 4)
        static let legacy = Methods(rawValue: 8)
        static let all: Methods = [.token, .failure, .fetch]
    }

    /// A fake app delegate class implementing `methods`. Each original records `original:<name>`.
    private func makeDelegateClass(_ methods: Methods, superclass: AnyClass = NSObject.self) -> AnyClass {
        let name = "NottiFixtureDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(superclass, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if methods.contains(.token) {
            let block: @convention(block) (AnyObject, AnyObject, NSData) -> Void = { [weak self] _, _, _ in
                self?.calls.append("original:token")
            }
            class_addMethod(cls, tokenSel, imp_implementationWithBlock(block), "v@:@@")
        }
        if methods.contains(.failure) {
            let block: @convention(block) (AnyObject, AnyObject, NSError) -> Void = { [weak self] _, _, _ in
                self?.calls.append("original:failure")
            }
            class_addMethod(cls, failureSel, imp_implementationWithBlock(block), "v@:@@")
        }
        if methods.contains(.fetch) {
            let block: FetchBlock = { [weak self] _, _, _, completion in
                self?.calls.append("original:fetch")
                completion(.newData)
            }
            class_addMethod(cls, fetchSel, imp_implementationWithBlock(block), "v@:@@@?")
        }
        if methods.contains(.legacy) {
            let block: @convention(block) (AnyObject, AnyObject, NSDictionary) -> Void = { [weak self] _, _, _ in
                self?.calls.append("original:legacy")
            }
            class_addMethod(cls, legacySel, imp_implementationWithBlock(block), "v@:@@")
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

    /// Returns every result the completion handler received.
    @discardableResult
    private func sendFetch(_ object: AnyObject, _ userInfo: [AnyHashable: Any]) -> [UIBackgroundFetchResult] {
        var results: [UIBackgroundFetchResult] = []
        let completion: Completion = { results.append($0) }
        let send = unsafeBitCast(object.method(for: fetchSel), to: FetchCall.self)
        send(object, fetchSel, NSObject(), userInfo as NSDictionary, completion)
        return results
    }

    private func responds(_ cls: AnyClass, _ selector: Selector) -> Bool {
        class_getInstanceMethod(cls, selector) != nil
    }

    private func silentUserInfo() -> [AnyHashable: Any] {
        ["aps": ["content-available": 1], "notification_id": "n-1", "delivery_id": "d-1"]
    }

    private var postBodies: [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "POST" }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
    }

    private var capturedLogs: [(NottiLogLevel, String)] {
        logLock.withLock { logs }
    }

    // MARK: - Order (DEL-03): the adapter first, then the host's original

    /// A fresh adapter resolves its runtime on first use, so the provider call marks the moment the SDK
    /// handles the callback. Each callback gets its own adapter and class.
    private func adapterRecordingFirstUse() -> NottiPushAdapter {
        NottiPushAdapter(runtimeProvider: { [weak self] in
            self?.calls.append("adapter")
            return self?.runtime ?? NottiRuntime.shared
        })
    }

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

    func test_theAdapterHandlesTheFetchCallbackBeforeTheHostOriginal() {
        let cls = makeDelegateClass(.fetch)
        XCTAssertTrue(NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapterRecordingFirstUse()).swizzle(delegateClass: cls))

        _ = sendFetch(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(calls, ["adapter", "original:fetch"])
    }

    // MARK: - All three implemented

    func test_delegateWithAllThreeMethodsReachesTheAdapterOnceAndEachOriginalOnce() {
        startCore()
        let cls = makeDelegateClass(.all)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        StubURLProtocol.enqueue(.echoDevice())
        sendToken(delegate, Data([0xAB, 0xCD]))
        drain()
        sendFailure(delegate, NSError(domain: "fixture.apns", code: 3000))
        let results = sendFetch(delegate, silentUserInfo())

        XCTAssertEqual(postBodies.map { $0["token"] as? String }, ["abcd"])
        let errors = capturedLogs.filter { $0.0 == .error }.map(\.1)
        XCTAssertEqual(errors, ["Notti: failed to register for remote notifications - fixture.apns#3000"])
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, ["original:token", "original:failure", "original:fetch"])
        XCTAssertEqual(results, [.newData], "only the host completes, once")
    }

    func test_hostOriginalReceivesTheSameArguments() {
        var seenToken: Data?
        let cls = makeDelegateClass([])
        let block: @convention(block) (AnyObject, AnyObject, NSData) -> Void = { _, _, token in seenToken = token as Data }
        class_addMethod(cls, tokenSel, imp_implementationWithBlock(block), "v@:@@")

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        sendToken(makeInstance(cls), Data([0x01, 0x02, 0x03]))

        XCTAssertEqual(seenToken, Data([0x01, 0x02, 0x03]))
    }

    // MARK: - None implemented

    func test_delegateWithNoMethodsGetsTheSdkImplementationsAndTheFetchVariantCompletesOnceWithNoData() {
        startCore()
        let cls = makeDelegateClass([])
        XCTAssertFalse(responds(cls, tokenSel))

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        XCTAssertTrue(responds(cls, tokenSel))
        XCTAssertTrue(responds(cls, failureSel))
        XCTAssertTrue(responds(cls, fetchSel))

        StubURLProtocol.enqueue(.echoDevice())
        sendToken(delegate, Data([0x0A]))
        drain()
        XCTAssertEqual(postBodies.map { $0["token"] as? String }, ["0a"])

        let results = sendFetch(delegate, silentUserInfo())
        XCTAssertEqual(results, [.noData])
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
    }

    func test_fetchVariantOnAVisiblePushCompletesWithNoDataAndReportsNothing() {
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let results = sendFetch(makeInstance(cls), ["aps": ["alert": "fixture"], "notification_id": "n-1", "delivery_id": "d-1"])

        XCTAssertEqual(results, [.noData])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - Legacy only (DEL-16)

    func test_delegateWithOnlyTheLegacyMethodDoesNotGetTheFetchVariantAndKeepsItsLegacyMethod() {
        let cls = makeDelegateClass(.legacy)

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        XCTAssertFalse(responds(cls, fetchSel), "adding it would make UIKit stop calling the legacy method")
        XCTAssertTrue(responds(cls, legacySel))
        let delegate = makeInstance(cls)
        unsafeBitCast(delegate.method(for: legacySel), to: LegacyCall.self)(delegate, legacySel, NSObject(), [:] as NSDictionary)
        XCTAssertEqual(calls, ["original:legacy"])
        // The token and failure callbacks are still observed.
        XCTAssertTrue(responds(cls, tokenSel))
        XCTAssertTrue(responds(cls, failureSel))
    }

    func test_delegateWithBothLegacyAndFetchMethodsSwizzlesTheFetchVariant() {
        let cls = makeDelegateClass([.legacy, .fetch])

        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let results = sendFetch(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(calls, ["original:fetch"])
        XCTAssertEqual(results, [.newData])
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
    }

    // MARK: - Subclass, repeat install, SwiftUI

    func test_aSubclassOfASwizzledDelegateClassIsObservedOncePerCallback() {
        let base = makeDelegateClass(.all)
        let child = makeDelegateClass([], superclass: base)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: base))
        XCTAssertTrue(sdk.swizzle(delegateClass: child))
        let results = sendFetch(makeInstance(child), silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, ["original:fetch"])
        XCTAssertEqual(results, [.newData])
    }

    func test_swizzlingTheSameClassTwiceChangesNothing() {
        let cls = makeDelegateClass(.all)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        sendFetch(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
        XCTAssertEqual(calls, ["original:fetch"])
    }

    func test_theSwiftUIInternalDelegateWarnsOnceAndSwizzlesNothing() {
        let cls = makeDelegateClass([])
        let sdk = makeSwizzler(isSwiftUI: { $0 == cls })

        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        XCTAssertTrue(sdk.swizzle(delegateClass: cls))

        XCTAssertFalse(responds(cls, tokenSel))
        XCTAssertFalse(responds(cls, failureSel))
        XCTAssertFalse(responds(cls, fetchSel))
        XCTAssertEqual(capturedLogs.filter { $0.0 == .warn }.count, 1)
    }

    /// A fake SwiftUI-internal delegate: implements no callback and forwards every selector to `target`,
    /// the way `SwiftUI.AppDelegate` forwards to the `@UIApplicationDelegateAdaptor` object.
    private func makeForwardingDelegateClass(target: @escaping () -> AnyObject?) -> AnyClass {
        let name = "NottiFixtureSwiftUIDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
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
        XCTAssertTrue(responds(hostClass, fetchSel))
        XCTAssertTrue(capturedLogs.filter { $0.0 == .warn }.isEmpty, "no SwiftUI warning when an adaptor exists")
    }

    func test_setDelegateHookSwizzlesTheAdaptorClassBeforeTheOriginalSetterRuns() {
        let hostClass = makeDelegateClass([])
        let host = makeInstance(hostClass)
        let internalClass = makeForwardingDelegateClass { host }
        var respondedWhenSet: Bool?
        let appClass = makeApplicationClass { delegate in respondedWhenSet = delegate?.responds(to: self.tokenSel) }
        let sdk = makeSwizzler(isSwiftUI: { $0 == internalClass })
        XCTAssertTrue(sdk.swizzleSetDelegate(on: appClass))

        let application = makeInstance(appClass)
        let setter = unsafeBitCast(application.method(for: setDelegateSel), to: SetDelegateCall.self)
        setter(application, setDelegateSel, makeInstance(internalClass))

        XCTAssertEqual(respondedWhenSet, true, "SwiftUI's delegate answers through the adaptor, already swizzled")
        XCTAssertTrue(responds(hostClass, tokenSel))
        XCTAssertFalse(responds(internalClass, tokenSel))
    }

    func test_theSwiftUIInternalDelegateWithNoUsableForwardingTargetWarnsOnceAndSwizzlesNothing() {
        // Three ways to have no adaptor: no target, another SwiftUI object, and the delegate itself.
        let otherInternal = makeInstance(makeDelegateClass([]))
        let noTarget = makeForwardingDelegateClass { nil }
        let swiftUITarget = makeForwardingDelegateClass { otherInternal }
        var selfInstance: AnyObject?
        let selfTarget = makeForwardingDelegateClass { selfInstance }
        selfInstance = makeInstance(selfTarget)
        let internalClasses: [AnyClass] = [noTarget, swiftUITarget, type(of: otherInternal), selfTarget]
        let sdk = makeSwizzler(isSwiftUI: { cls in internalClasses.contains { $0 == cls } })

        XCTAssertTrue(sdk.observe(delegate: makeInstance(noTarget)))
        XCTAssertTrue(sdk.observe(delegate: makeInstance(swiftUITarget)))
        XCTAssertTrue(sdk.observe(delegate: selfInstance))

        for cls in internalClasses {
            XCTAssertFalse(responds(cls, tokenSel), NSStringFromClass(cls))
        }
        XCTAssertEqual(capturedLogs.filter { $0.0 == .warn }.count, 1)
    }

    func test_theDefaultSwiftUIPredicateMatchesOnlySwiftUINamedClasses() {
        XCTAssertFalse(NottiAppDelegateSwizzler.isSwiftUIInternal(NSObject.self))
        XCTAssertFalse(NottiAppDelegateSwizzler.isSwiftUIInternal(makeDelegateClass([])))
    }

    // MARK: - UIApplication.setDelegate:

    /// A fake application class whose `setDelegate:` records the call and whether the delegate class was
    /// already swizzled at that moment.
    private func makeApplicationClass(
        onSet: @escaping (AnyObject?) -> Void
    ) -> AnyClass {
        let name = "NottiFixtureApplication\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
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
        XCTAssertTrue(responds(delegateClass, fetchSel))
    }

    func test_setDelegateHookIgnoresNilAndDoesNotGrowTheChainOnRepeatedAssignments() {
        let delegateClass = makeDelegateClass(.all)
        var delegatesSet = 0
        let appClass = makeApplicationClass { _ in delegatesSet += 1 }
        let sdk = makeSwizzler()
        XCTAssertTrue(sdk.swizzleSetDelegate(on: appClass))
        XCTAssertTrue(sdk.swizzleSetDelegate(on: appClass), "second install is a no-op")

        let application = makeInstance(appClass)
        let setter = unsafeBitCast(application.method(for: setDelegateSel), to: SetDelegateCall.self)
        let delegate = makeInstance(delegateClass)
        setter(application, setDelegateSel, nil)
        setter(application, setDelegateSel, delegate)
        setter(application, setDelegateSel, delegate)
        setter(application, setDelegateSel, makeInstance(delegateClass))
        sendFetch(delegate, silentUserInfo())

        XCTAssertEqual(delegatesSet, 4)
        XCTAssertEqual(calls, ["original:fetch"])
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
    }

    // MARK: - Isa-swizzled delegates (PRF-03)
    //
    // Swift's `type(of:)` on an Objective-C object answers `-class`, so a dynamic subclass that hides itself
    // behind `-class` (GoogleUtilities' app delegate proxy, KVO) resolves to the host class, which the
    // registry already holds: a late `observe` adds nothing. These tests pin that.

    /// A fake GoogleUtilities/KVO-style proxy: a dynamic subclass of the object's class that owns `selectors`
    /// with the implementations the class had at that moment (it calls the captured original), and whose
    /// `-class` answers the original class. The object is isa-swizzled to it.
    @discardableResult
    private func isaSwizzle(_ object: AnyObject, owning selectors: [Selector]) -> AnyClass {
        let original: AnyClass = type(of: object)
        let name = "NottiFixtureProxy\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let proxy = objc_allocateClassPair(original, name, 0) else {
            XCTFail("could not allocate fixture proxy class")
            return original
        }
        for selector in selectors {
            guard let method = class_getInstanceMethod(original, selector) else { continue }
            class_addMethod(proxy, selector, method_getImplementation(method), method_getTypeEncoding(method))
        }
        let classBlock: @convention(block) (AnyObject) -> AnyClass = { _ in original }
        class_addMethod(proxy, NSSelectorFromString("class"), imp_implementationWithBlock(classBlock), "#@:")
        objc_registerClassPair(proxy)
        object_setClass(object, proxy)
        return proxy
    }

    private var failureLogCount: Int {
        capturedLogs.filter { $0.0 == .error && $0.1.contains("failed to register for remote notifications") }.count
    }

    /// The premise of the tests below: `observe(delegate:)` reads `type(of:)`, which answers the hidden class,
    /// not the isa class. If a Swift release changes that, the dynamic subclass would be swizzled too.
    func test_typeOfAnswersTheClassAnIsaSwizzlingSdkHides() {
        let cls = makeDelegateClass(.all)
        let delegate = makeInstance(cls)
        let proxy = isaSwizzle(delegate, owning: [failureSel])

        XCTAssertTrue(object_getClass(delegate) == proxy, "the isa class is the dynamic subclass")
        XCTAssertTrue(type(of: delegate) == cls, "type(of:) answers -class")
    }

    func test_aDelegateIsaSwizzledAfterTheSdkIsObservedOncePerCallback() {
        let cls = makeDelegateClass(.all)
        let delegate = makeInstance(cls)
        let sdk = makeSwizzler()
        XCTAssertTrue(sdk.observe(delegate: delegate), "the setDelegate: hook")

        isaSwizzle(delegate, owning: [tokenSel, failureSel, fetchSel])
        XCTAssertTrue(sdk.observe(delegate: delegate), "the late look after the other SDK")
        sendFailure(delegate, NSError(domain: "fixture.apns", code: 1))
        let results = sendFetch(delegate, silentUserInfo())

        XCTAssertEqual(failureLogCount, 1, "the adapter saw the failure once")
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"], "one received, not two")
        XCTAssertEqual(calls, ["original:failure", "original:fetch"], "each host original once")
        XCTAssertEqual(results, [.newData])
    }

    func test_anIsaSwizzledSwiftUIInternalDelegateStillTakesTheAdaptorPath() {
        let hostClass = makeDelegateClass(.token)
        let host = makeInstance(hostClass)
        let internalClass = makeForwardingDelegateClass { host }
        let swiftUIDelegate = makeInstance(internalClass)
        let proxy = isaSwizzle(swiftUIDelegate, owning: [])
        let sdk = NottiAppDelegateSwizzler(
            swizzler: swizzler,
            adapter: adapterRecordingFirstUse(),
            isSwiftUIInternalDelegate: { $0 == internalClass }
        )

        XCTAssertTrue(sdk.observe(delegate: swiftUIDelegate))
        sendToken(swiftUIDelegate, Data([0x01]))

        XCTAssertEqual(calls, ["adapter", "original:token"])
        XCTAssertFalse(responds(proxy, tokenSel), "neither SwiftUI's class nor the proxy gets a method")
        XCTAssertTrue(capturedLogs.filter { $0.0 == .warn }.isEmpty)
    }

    func test_observingAnExistingDelegateSwizzlesItsClassDirectly() {
        let cls = makeDelegateClass(.all)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.observe(delegate: nil))
        XCTAssertTrue(sdk.observe(delegate: makeInstance(cls)))
        sendFetch(makeInstance(cls), silentUserInfo())

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["received"])
    }
}

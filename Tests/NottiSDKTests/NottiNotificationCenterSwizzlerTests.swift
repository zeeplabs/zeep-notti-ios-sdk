import ObjectiveC
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// Fake UN delegates and a fake center class, each built per test with a unique name and a private
/// `NottiMethodSwizzler` registry. `UNUserNotificationCenter` itself is never swizzled here.
final class NottiNotificationCenterSwizzlerTests: XCTestCase {

    typealias PresentCompletion = @convention(block) (UNNotificationPresentationOptions) -> Void
    typealias ResponseCompletion = @convention(block) () -> Void
    private typealias PresentCall = @convention(c) (AnyObject, Selector, AnyObject, UNNotification, PresentCompletion) -> Void
    private typealias ResponseCall =
        @convention(c) (AnyObject, Selector, AnyObject, UNNotificationResponse, ResponseCompletion) -> Void
    private typealias PresentBlock = @convention(block) (AnyObject, AnyObject, UNNotification, @escaping PresentCompletion) -> Void
    private typealias ResponseBlock =
        @convention(block) (AnyObject, AnyObject, UNNotificationResponse, @escaping ResponseCompletion) -> Void
    private typealias SetDelegateCall = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    let presentSel = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    let responseSel = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
    private let setDelegateSel = NSSelectorFromString("setDelegate:")
    private let allOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]

    var suiteName: String!
    var defaults: UserDefaults!
    var runtime: NottiRuntime!
    var adapter: NottiPushAdapter!
    var swizzler: NottiMethodSwizzler!
    var sessions: [URLSession] = []
    var calls: [String] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiNotificationCenterSwizzlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        calls = []
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

    func makeSwizzler() -> NottiNotificationCenterSwizzler {
        NottiNotificationCenterSwizzler(swizzler: swizzler, adapter: adapter)
    }

    /// `UNNotification` / `UNNotificationResponse` have no public initializer; allocate and set via KVC
    /// (same approach as the RN tests). Only the properties the swizzler reads are set.
    func makeNotification(userInfo: [AnyHashable: Any], identifier: String = "req-1") -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        guard let notification = (UNNotification.self as NSObject.Type).init() as? UNNotification else {
            fatalError("could not allocate UNNotification")
        }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    func makeResponse(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        identifier: String = "req-1"
    ) -> UNNotificationResponse {
        guard let response = (UNNotificationResponse.self as NSObject.Type).init() as? UNNotificationResponse else {
            fatalError("could not allocate UNNotificationResponse")
        }
        response.setValue(makeNotification(userInfo: userInfo, identifier: identifier), forKey: "notification")
        response.setValue(actionIdentifier, forKey: "actionIdentifier")
        return response
    }

    func nottiUserInfo(notificationId: String? = "n-1", deliveryId: String? = "d-1") -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Hello", "body": "World"]]]
        if let notificationId = notificationId { userInfo["notification_id"] = notificationId }
        if let deliveryId = deliveryId { userInfo["delivery_id"] = deliveryId }
        return userInfo
    }

    var storedTypes: [String] {
        runtime.eventStore.all().map(\.type)
    }

    struct Methods: OptionSet {
        let rawValue: Int
        static let willPresent = Methods(rawValue: 1)
        static let didReceive = Methods(rawValue: 2)
    }

    /// A fake delegate class. The host's `willPresent` completes with `.sound`, its `didReceive` with no
    /// arguments, and both record `original:<name>`.
    func makeDelegateClass(_ methods: Methods, superclass: AnyClass = NSObject.self) -> AnyClass {
        let name = "NottiFixtureNotificationDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(superclass, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if methods.contains(.willPresent) {
            let block: PresentBlock = { [weak self] _, _, _, completion in
                self?.calls.append("original:willPresent")
                completion(.sound)
            }
            class_addMethod(cls, presentSel, imp_implementationWithBlock(block), "v@:@@@?")
        }
        if methods.contains(.didReceive) {
            let block: ResponseBlock = { [weak self] _, _, _, completion in
                self?.calls.append("original:didReceive")
                completion()
            }
            class_addMethod(cls, responseSel, imp_implementationWithBlock(block), "v@:@@@?")
        }
        objc_registerClassPair(cls)
        return cls
    }

    func makeInstance(_ cls: AnyClass) -> AnyObject {
        (cls as? NSObject.Type)?.init() ?? NSObject()
    }

    /// Returns every option set the completion received.
    @discardableResult
    func sendWillPresent(_ delegate: AnyObject, _ userInfo: [AnyHashable: Any]) -> [UNNotificationPresentationOptions] {
        var results: [UNNotificationPresentationOptions] = []
        let completion: PresentCompletion = { results.append($0) }
        let send = unsafeBitCast(delegate.method(for: presentSel), to: PresentCall.self)
        send(delegate, presentSel, NSObject(), makeNotification(userInfo: userInfo), completion)
        return results
    }

    /// Returns how many times the completion ran.
    @discardableResult
    func sendDidReceive(
        _ delegate: AnyObject,
        _ userInfo: [AnyHashable: Any],
        action: String = UNNotificationDefaultActionIdentifier
    ) -> Int {
        var completions = 0
        let completion: ResponseCompletion = { completions += 1 }
        let send = unsafeBitCast(delegate.method(for: responseSel), to: ResponseCall.self)
        send(delegate, responseSel, NSObject(), makeResponse(userInfo: userInfo, actionIdentifier: action), completion)
        return completions
    }

    func responds(_ cls: AnyClass, _ selector: Selector) -> Bool {
        class_getInstanceMethod(cls, selector) != nil
    }

    // MARK: - willPresent

    func test_whenTheHostImplementsWillPresentTheHostCompletionReachesTheOSAndTheSdkNeverCallsIt() {
        let cls = makeDelegateClass(.willPresent)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let results = sendWillPresent(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(results, [.sound], "one completion, with the host's options")
        XCTAssertEqual(calls, ["original:willPresent"])
        XCTAssertEqual(storedTypes, ["received"], "still reported")
    }

    func test_whenTheHostLacksWillPresentANottiPushCompletesOnceWithTheD2Options() {
        let cls = makeDelegateClass([])
        XCTAssertFalse(responds(cls, presentSel))
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let results = sendWillPresent(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(results, [allOptions])
        XCTAssertEqual(storedTypes, ["received"])
    }

    func test_whenTheHostLacksWillPresentOtherNotificationsCompleteOnceWithNoOptionsAndAreNotReported() {
        let cls = makeDelegateClass([])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        let local = sendWillPresent(delegate, ["notification_id": "n-1", "delivery_id": "d-1"])
        let otherSdk = sendWillPresent(delegate, nottiUserInfo(notificationId: nil))

        XCTAssertEqual(local, [[]])
        XCTAssertEqual(otherSdk, [[]])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_aLocalNotificationIsForwardedUntouchedToTheHostAndNotReported() {
        let cls = makeDelegateClass(.willPresent)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let results = sendWillPresent(makeInstance(cls), ["notification_id": "n-1", "delivery_id": "d-1"])

        XCTAssertEqual(results, [.sound])
        XCTAssertEqual(calls, ["original:willPresent"])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - didReceive

    func test_didReceiveCompletesOnceByTheHostWhenItImplementsTheMethod() {
        let cls = makeDelegateClass(.didReceive)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let completions = sendDidReceive(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(calls, ["original:didReceive"])
        XCTAssertEqual(storedTypes, ["opened", "clicked"])
    }

    func test_didReceiveCompletesOnceBySdkWhenTheHostLacksTheMethod() {
        let cls = makeDelegateClass([])
        XCTAssertFalse(responds(cls, responseSel))
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        let completions = sendDidReceive(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(storedTypes, ["opened", "clicked"])
    }

    func test_didReceiveForALocalNotificationOrADismissIsForwardedAndNotReported() {
        let cls = makeDelegateClass(.didReceive)
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))
        let delegate = makeInstance(cls)

        XCTAssertEqual(sendDidReceive(delegate, ["notification_id": "n-1", "delivery_id": "d-1"]), 1)
        XCTAssertEqual(sendDidReceive(delegate, nottiUserInfo(), action: UNNotificationDismissActionIdentifier), 1)

        XCTAssertEqual(calls, ["original:didReceive", "original:didReceive"])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
    }

    // MARK: - Idempotency, stacking, subclass

    func test_swizzlingTheSameClassTwiceKeepsOneObservationPerCallback() {
        let cls = makeDelegateClass([.willPresent, .didReceive])
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        XCTAssertTrue(sdk.swizzle(delegateClass: cls))
        sendWillPresent(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(storedTypes, ["received"])
        XCTAssertEqual(calls, ["original:willPresent"])
    }

    func test_aSubclassOfASwizzledDelegateClassIsObservedOnce() {
        let base = makeDelegateClass([.willPresent, .didReceive])
        let child = makeDelegateClass([], superclass: base)
        let sdk = makeSwizzler()

        XCTAssertTrue(sdk.swizzle(delegateClass: base))
        XCTAssertTrue(sdk.swizzle(delegateClass: child))
        sendWillPresent(makeInstance(child), nottiUserInfo())

        XCTAssertEqual(storedTypes, ["received"])
        XCTAssertEqual(calls, ["original:willPresent"])
    }

    func test_anotherSwizzlerStackedOnTopCallsEveryOriginalOnce() {
        let cls = makeDelegateClass([.willPresent, .didReceive])
        XCTAssertTrue(makeSwizzler().swizzle(delegateClass: cls))

        // A second SDK swizzling the same selector with its own registry, chaining to what it found.
        let other = NottiMethodSwizzler()
        let selector = presentSel
        XCTAssertTrue(
            other.swizzle(cls, selector, typeEncoding: "v@:@@@?") { [weak self] previous in
                let original = previous.map { unsafeBitCast($0, to: PresentCall.self) }
                let block: PresentBlock = { object, center, notification, completion in
                    self?.calls.append("other")
                    original?(object, selector, center, notification, completion)
                }
                return block
            }
        )
        let results = sendWillPresent(makeInstance(cls), nottiUserInfo())

        XCTAssertEqual(calls, ["other", "original:willPresent"])
        XCTAssertEqual(results, [.sound])
        XCTAssertEqual(storedTypes, ["received"], "the SDK layer ran once underneath")
    }

    // MARK: - UNUserNotificationCenter.setDelegate:

    private func makeCenterClass(onSet: @escaping (AnyObject?) -> Void) -> AnyClass {
        let name = "NottiFixtureCenter\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
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
        var setterRuns = 0
        let centerClass = makeCenterClass { delegate in
            setterRuns += 1
            if let delegate { respondedWhenSet = delegate.responds(to: self.presentSel) }
        }
        let sdk = makeSwizzler() // the setter block holds it weakly, so keep it alive
        XCTAssertTrue(sdk.swizzleSetDelegate(on: centerClass))

        let center = makeInstance(centerClass)
        let setter = unsafeBitCast(center.method(for: setDelegateSel), to: SetDelegateCall.self)
        setter(center, setDelegateSel, makeInstance(delegateClass))

        XCTAssertEqual(setterRuns, 1)
        XCTAssertEqual(respondedWhenSet, true)
        XCTAssertTrue(responds(delegateClass, responseSel))
    }

    func test_swappingTheDelegateRepeatedlyDoesNotGrowTheChain() {
        let classA = makeDelegateClass([.willPresent, .didReceive])
        let classB = makeDelegateClass([.willPresent, .didReceive])
        let centerClass = makeCenterClass { _ in }
        let sdk = makeSwizzler()
        XCTAssertTrue(sdk.swizzleSetDelegate(on: centerClass))
        XCTAssertTrue(sdk.swizzleSetDelegate(on: centerClass), "second install is a no-op")

        let center = makeInstance(centerClass)
        let setter = unsafeBitCast(center.method(for: setDelegateSel), to: SetDelegateCall.self)
        setter(center, setDelegateSel, nil)
        let delegateA = makeInstance(classA)
        let delegateB = makeInstance(classB)
        for delegate in [delegateA, delegateB, delegateA, delegateB, delegateA] {
            setter(center, setDelegateSel, delegate)
        }
        sendWillPresent(delegateA, nottiUserInfo())
        sendWillPresent(delegateB, nottiUserInfo(notificationId: "n-2", deliveryId: "d-2"))

        XCTAssertEqual(storedTypes, ["received", "received"], "one observation per callback on each class")
        XCTAssertEqual(calls, ["original:willPresent", "original:willPresent"])
    }
}

import ObjectiveC
import UIKit
import UserNotifications
import XCTest

/// Fakes for driving the swizzled delegate paths without the real `UIApplication` or
/// `UNUserNotificationCenter`: unique fixture classes, `UNNotification` values built by KVC, a sender for each
/// callback, and an opener spy.
enum DelegateFixtures {

    typealias PresentCompletion = @convention(block) (UNNotificationPresentationOptions) -> Void
    typealias ResponseCompletion = @convention(block) () -> Void
    typealias FetchCompletion = @convention(block) (UIBackgroundFetchResult) -> Void
    private typealias PresentCall = @convention(c) (AnyObject, Selector, AnyObject, UNNotification, PresentCompletion) -> Void
    private typealias ResponseCall = @convention(c) (AnyObject, Selector, AnyObject, UNNotificationResponse, ResponseCompletion) -> Void
    private typealias FetchCall = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary, FetchCompletion) -> Void
    private typealias TokenCall = @convention(c) (AnyObject, Selector, AnyObject, NSData) -> Void
    private typealias FailureCall = @convention(c) (AnyObject, Selector, AnyObject, NSError) -> Void

    static let presentSel = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    static let responseSel = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
    static let fetchSel = NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")
    static let tokenSel = NSSelectorFromString("application:didRegisterForRemoteNotificationsWithDeviceToken:")
    static let failureSel = NSSelectorFromString("application:didFailToRegisterForRemoteNotificationsWithError:")

    /// Records every URL-opening call it receives. It is passed as the `application` / `center` argument of the
    /// swizzled callbacks, so a call the SDK made on it would show up in `calls`.
    final class OpenSpy: NSObject {
        private let lock = NSLock()
        private var recorded: [String] = []

        var calls: [String] { lock.withLock { recorded } }

        @objc func openURL(_ url: URL) -> Bool {
            lock.withLock { recorded.append("openURL") }
            return false
        }

        @objc(open:options:completionHandler:)
        func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler: ((Bool) -> Void)?) {
            lock.withLock { recorded.append("open:options:completionHandler:") }
            completionHandler?(false)
        }
    }

    /// An empty registered class that conforms to `UNUserNotificationCenterDelegate`. The SDK adds what is missing.
    static func makeEmptyDelegateClass() -> AnyClass {
        let name = "NottiFixtureEmptyDelegate\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(NSObject.self, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if let proto = objc_getProtocol("UNUserNotificationCenterDelegate") {
            class_addProtocol(cls, proto)
        }
        objc_registerClassPair(cls)
        return cls
    }

    static func makeInstance(_ cls: AnyClass) -> AnyObject {
        (cls as? NSObject.Type)?.init() ?? NSObject()
    }

    static func notification(userInfo: [AnyHashable: Any], identifier: String = "req-1") -> UNNotification {
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

    static func response(
        userInfo: [AnyHashable: Any],
        action: String = UNNotificationDefaultActionIdentifier,
        identifier: String = "req-1"
    ) -> UNNotificationResponse {
        guard let response = (UNNotificationResponse.self as NSObject.Type).init() as? UNNotificationResponse else {
            fatalError("could not allocate UNNotificationResponse")
        }
        response.setValue(notification(userInfo: userInfo, identifier: identifier), forKey: "notification")
        response.setValue(action, forKey: "actionIdentifier")
        return response
    }

    @discardableResult
    static func sendWillPresent(
        _ delegate: AnyObject,
        _ userInfo: [AnyHashable: Any],
        center: AnyObject = NSObject()
    ) -> [UNNotificationPresentationOptions] {
        var results: [UNNotificationPresentationOptions] = []
        let completion: PresentCompletion = { results.append($0) }
        let send = unsafeBitCast(delegate.method(for: presentSel), to: PresentCall.self)
        send(delegate, presentSel, center, notification(userInfo: userInfo), completion)
        return results
    }

    /// Returns how many times the completion ran.
    @discardableResult
    static func sendDidReceive(_ delegate: AnyObject, _ userInfo: [AnyHashable: Any], center: AnyObject = NSObject()) -> Int {
        var completions = 0
        let completion: ResponseCompletion = { completions += 1 }
        let send = unsafeBitCast(delegate.method(for: responseSel), to: ResponseCall.self)
        send(delegate, responseSel, center, response(userInfo: userInfo), completion)
        return completions
    }

    @discardableResult
    static func sendFetch(
        _ delegate: AnyObject,
        _ userInfo: [AnyHashable: Any],
        application: AnyObject = NSObject()
    ) -> [UIBackgroundFetchResult] {
        var results: [UIBackgroundFetchResult] = []
        let completion: FetchCompletion = { results.append($0) }
        let send = unsafeBitCast(delegate.method(for: fetchSel), to: FetchCall.self)
        send(delegate, fetchSel, application, userInfo as NSDictionary, completion)
        return results
    }

    static func sendToken(_ delegate: AnyObject, _ token: Data, application: AnyObject = NSObject()) {
        unsafeBitCast(delegate.method(for: tokenSel), to: TokenCall.self)(delegate, tokenSel, application, token as NSData)
    }

    static func sendFailure(_ delegate: AnyObject, _ error: NSError, application: AnyObject = NSObject()) {
        unsafeBitCast(delegate.method(for: failureSel), to: FailureCall.self)(delegate, failureSel, application, error)
    }
}

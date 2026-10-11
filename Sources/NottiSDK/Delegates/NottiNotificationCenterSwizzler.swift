import Foundation
import ObjectiveC
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// Observes `UNUserNotificationCenterDelegate` callbacks and keeps observing across delegate swaps
/// (DEL-04, DEL-05, DEL-06, DEL-07, DEL-11).
///
/// `willPresent` goes to `NottiPushAdapter` first. When the host implements it, the host's original runs
/// with the host's completion, which is the one that reaches the OS: the SDK never calls it (DEL-04). When
/// the host does not, the SDK implementation completes once with the adapter's options (D2).
/// `didReceive` goes to the adapter, then to the host's original, or completes once when there is none.
///
/// A swizzle of `-[UNUserNotificationCenter setDelegate:]` swizzles each newly assigned delegate class
/// (idempotent by registry) before the original setter runs, so swapping delegates never grows the chain.
@available(iOSApplicationExtension, unavailable)
final class NottiNotificationCenterSwizzler {

    private typealias PresentCompletion = @convention(block) (UNNotificationPresentationOptions) -> Void
    private typealias ResponseCompletion = @convention(block) () -> Void
    private typealias PresentFunction = @convention(c) (AnyObject, Selector, AnyObject, UNNotification, PresentCompletion) -> Void
    private typealias ResponseFunction =
        @convention(c) (AnyObject, Selector, AnyObject, UNNotificationResponse, ResponseCompletion) -> Void
    private typealias SetDelegateFunction = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias PresentBlock = @convention(block) (AnyObject, AnyObject, UNNotification, @escaping PresentCompletion) -> Void
    private typealias ResponseBlock =
        @convention(block) (AnyObject, AnyObject, UNNotificationResponse, @escaping ResponseCompletion) -> Void

    private static let presentSelector = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    private static let responseSelector = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
    private static let setDelegateSelector = NSSelectorFromString("setDelegate:")

    private let swizzler: NottiMethodSwizzler
    private let adapter: NottiPushAdapter

    init(swizzler: NottiMethodSwizzler, adapter: NottiPushAdapter) {
        self.swizzler = swizzler
        self.adapter = adapter
    }

    // MARK: - Delegate class

    /// Swizzles `willPresent` and `didReceive` on `cls` (or on the superclass that implements each). Idempotent.
    /// Returns false when an install failed (logged at `.error` by the swizzler).
    @discardableResult
    func swizzle(delegateClass cls: AnyClass) -> Bool {
        // The SDK's own fallback delegate already reports through the adapter; swizzling it would observe twice.
        if (cls as? NottiNotificationCenterDelegate.Type) != nil {
            return true
        }
        let present = swizzleWillPresent(cls)
        let response = swizzleDidReceive(cls)
        return present && response
    }

    /// Late path: the delegate already exists when the SDK installs.
    @discardableResult
    func observe(delegate: AnyObject?) -> Bool {
        guard let delegate else { return true }
        return swizzle(delegateClass: type(of: delegate))
    }

    // MARK: - UNUserNotificationCenter.setDelegate:

    /// Swizzles `setDelegate:` on `centerClass` (`UNUserNotificationCenter` in production).
    @discardableResult
    func swizzleSetDelegate(on centerClass: AnyClass) -> Bool {
        swizzler.swizzle(centerClass, Self.setDelegateSelector, typeEncoding: "v@:@") { [weak self] previous in
            let original = previous.map { unsafeBitCast($0, to: SetDelegateFunction.self) }
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { center, delegate in
                self?.observe(delegate: delegate)
                original?(center, Self.setDelegateSelector, delegate)
            }
            return block
        }
    }

    // MARK: - Callbacks

    private func swizzleWillPresent(_ cls: AnyClass) -> Bool {
        let selector = Self.presentSelector
        return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@@?") { [adapter] previous in
            let original = previous.map { unsafeBitCast($0, to: PresentFunction.self) }
            let block: PresentBlock = { object, center, notification, completion in
                let request = notification.request
                let options = adapter.willPresent(userInfo: request.content.userInfo, identifier: request.identifier)
                if let original {
                    // The host's completion is the one that reaches the OS.
                    original(object, selector, center, notification, completion)
                } else {
                    completion(options)
                }
            }
            return block
        }
    }

    private func swizzleDidReceive(_ cls: AnyClass) -> Bool {
        let selector = Self.responseSelector
        return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@@?") { [adapter] previous in
            let original = previous.map { unsafeBitCast($0, to: ResponseFunction.self) }
            let block: ResponseBlock = { object, center, response, completion in
                let request = response.notification.request
                adapter.didReceive(
                    actionIdentifier: response.actionIdentifier,
                    userInfo: request.content.userInfo,
                    identifier: request.identifier
                )
                if let original {
                    // The host completes, once.
                    original(object, selector, center, response, completion)
                } else {
                    completion()
                }
            }
            return block
        }
    }
}

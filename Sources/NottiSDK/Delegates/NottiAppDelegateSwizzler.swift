import Foundation
import ObjectiveC
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(NottiShared)
import NottiShared
#endif

/// Observes the `UIApplicationDelegate` (iOS) or `NSApplicationDelegate` (macOS, AD-025) callbacks the SDK
/// needs (DEL-03, DEL-15, DEL-16): the APNs token, the APNs failure and the silent push. The silent push is
/// the `fetchCompletionHandler` variant on iOS and `application(_:didReceiveRemoteNotification:)` on macOS,
/// which has no completion handler.
///
/// Each callback goes to `NottiPushAdapter` first and then to the host's original with the same
/// arguments. A callback the host does not implement is added, except on iOS the fetch variant when the host
/// implements only the legacy `application(_:didReceiveRemoteNotification:)`: adding it would make UIKit
/// stop calling the legacy method (D3). macOS has no second variant, so that trap does not exist there
/// (design S3, UNCONFIRMED: adding the method to a host that lacks it is harmless).
///
/// Two entry points reach a delegate class: `swizzle(delegateClass:)` directly, and a swizzle of
/// `-[UIApplication setDelegate:]` (`-[NSApplication setDelegate:]` on macOS) so a delegate assigned later is
/// reached before the system queries it.
@available(iOSApplicationExtension, unavailable)
final class NottiAppDelegateSwizzler {

    private typealias TokenFunction = @convention(c) (AnyObject, Selector, AnyObject, NSData) -> Void
    private typealias FailureFunction = @convention(c) (AnyObject, Selector, AnyObject, NSError) -> Void
    #if canImport(UIKit)
        private typealias FetchCompletion = @convention(block) (UIBackgroundFetchResult) -> Void
        private typealias FetchFunction = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary, FetchCompletion) -> Void
        private typealias FetchBlock = @convention(block) (AnyObject, AnyObject, NSDictionary, @escaping FetchCompletion) -> Void
    #else
        private typealias RemoteFunction = @convention(c) (AnyObject, Selector, AnyObject, NSDictionary) -> Void
        private typealias RemoteBlock = @convention(block) (AnyObject, AnyObject, NSDictionary) -> Void
    #endif
    private typealias SetDelegateFunction = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    private static let tokenSelector = NSSelectorFromString("application:didRegisterForRemoteNotificationsWithDeviceToken:")
    private static let failureSelector = NSSelectorFromString("application:didFailToRegisterForRemoteNotificationsWithError:")
    #if canImport(UIKit)
        private static let fetchSelector = NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")
    #endif
    /// iOS: the legacy variant, only probed (DEL-16). macOS: the one silent-push callback, swizzled.
    private static let legacySelector = NSSelectorFromString("application:didReceiveRemoteNotification:")
    private static let setDelegateSelector = NSSelectorFromString("setDelegate:")

    private let swizzler: NottiMethodSwizzler
    private let adapter: NottiPushAdapter
    private let isSwiftUIInternalDelegate: (AnyClass) -> Bool
    private let lock = NSLock()
    private var warnedAboutSwiftUI = false

    /// - Parameters:
    ///   - isSwiftUIInternalDelegate: true for SwiftUI's own app delegate class, which is never swizzled
    ///     (with an adaptor, its forwarding target is). Injected so tests need no SwiftUI.
    init(
        swizzler: NottiMethodSwizzler,
        adapter: NottiPushAdapter,
        isSwiftUIInternalDelegate: @escaping (AnyClass) -> Bool = NottiAppDelegateSwizzler.isSwiftUIInternal
    ) {
        self.swizzler = swizzler
        self.adapter = adapter
        self.isSwiftUIInternalDelegate = isSwiftUIInternalDelegate
    }

    /// Best-effort name check for SwiftUI's internal app delegate. Verified on device, not in unit tests.
    static func isSwiftUIInternal(_ cls: AnyClass) -> Bool {
        let name = NSStringFromClass(cls)
        return name.hasPrefix("_TtC7SwiftUI") || name.hasPrefix("SwiftUI.")
    }

    // MARK: - Delegate class

    /// Swizzles the three callbacks on `cls` (or on the superclass that implements each). Idempotent.
    /// Returns false when any install failed (logged at `.error` by the swizzler).
    @discardableResult
    func swizzle(delegateClass cls: AnyClass) -> Bool {
        if isSwiftUIInternalDelegate(cls) {
            warnAboutSwiftUIOnce()
            return true
        }
        let token = swizzleToken(cls)
        let failure = swizzleFailure(cls)
        let remote = swizzleRemoteNotification(cls)
        return token && failure && remote
    }

    /// Swizzles the class of a delegate instance: from the `setDelegate:` hook and from the late path, when
    /// the delegate already exists at install time.
    ///
    /// SwiftUI's internal delegate stays the app delegate even with `@UIApplicationDelegateAdaptor`, and
    /// forwards each call to the host's adaptor object through `forwardingTarget(for:)` (DEL-19, AD-016).
    /// That object's class is the one swizzled; SwiftUI's own class is never touched.
    @discardableResult
    func observe(delegate: AnyObject?) -> Bool {
        guard let delegate else { return true }
        let cls: AnyClass = type(of: delegate)
        if isSwiftUIInternalDelegate(cls), let adaptor = adaptorDelegate(behind: delegate) {
            return swizzle(delegateClass: type(of: adaptor))
        }
        return swizzle(delegateClass: cls)
    }

    /// The host's `@UIApplicationDelegateAdaptor` object behind SwiftUI's internal delegate, or nil when
    /// there is none (no adaptor: the caller falls back to the SwiftUI warning).
    private func adaptorDelegate(behind delegate: AnyObject) -> AnyObject? {
        guard let object = delegate as? NSObject,
              let target = object.forwardingTarget(for: Self.tokenSelector) as AnyObject?,
              target !== delegate,
              !isSwiftUIInternalDelegate(type(of: target))
        else { return nil }
        return target
    }

    // MARK: - UIApplication.setDelegate:

    /// Swizzles `setDelegate:` on `applicationClass` (`UIApplication` in production) so each newly assigned
    /// delegate class is swizzled before the original setter runs.
    @discardableResult
    func swizzleSetDelegate(on applicationClass: AnyClass) -> Bool {
        swizzler.swizzle(applicationClass, Self.setDelegateSelector, typeEncoding: "v@:@") { [weak self] previous in
            let original = previous.map { unsafeBitCast($0, to: SetDelegateFunction.self) }
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { application, delegate in
                self?.observe(delegate: delegate)
                original?(application, Self.setDelegateSelector, delegate)
            }
            return block
        }
    }

    // MARK: - Callbacks

    private func swizzleToken(_ cls: AnyClass) -> Bool {
        let selector = Self.tokenSelector
        return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@") { [adapter] previous in
            let original = previous.map { unsafeBitCast($0, to: TokenFunction.self) }
            let block: @convention(block) (AnyObject, AnyObject, NSData) -> Void = { object, application, token in
                adapter.didRegister(deviceToken: token as Data)
                original?(object, selector, application, token)
            }
            return block
        }
    }

    private func swizzleFailure(_ cls: AnyClass) -> Bool {
        let selector = Self.failureSelector
        return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@") { [adapter] previous in
            let original = previous.map { unsafeBitCast($0, to: FailureFunction.self) }
            let block: @convention(block) (AnyObject, AnyObject, NSError) -> Void = { object, application, error in
                adapter.didFail(error: error)
                original?(object, selector, application, error)
            }
            return block
        }
    }

    #if canImport(UIKit)
        private func swizzleRemoteNotification(_ cls: AnyClass) -> Bool {
            swizzleFetchIfSafe(cls)
        }

        /// DEL-16: never add the fetch variant over a host that has only the legacy method.
        private func swizzleFetchIfSafe(_ cls: AnyClass) -> Bool {
            let hasFetch = class_respondsToSelector(cls, Self.fetchSelector)
            if !hasFetch && class_respondsToSelector(cls, Self.legacySelector) {
                return true
            }
            let selector = Self.fetchSelector
            return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@@?") { [adapter] previous in
                let original = previous.map { unsafeBitCast($0, to: FetchFunction.self) }
                let block: FetchBlock = { object, application, userInfo, completion in
                    let result = adapter.didReceiveRemoteNotification(userInfo: userInfo as? [AnyHashable: Any] ?? [:])
                    if let original {
                        // The host's completion is the one that reaches the OS.
                        original(object, selector, application, userInfo, completion)
                    } else {
                        completion(result)
                    }
                }
                return block
            }
        }
    #else
        /// macOS: `application(_:didReceiveRemoteNotification:)` has no completion handler. The adapter sees
        /// the push once, then the host's original (if any) runs with the same arguments. Added when the
        /// host lacks it (design S3, UNCONFIRMED).
        private func swizzleRemoteNotification(_ cls: AnyClass) -> Bool {
            let selector = Self.legacySelector
            return swizzler.swizzle(cls, selector, typeEncoding: "v@:@@") { [adapter] previous in
                let original = previous.map { unsafeBitCast($0, to: RemoteFunction.self) }
                let block: RemoteBlock = { object, application, userInfo in
                    adapter.didReceiveRemoteNotification(userInfo: userInfo as? [AnyHashable: Any] ?? [:])
                    original?(object, selector, application, userInfo)
                }
                return block
            }
        }
    #endif

    private func warnAboutSwiftUIOnce() {
        let shouldWarn: Bool = lock.withLock {
            defer { warnedAboutSwiftUI = true }
            return !warnedAboutSwiftUI
        }
        guard shouldWarn else { return }
        NottiLogger.log(
            .warn,
            "Notti: the app delegate is SwiftUI's internal one and is not swizzled; use @UIApplicationDelegateAdaptor or the manual API",
            category: "delegates"
        )
    }
}

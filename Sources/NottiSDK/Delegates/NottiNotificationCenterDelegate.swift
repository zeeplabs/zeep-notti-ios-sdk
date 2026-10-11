import Foundation
import UIKit
import UserNotifications

/// The slice of `UNUserNotificationCenter` the fallback needs, so tests inject a fake center.
@available(iOSApplicationExtension, unavailable)
protocol NottiNotificationCenterHost: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
}

@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter: NottiNotificationCenterHost {}

/// The SDK's own `UNUserNotificationCenterDelegate`, used only when the host never sets one (DEL-06).
///
/// It does what the swizzled path does for a host that has no methods: reports through `NottiPushAdapter`
/// and completes exactly once (D2 options for `willPresent`). It is never swizzled itself
/// (`NottiNotificationCenterSwizzler` skips it), so each callback is observed once.
@available(iOSApplicationExtension, unavailable)
final class NottiNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let adapter: NottiPushAdapter

    init(adapter: NottiPushAdapter) {
        self.adapter = adapter
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let request = notification.request
        completionHandler(adapter.willPresent(userInfo: request.content.userInfo, identifier: request.identifier))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        adapter.didReceive(
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
        completionHandler()
    }
}

/// Assigns the fallback delegate at the end of launch, only when the host left `delegate` nil (D1).
///
/// At `+load` time every host's `UNUserNotificationCenter.delegate` is nil, including hosts that set it a
/// few milliseconds later, so assuming it then would override the host. The check runs when
/// `UIApplication.didFinishLaunchingNotification` fires, after `application(_:didFinishLaunchingWithOptions:)`
/// returned. The OS holds a cold-start response until a delegate exists, so the click still arrives. A
/// delegate the host sets later goes through the swizzled setter and replaces the fallback.
///
/// The center's `delegate` is weak, so this object owns the fallback. Center and `NotificationCenter` are
/// injected.
@available(iOSApplicationExtension, unavailable)
final class NottiFallbackDelegateAssigner {

    private let isEnabled: Bool
    private let center: NottiNotificationCenterHost
    private let notificationCenter: NotificationCenter
    private let adapter: NottiPushAdapter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var fallback: NottiNotificationCenterDelegate?

    /// - Parameter isEnabled: false when swizzling is off (opt-out): the SDK never becomes the delegate.
    init(
        isEnabled: Bool,
        center: NottiNotificationCenterHost,
        notificationCenter: NotificationCenter = .default,
        adapter: NottiPushAdapter
    ) {
        self.isEnabled = isEnabled
        self.center = center
        self.notificationCenter = notificationCenter
        self.adapter = adapter
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    /// The fallback assigned to the center, if any.
    var assignedFallback: NottiNotificationCenterDelegate? {
        lock.withLock { fallback }
    }

    /// Starts waiting for the end of launch. Idempotent; a no-op when swizzling is off.
    func start() {
        guard isEnabled else { return }
        lock.withLock {
            guard observer == nil, fallback == nil else { return }
            observer = notificationCenter.addObserver(
                forName: UIApplication.didFinishLaunchingNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.assignIfNeeded()
            }
        }
    }

    /// Evaluates now, for an install that runs after the end of launch (the launch notification already
    /// fired, so `start()` would wait forever). A no-op when swizzling is off, when the host has a delegate
    /// or when the fallback was already assigned.
    func evaluateNow() {
        guard isEnabled else { return }
        assignIfNeeded()
    }

    private func assignIfNeeded() {
        lock.withLock {
            if let observer {
                notificationCenter.removeObserver(observer)
                self.observer = nil
            }
            guard fallback == nil, center.delegate == nil else { return }
            let delegate = NottiNotificationCenterDelegate(adapter: adapter)
            fallback = delegate
            center.delegate = delegate
        }
    }
}

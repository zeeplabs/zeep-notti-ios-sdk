import Foundation
import UIKit
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// The single place that turns OS delegate inputs into runtime and handler calls.
///
/// The swizzled blocks (`NottiAppDelegateSwizzler`, `NottiNotificationCenterSwizzler`), the fallback
/// `UNUserNotificationCenterDelegate` and the manual API all call it, so the paths cannot diverge.
/// Entry points take plain inputs (`userInfo`, identifiers), so tests need no `UNNotification`.
///
/// The `manual…` entry points are for the host's own forwarding calls. While swizzling is active they
/// are ignored with one `.warn` (no values) so an event is never processed twice (DEL-09).
@available(iOSApplicationExtension, unavailable)
final class NottiPushAdapter {

    /// Presentation options the SDK passes for a Notti push when the host has no `willPresent` (RN parity).
    static let nottiPresentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]

    private let runtimeProvider: () -> NottiRuntime
    private let isSwizzlingActive: () -> Bool
    private let lock = NSLock()
    private var resolved: (runtime: NottiRuntime, handler: NottiNotificationHandler)?

    /// - Parameters:
    ///   - runtimeProvider: called on first use, never at construction. The installer builds the adapter at
    ///     process launch (`+load`), where touching `NottiRuntime.shared` would open UserDefaults and start
    ///     observers (DEL-14).
    ///   - isSwizzlingActive: read by the manual entry points (`NottiSwizzlingState` in production).
    init(runtimeProvider: @escaping () -> NottiRuntime, isSwizzlingActive: @escaping () -> Bool = { false }) {
        self.runtimeProvider = runtimeProvider
        self.isSwizzlingActive = isSwizzlingActive
    }

    convenience init(runtime: NottiRuntime, isSwizzlingActive: @escaping () -> Bool = { false }) {
        self.init(runtimeProvider: { runtime }, isSwizzlingActive: isSwizzlingActive)
    }

    private var runtime: NottiRuntime { resolve().runtime }
    private var handler: NottiNotificationHandler { resolve().handler }

    private func resolve() -> (runtime: NottiRuntime, handler: NottiNotificationHandler) {
        lock.withLock {
            if let resolved { return resolved }
            let runtime = runtimeProvider()
            let value = (runtime: runtime, handler: NottiNotificationHandler(runtime: runtime))
            resolved = value
            return value
        }
    }

    // MARK: - Swizzled and fallback path

    func didRegister(deviceToken: Data) {
        runtime.onApnsToken(deviceToken)
    }

    /// Logs `domain#code` only (inside the runtime), never `localizedDescription`.
    func didFail(error: Error) {
        runtime.onApnsRegistrationFailed(error)
    }

    /// Reports a Notti push and returns the options the SDK uses when the host has no `willPresent`:
    /// `[.banner, .list, .sound, .badge]` for a Notti push and `[]` for anything else, which is also
    /// not reported (D2). A Notti push is a remote push with a non-empty `notification_id`.
    func willPresent(userInfo: [AnyHashable: Any], identifier: String) -> UNNotificationPresentationOptions {
        guard Self.isNottiPush(userInfo) else {
            return []
        }
        handler.handleWillPresent(userInfo: userInfo, identifier: identifier)
        return Self.nottiPresentationOptions
    }

    /// Reports a response. Local notifications and payloads without `aps` are ignored by the handler.
    func didReceive(actionIdentifier: String, userInfo: [AnyHashable: Any], identifier: String) {
        handler.handleResponse(actionIdentifier: actionIdentifier, userInfo: userInfo, identifier: identifier)
    }

    /// Silent-push path. The fetch result is `.noData`: the SDK downloads nothing.
    func didReceiveRemoteNotification(userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        handler.handleSilentPush(userInfo: userInfo)
        return .noData
    }

    // MARK: - Manual path (ignored while swizzling is active)

    func manualDidRegister(deviceToken: Data) {
        guard !ignoreManualCall("didRegisterForRemoteNotifications") else { return }
        didRegister(deviceToken: deviceToken)
    }

    func manualDidFail(error: Error) {
        guard !ignoreManualCall("didFailToRegisterForRemoteNotifications") else { return }
        didFail(error: error)
    }

    /// While swizzling is active the event is not reported, but the options are still returned (a pure
    /// computation) so a host that uses the value as its completion is not left with a hidden banner.
    func manualWillPresent(userInfo: [AnyHashable: Any], identifier: String) -> UNNotificationPresentationOptions {
        guard !ignoreManualCall("willPresent") else {
            return Self.isNottiPush(userInfo) ? Self.nottiPresentationOptions : []
        }
        return willPresent(userInfo: userInfo, identifier: identifier)
    }

    func manualDidReceive(actionIdentifier: String, userInfo: [AnyHashable: Any], identifier: String) {
        guard !ignoreManualCall("didReceive") else { return }
        didReceive(actionIdentifier: actionIdentifier, userInfo: userInfo, identifier: identifier)
    }

    func manualDidReceiveRemoteNotification(userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        guard !ignoreManualCall("didReceiveRemoteNotification") else { return .noData }
        return didReceiveRemoteNotification(userInfo: userInfo)
    }

    // MARK: - Helpers

    /// A Notti push: a remote push (`aps` present) with a non-empty `notification_id`.
    static func isNottiPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo[NottiPayloadKeys.aps] != nil else { return false }
        // Same stringification the handler uses, so "Notti push" and "reportable" agree.
        guard let notificationId = parseUserInfo(userInfo).data[NottiPayloadKeys.notificationId] else { return false }
        return !notificationId.isEmpty
    }

    /// Returns true (and logs one `.warn` without values) when the call must be ignored.
    private func ignoreManualCall(_ name: String) -> Bool {
        guard isSwizzlingActive() else { return false }
        NottiLogger.log(
            .warn,
            "Notti: \(name) ignored because delegate swizzling is active; remove the manual call or set NottiDisableSwizzling",
            category: "delegates"
        )
        return true
    }
}

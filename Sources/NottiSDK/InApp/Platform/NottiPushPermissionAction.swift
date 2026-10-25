import Foundation
import UIKit
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// iOS side of the `push_permission` In-App button (design D15, IAM-50), a port of RN
/// `NottiPushPermissionAction.swift` (0.8.0).
///
/// | state | effect |
/// | --- | --- |
/// | not determined | request through the current core, so the subscribed PATCH and the status refresh stay there |
/// | denied | open the app's notification settings |
/// | authorized, provisional, ephemeral | nothing |
/// | unknown | nothing, one fixed log line |
///
/// AD-019: this is the only file allowed to open a URL (`scripts/check-no-url-open.sh` allowlists it by
/// path), and the only URL it opens is the system settings constant below. Every platform effect is
/// injected, so each row is a plain XCTest.
final class NottiPushPermissionAction {

    static let unknownStateLog = "Notti.inapp: push permission state unavailable"

    enum State: Equatable {
        case notDetermined
        case denied
        case granted
        case unknown

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .denied: self = .denied
            case .authorized, .provisional, .ephemeral: self = .granted
            @unknown default: self = .unknown
            }
        }
    }

    /// The OS side: how the state is read and how the settings page is opened (`system` in production).
    struct Platform {
        let readState: (@escaping (State) -> Void) -> Void
        let openNotificationSettings: () -> Void

        @available(iOSApplicationExtension, unavailable)
        static let system = Platform(
            readState: NottiPushPermissionAction.systemState,
            openNotificationSettings: NottiPushPermissionAction.openSystemNotificationSettings
        )
    }

    private let readState: (@escaping (State) -> Void) -> Void
    private let requestPermission: () -> Void
    private let openNotificationSettings: () -> Void
    private let logger: (String) -> Void

    /// `readState` may answer on any thread; `openNotificationSettings` hops to main itself.
    init(
        readState: @escaping (@escaping (State) -> Void) -> Void,
        requestPermission: @escaping () -> Void,
        openNotificationSettings: @escaping () -> Void,
        logger: @escaping (String) -> Void = { NottiLogger.log(.warn, $0, category: "inapp") }
    ) {
        self.readState = readState
        self.requestPermission = requestPermission
        self.openNotificationSettings = openNotificationSettings
        self.logger = logger
    }

    func run() {
        readState { [self] state in
            switch state {
            case .notDetermined: requestPermission()
            case .denied: openNotificationSettings()
            case .granted: break
            case .unknown: logger(Self.unknownStateLog)
            }
        }
    }

    /// The production state reader.
    @available(iOSApplicationExtension, unavailable)
    static func systemState(_ callback: @escaping (State) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            callback(State(settings.authorizationStatus))
        }
    }

    /// Opens the app's notification settings where the OS has such a page (iOS 16+), else its settings page.
    /// The address is always a system constant.
    @available(iOSApplicationExtension, unavailable)
    static func openSystemNotificationSettings() {
        DispatchQueue.main.async {
            let raw: String
            if #available(iOS 16.0, *) {
                raw = UIApplication.openNotificationSettingsURLString
            } else {
                raw = UIApplication.openSettingsURLString
            }
            guard let url = URL(string: raw) else { return }
            UIApplication.shared.open(url)
        }
    }
}

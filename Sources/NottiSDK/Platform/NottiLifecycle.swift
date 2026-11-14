// AD-025 (macos-support): the one place that knows which system notification marks which SDK lifecycle
// event. The core, the runtime and the delegate installer read this seam, never a platform class, so the
// session logic stays name-agnostic. On iOS every name is the same `UIApplication` constant as before.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOSApplicationExtension, unavailable)
@available(macOSApplicationExtension, unavailable)
enum NottiLifecycle {

    /// The end of the app's launch. `didFinishLaunching` on both platforms.
    static var didFinishLaunching: Notification.Name {
        #if canImport(UIKit)
            return UIApplication.didFinishLaunchingNotification
        #else
            return NSApplication.didFinishLaunchingNotification
        #endif
    }

    /// The app became the active (foreground) app: a session starts. Same name on both platforms.
    static var didBecomeActive: Notification.Name {
        #if canImport(UIKit)
            return UIApplication.didBecomeActiveNotification
        #else
            return NSApplication.didBecomeActiveNotification
        #endif
    }

    /// The app left the screen: the session ends.
    ///
    /// UNCONFIRMED DECISION (design C1, spike S4): on macOS this is `didResignActive`, which fires on every
    /// app switch (Cmd-Tab), so sessions become many and short. If the owner prefers `didHide` or window
    /// occlusion instead, this is the only line to change.
    static var didEnterBackground: Notification.Name {
        #if canImport(UIKit)
            return UIApplication.didEnterBackgroundNotification
        #else
            return NSApplication.didResignActiveNotification
        #endif
    }

    #if canImport(UIKit)
        /// Back to the foreground (iOS only). It only drives the In-App engine, which is inert on macOS
        /// (design D3), and `didBecomeActive` already starts the session.
        static var willEnterForeground: Notification.Name {
            UIApplication.willEnterForegroundNotification
        }
    #else
        /// The app is quitting (macOS only; iOS never uses it). Ends a session that is still open because
        /// no resign-active came before the quit.
        static var willTerminate: Notification.Name {
            NSApplication.willTerminateNotification
        }
    #endif
}

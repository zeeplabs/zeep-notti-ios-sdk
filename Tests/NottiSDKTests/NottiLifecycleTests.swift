import XCTest
#if canImport(UIKit)
#if canImport(UIKit)
import UIKit
#endif
#elseif canImport(AppKit)
import AppKit
#endif
@testable import NottiSDK

/// AD-025: the `NottiLifecycle` seam maps each SDK lifecycle event to the system notification of the platform.
/// Each name is compared with the literal platform constant, so a wrong mapping fails here and not silently in
/// the field (an observer on a name nobody posts compiles and never fires).
final class NottiLifecycleTests: XCTestCase {

    func test_namesAreThePlatformConstants() {
        #if canImport(UIKit)
            XCTAssertEqual(NottiLifecycle.didFinishLaunching, UIApplication.didFinishLaunchingNotification)
            XCTAssertEqual(NottiLifecycle.didBecomeActive, UIApplication.didBecomeActiveNotification)
            XCTAssertEqual(NottiLifecycle.didEnterBackground, UIApplication.didEnterBackgroundNotification)
            XCTAssertEqual(NottiLifecycle.willEnterForeground, UIApplication.willEnterForegroundNotification)
        #else
            XCTAssertEqual(NottiLifecycle.didFinishLaunching, NSApplication.didFinishLaunchingNotification)
            XCTAssertEqual(NottiLifecycle.didBecomeActive, NSApplication.didBecomeActiveNotification)
            // Unconfirmed decision C1: resign active ends the session on macOS.
            XCTAssertEqual(NottiLifecycle.didEnterBackground, NSApplication.didResignActiveNotification)
            XCTAssertEqual(NottiLifecycle.willTerminate, NSApplication.willTerminateNotification)
        #endif
    }

    func test_theThreeSessionNamesAreDistinct() {
        let names: Set<Notification.Name> = [
            NottiLifecycle.didFinishLaunching, NottiLifecycle.didBecomeActive, NottiLifecycle.didEnterBackground
        ]
        XCTAssertEqual(names.count, 3)
    }
}

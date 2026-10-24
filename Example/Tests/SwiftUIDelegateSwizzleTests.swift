import ObjectiveC
import UIKit
import XCTest
@testable import NottiExample

/// Runs inside the real SwiftUI app, where unit-test fakes cannot reach: with `@UIApplicationDelegateAdaptor`,
/// `UIApplication.shared.delegate` is SwiftUI's internal delegate, and the SDK must swizzle the adaptor class
/// behind it (DEL-19, AD-016). Before AD-016 the APNs token never reached the SDK in this setup.
final class SwiftUIDelegateSwizzleTests: XCTestCase {

    private let selectors = [
        "application:didRegisterForRemoteNotificationsWithDeviceToken:",
        "application:didFailToRegisterForRemoteNotificationsWithError:",
        "application:didReceiveRemoteNotification:fetchCompletionHandler:",
    ].map(NSSelectorFromString)

    func test_theAdaptorDelegateIsWhatTheAppDelegateForwardsToAndItsPushCallbacksAreSwizzled() throws {
        try XCTSkipUnless(ExampleApp.usesAdaptor, "no @UIApplicationDelegateAdaptor in this configuration")
        try XCTSkipIf(ManualForwarding().isEnabled, "swizzling is off in this configuration")
        let appDelegate = try XCTUnwrap(UIApplication.shared.delegate as? NSObject)
        let receiver = appDelegate.forwardingTarget(for: selectors[0]) ?? appDelegate
        XCTAssertTrue(receiver is ExampleAppDelegate, "the push callbacks land on the adaptor delegate")

        for selector in selectors {
            XCTAssertTrue(appDelegate.responds(to: selector), NSStringFromSelector(selector))
            // The SDK installs block IMPs; the host's own methods are compiled Swift, not blocks.
            let imp = class_getMethodImplementation(ExampleAppDelegate.self, selector)
            XCTAssertNotNil(imp.flatMap { imp_getBlock($0) }, "not swizzled: \(NSStringFromSelector(selector))")
        }
    }
}

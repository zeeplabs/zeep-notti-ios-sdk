import UIKit
import UserNotifications
import XCTest
@testable import NottiExample

private final class CountingSink: ForwardingSink {
    private(set) var calls: [String] = []
    func didRegister(deviceToken: Data) { calls.append("didRegister") }
    func didFail(error: Error) { calls.append("didFail") }
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        calls.append("didReceiveRemoteNotification"); return .newData
    }
    func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        calls.append("willPresent"); return [.banner]
    }
    func didReceive(_ response: UNNotificationResponse) { calls.append("didReceive") }
}

final class ManualForwardingTests: XCTestCase {
    private struct SyntheticError: Error {}

    /// Never read: the sink only counts. `class_createInstance` avoids needing a real notification.
    private func fakeNotification() throws -> UNNotification {
        try XCTUnwrap(class_createInstance(UNNotification.self, 0) as? UNNotification)
    }

    private func fakeResponse() throws -> UNNotificationResponse {
        try XCTUnwrap(class_createInstance(UNNotificationResponse.self, 0) as? UNNotificationResponse)
    }

    private func driveAllFive(_ forwarding: ManualForwarding) throws -> (UIBackgroundFetchResult, UNNotificationPresentationOptions) {
        forwarding.didRegister(deviceToken: Data([0x01]))
        forwarding.didFail(error: SyntheticError())
        let fetch = forwarding.didReceiveRemoteNotification(["k": "v"])
        let options = forwarding.willPresent(try fakeNotification())
        forwarding.didReceive(try fakeResponse())
        return (fetch, options)
    }

    func test_enabledForwardsTheFiveCallsAndReturnsTheSdkResults() throws {
        let sink = CountingSink()
        let (fetch, options) = try driveAllFive(ManualForwarding(isEnabled: true, sink: sink))
        XCTAssertEqual(sink.calls, ["didRegister", "didFail", "didReceiveRemoteNotification", "willPresent", "didReceive"])
        XCTAssertEqual(fetch, .newData)
        XCTAssertEqual(options, [.banner])
    }

    func test_disabledForwardsNothingAndReturnsNeutralResults() throws {
        let sink = CountingSink()
        let (fetch, options) = try driveAllFive(ManualForwarding(isEnabled: false, sink: sink))
        XCTAssertEqual(sink.calls, [])
        XCTAssertEqual(fetch, .noData)
        XCTAssertEqual(options, [])
    }

    func test_bundleFlagMustBeABooleanTrue() {
        let key = ManualForwarding.plistKey
        XCTAssertEqual(key, "NottiDisableSwizzling")
        XCTAssertFalse(ManualForwarding(bundle: Bundle(for: ManualForwardingTests.self), sink: CountingSink()).isEnabled)
    }
}

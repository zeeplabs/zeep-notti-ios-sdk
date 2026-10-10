// Ported from react-native-notti 52e4b55 ios/Tests/NottiCoreTests.swift (AD-002).
// Changes: moved out of the RN test file unchanged; `@testable import NottiSDK`.

import Foundation
@testable import NottiSDK

/// Registers successfully and answers every event report with a slow
/// transient failure, counting calls - used to prove flush de-duplication.
final class SlowEventApiClient: NottiApiClient {
    private let lock = NSLock()
    private var reports = 0

    init() {
        super.init(baseUrl: "https://notti.example.com", appId: "app-1", clientKey: "key", sleeper: { _ in })
    }

    var reportCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reports
    }

    override func createOrUpdateDevice(token: String, platform: String) -> ApiResult {
        .success(DeviceResponse(id: "device-1", tags: [:]))
    }

    override func reportEvent(notificationId: String, deliveryId: String, type: String, token: String) -> EventResult {
        lock.lock(); reports += 1; lock.unlock()
        Thread.sleep(forTimeInterval: 0.3)
        return .failure("HTTP 503", terminal: false)
    }
}

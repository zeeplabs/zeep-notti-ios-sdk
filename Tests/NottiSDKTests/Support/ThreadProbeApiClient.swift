// Ported from react-native-notti 52e4b55 ios/Tests/NottiCoreTests.swift (AD-002).
// Changes: moved out of the RN test file unchanged; `@testable import NottiSDK`.

import Foundation
@testable import NottiSDK

/// An API client that records which thread it was called on and blocks there
/// for a while, standing in for a slow/dead network. A stubbed `URLProtocol`
/// cannot prove this: `URLSession` always runs the protocol on its own
/// internal queue, so the only way to observe the thread the *SDK's* blocking
/// call chain occupies is from inside the client itself.
final class ThreadProbeApiClient: NottiApiClient {

    private let blockForSeconds: TimeInterval
    private let lock = NSLock()
    private var mainThreadSeen = false
    private var calls = 0
    private var patchCalls = 0

    init(blockForSeconds: TimeInterval) {
        self.blockForSeconds = blockForSeconds
        super.init(baseUrl: "https://notti.example.com", appId: "app-1", clientKey: "key", sleeper: { _ in })
    }

    var sawMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return mainThreadSeen
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    var patchCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return patchCalls
    }

    override func createOrUpdateDevice(token: String, platform: String) -> ApiResult {
        record(isPatch: false)
        Thread.sleep(forTimeInterval: blockForSeconds)
        return .success(DeviceResponse(id: "device-1", tags: [:]))
    }

    override func patchDevice(deviceId: String, token: String, fields: [String: Any]) -> ApiResult {
        record(isPatch: true)
        Thread.sleep(forTimeInterval: blockForSeconds)
        return .success(DeviceResponse(id: deviceId, tags: (fields["tags"] as? [String: String]) ?? [:]))
    }

    private func record(isPatch: Bool) {
        let onMain = Thread.isMainThread
        lock.lock(); defer { lock.unlock() }
        if onMain { mainThreadSeen = true }
        calls += 1
        if isPatch { patchCalls += 1 }
    }
}

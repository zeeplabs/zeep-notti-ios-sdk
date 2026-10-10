// Ported from react-native-notti 52e4b55 ios/Tests/NottiCoreTests.swift (AD-002).
// Changes: moved out of the RN test file unchanged; `@testable import NottiSDK`.

import Foundation
@testable import NottiSDK

/// Registers successfully and answers every PATCH through `onPatch` (true =
/// 2xx, false = terminal 400) - lets a test mutate store state while a PATCH
/// is "in flight" and fail specific requests. Called on the work queue only.
final class PatchHookApiClient: NottiApiClient {
    private let onPatch: ([String: Any]) -> Bool

    init(onPatch: @escaping ([String: Any]) -> Bool) {
        self.onPatch = onPatch
        super.init(baseUrl: "https://notti.example.com", appId: "app-1", clientKey: "key", sleeper: { _ in })
    }

    override func createOrUpdateDevice(token: String, platform: String) -> ApiResult {
        .success(DeviceResponse(id: "device-1", tags: [:]))
    }

    override func patchDevice(deviceId: String, token: String, fields: [String: Any]) -> ApiResult {
        onPatch(fields) ? .success(DeviceResponse(id: deviceId, tags: [:])) : .failure("HTTP 400")
    }
}

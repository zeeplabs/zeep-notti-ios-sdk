import Foundation
@testable import NottiExample

/// Records calls instead of reaching the SDK. `calls` holds names only; `lastArgs` holds what was passed.
final class SpySDKClient: ExampleSDKClient {
    private(set) var calls: [String] = []
    private(set) var lastArgs: [String: String] = [:]
    var permissionResult = true
    var storedDeviceId: String? = "device-synthetic"
    var initialClickKeys: [String]?
    var receivedHandler: PayloadHandler?
    var clickedHandler: PayloadHandler?
    var deviceIdHandler: (@MainActor @Sendable (String) -> Void)?
    private(set) var removedListeners = 0
    private var level = ExampleLogLevel.error

    private func note(_ name: String, _ args: [String: String] = [:]) {
        calls.append(name)
        for (key, value) in args { lastArgs[key] = value }
    }

    func initialize(appId: String, clientKey: String, baseUrl: String?) {
        note("initialize", ["appId": appId, "clientKey": clientKey, "baseUrl": baseUrl ?? "nil"])
    }
    func requestPermission() async -> Bool { note("requestPermission"); return permissionResult }
    func requestPermission(completion: @escaping (Bool) -> Void) {
        note("requestPermissionCompletion")
        completion(permissionResult)
    }
    func login(_ externalUserId: String) { note("login", ["id": externalUserId]) }
    func logout() { note("logout") }
    func setEmail(_ email: String) { note("setEmail", ["email": email]) }
    func clearEmail() { note("clearEmail") }
    func setPhone(_ phone: String) { note("setPhone", ["phone": phone]) }
    func clearPhone() { note("clearPhone") }
    func addTag(_ key: String, value: String) { note("addTag", ["key": key, "value": value]) }
    func addTags(_ tags: [String: String]) { note("addTags", ["tags": tags.keys.sorted().joined(separator: ",")]) }
    func removeTag(_ key: String) { note("removeTag", ["key": key]) }
    func removeTags(_ keys: [String]) { note("removeTags", ["keys": keys.joined(separator: ",")]) }
    func setSubscription(_ enabled: Bool) { note("setSubscription", ["enabled": "\(enabled)"]) }
    func setLocationSharingEnabled(_ enabled: Bool) { note("setLocationSharingEnabled", ["enabled": "\(enabled)"]) }
    func setLogLevel(_ level: ExampleLogLevel) { note("setLogLevel"); self.level = level }
    func currentLogLevel() -> ExampleLogLevel { level }
    func deviceId() -> String? { storedDeviceId }
    func addReceivedListener(_ handler: @escaping PayloadHandler) -> () -> Void {
        note("addReceivedListener"); receivedHandler = handler
        return { [weak self] in self?.removedListeners += 1 }
    }
    func addClickedListener(_ handler: @escaping PayloadHandler) -> () -> Void {
        note("addClickedListener"); clickedHandler = handler
        return { [weak self] in self?.removedListeners += 1 }
    }
    func addDeviceIdChangedListener(_ handler: @escaping @MainActor @Sendable (String) -> Void) -> () -> Void {
        note("addDeviceIdChangedListener"); deviceIdHandler = handler
        return { [weak self] in self?.removedListeners += 1 }
    }
    func takeInitialClick() -> [String]? { note("takeInitialClick"); return initialClickKeys }
}

import XCTest
@testable import NottiExample

@MainActor
final class ExampleModelTests: XCTestCase {
    private let sentinelEmail = "sentinel-mail@example.invalid"
    private let sentinelPhone = "+0000000SENTINEL"
    private let sentinelKey = "key-SENTINEL-secret"
    private let sentinelToken = "token-SENTINEL"

    private func model(configured: Bool = true, spy: SpySDKClient = SpySDKClient()) -> (ExampleModel, SpySDKClient) {
        let config = configured
            ? ExampleConfig(appId: "app-synthetic", clientKey: sentinelKey, host: "h.example.invalid")
            : ExampleConfig(appId: "fixture", clientKey: "fixture", host: "")
        return (ExampleModel(config: config, sdk: spy), spy)
    }

    func test_unconfiguredNeverCallsTheSdkFromAnyAction() async {
        let (model, spy) = model(configured: false)
        model.initialize()
        model.refreshDeviceId()
        model.setLogLevel(.debug)
        model.login("user"); model.logout()
        model.setEmail(sentinelEmail); model.clearEmail()
        model.setPhone(sentinelPhone); model.clearPhone()
        model.setSubscription(false); model.setLocationSharing(true)
        model.addTag(key: "k", value: "v"); model.addTags("a=b"); model.removeTag("k"); model.removeTags("a")
        await model.requestPermission(); model.requestPermissionWithCompletion()
        model.startListening(); model.stopListening(); model.takeInitialClick()

        XCTAssertEqual(spy.calls, [])
        XCTAssertNil(model.deviceId)
        XCTAssertFalse(model.isInitialized)
        XCTAssertTrue(model.log.rows.allSatisfy { $0 == LogEvent.notConfigured.text })
        XCTAssertFalse(model.log.rows.isEmpty)
    }

    func test_initializePassesConfigAndReadsTheDeviceId() {
        let (model, spy) = model()
        model.initialize()
        XCTAssertEqual(spy.calls, ["initialize"])
        XCTAssertEqual(spy.lastArgs["baseUrl"], "https://h.example.invalid")
        XCTAssertEqual(model.deviceId, "device-synthetic")
        XCTAssertTrue(model.isInitialized)
    }

    func test_sentinelEmailPhoneAndKeyReachTheSdkButNeverTheLog() {
        let (model, spy) = model()
        model.initialize()
        model.setEmail(sentinelEmail)
        model.setPhone(sentinelPhone)
        model.login(sentinelToken)

        XCTAssertEqual(spy.lastArgs["email"], sentinelEmail)
        XCTAssertEqual(spy.lastArgs["phone"], sentinelPhone)
        XCTAssertEqual(spy.lastArgs["clientKey"], sentinelKey)
        let joined = model.log.rows.joined(separator: "\n")
        for secret in [sentinelEmail, sentinelPhone, sentinelKey, sentinelToken, "SENTINEL"] {
            XCTAssertFalse(joined.contains(secret), "log leaked \(secret)")
        }
        XCTAssertFalse(String(describing: model.config).contains(sentinelKey))
    }

    func test_everyUserCallIsForwardedOnce() {
        let (model, spy) = model()
        model.login("u"); model.logout()
        model.setEmail("e@example.invalid"); model.clearEmail()
        model.setPhone("+000"); model.clearPhone()
        model.setSubscription(false); model.setLocationSharing(true)
        model.addTag(key: "k", value: "v"); model.addTags("a=1, b=2"); model.removeTag("k"); model.removeTags("a, b")
        XCTAssertEqual(spy.calls, [
            "login", "logout", "setEmail", "clearEmail", "setPhone", "clearPhone",
            "setSubscription", "setLocationSharingEnabled", "addTag", "addTags", "removeTag", "removeTags"
        ])
        XCTAssertEqual(spy.lastArgs["tags"], "a,b")
        XCTAssertEqual(spy.lastArgs["keys"], "a,b")
    }

    func test_blankInputIsSkippedWithoutCallingTheSdk() {
        let (model, spy) = model()
        model.login("  "); model.setEmail(""); model.setPhone(" "); model.addTag(key: " ", value: "v")
        model.addTags("no-equals, =novalue"); model.removeTag(""); model.removeTags(" , ")
        XCTAssertEqual(spy.calls, [])
        XCTAssertEqual(model.log.rows.count, 7)
        XCTAssertTrue(model.log.rows.allSatisfy { $0.hasSuffix(": skipped") })
    }

    func test_tagParsingKeepsValidPairsOnly() {
        XCTAssertEqual(ExampleModel.parseTags("a=1, b = 2 ,bad,=x, c="), ["a": "1", "b": "2", "c": ""])
        XCTAssertEqual(ExampleModel.parseKeys(" a, ,b ,"), ["a", "b"])
    }

    func test_permissionBothVariantsUpdateStateAndLog() async {
        let (model, spy) = model()
        await model.requestPermission()
        XCTAssertEqual(model.permission, "granted")
        spy.permissionResult = false
        model.requestPermissionWithCompletion()
        await Task.yield()
        XCTAssertEqual(model.permission, "denied")
        XCTAssertEqual(spy.calls, ["requestPermission", "requestPermissionCompletion"])
        XCTAssertTrue(model.log.rows.contains("permission: denied"))
    }

    func test_listenersLogKeysOnlyAndRemoveCleanly() {
        let (model, spy) = model()
        model.startListening()
        model.startListening()
        XCTAssertEqual(spy.calls, ["addReceivedListener", "addClickedListener", "addDeviceIdChangedListener"])
        XCTAssertTrue(model.isListening)

        spy.receivedHandler?(["notification_id", "secret-key-name"])
        spy.clickedHandler?(["delivery_id"])
        spy.deviceIdHandler?("device-new")
        XCTAssertEqual(model.deviceId, "device-new")
        XCTAssertTrue(model.log.rows.contains("received: keys [notification_id, +1 other]"))
        XCTAssertTrue(model.log.rows.contains("clicked: keys [delivery_id]"))
        XCTAssertFalse(model.log.rows.joined().contains("secret-key-name"))
        XCTAssertFalse(model.log.rows.joined().contains("device-new"))

        model.stopListening()
        XCTAssertEqual(spy.removedListeners, 3)
        XCTAssertFalse(model.isListening)
    }

    func test_takeInitialClickLogsKeysWhenThereIsOne() {
        let (model, spy) = model()
        spy.initialClickKeys = ["notification_id", "x"]
        model.takeInitialClick()
        XCTAssertTrue(model.log.rows.contains("clicked: keys [notification_id, +1 other]"))
        spy.initialClickKeys = nil
        model.takeInitialClick()
        XCTAssertEqual(spy.calls, ["takeInitialClick", "takeInitialClick"])
    }

    func test_logLevelRoundTripsThroughTheSdk() {
        let (model, _) = model()
        model.setLogLevel(.verbose)
        XCTAssertEqual(model.logLevel, .verbose)
    }
}

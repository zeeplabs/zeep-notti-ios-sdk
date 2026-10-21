import XCTest
@testable import NottiExample

final class ExampleConfigTests: XCTestCase {
    private func config(appId: String = "app-synthetic", key: String = "key-synthetic", host: String = "") -> ExampleConfig {
        ExampleConfig(appId: appId, clientKey: key, host: host)
    }

    func test_realLookingSyntheticValuesAreConfigured() {
        XCTAssertTrue(config().isConfigured)
    }

    func test_emptyValuesAreNotConfigured() {
        XCTAssertFalse(config(appId: "").isConfigured)
        XCTAssertFalse(config(key: "").isConfigured)
        XCTAssertFalse(config(appId: "  ", key: "\n").isConfigured)
    }

    func test_fixtureValuesAreNotConfigured() {
        XCTAssertFalse(config(appId: "fixture", key: "fixture").isConfigured)
        XCTAssertFalse(config(appId: "Fixture").isConfigured)
        XCTAssertFalse(config(key: "fixture").isConfigured)
    }

    func test_unsubstitutedBuildSettingsAreNotConfigured() {
        XCTAssertFalse(config(appId: "$(NOTTI_APP_ID)").isConfigured)
        XCTAssertFalse(config(key: "$(NOTTI_CLIENT_KEY)").isConfigured)
    }

    func test_bareHostBecomesHttpsUrl() {
        XCTAssertEqual(config(host: "h.example.invalid").baseUrl, "https://h.example.invalid")
        XCTAssertEqual(config(host: " h.example.invalid ").baseUrl, "https://h.example.invalid")
    }

    func test_emptyOrUnsubstitutedHostKeepsTheSdkDefault() {
        XCTAssertNil(config(host: "").baseUrl)
        XCTAssertNil(config(host: "$(NOTTI_HOST)").baseUrl)
    }

    func test_missingInfoPlistKeysDoNotCrashAndAreNotConfigured() {
        let empty = ExampleConfig(bundle: Bundle(for: ExampleConfigTests.self))
        XCTAssertFalse(empty.isConfigured)
        XCTAssertNil(empty.baseUrl)
    }

    func test_descriptionNeverPrintsTheClientKeyOrAppId() {
        let text = String(describing: config(appId: "app-sentinel-id", key: "key-sentinel-secret", host: "h.example.invalid"))
        XCTAssertFalse(text.contains("app-sentinel-id"))
        XCTAssertFalse(text.contains("key-sentinel-secret"))
        XCTAssertFalse(text.contains("h.example.invalid"))
    }
}

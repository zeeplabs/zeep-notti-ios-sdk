import XCTest
@testable import NottiSDK

final class PrivacyManifestTests: XCTestCase {
    private func loadManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(
            NottiSDKResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy missing from the NottiSDK resource bundle"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    func test_manifestIsBundled() throws {
        XCTAssertNotNil(
            NottiSDKResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
    }

    func test_manifestDeclaresNoTrackingUserDefaultsAndCollectedDataTypes() throws {
        let manifest = try loadManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)

        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        XCTAssertEqual(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])

        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertEqual(types, [
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypePhoneNumber",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeDeviceID",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData",
            "NSPrivacyCollectedDataTypeOtherDataTypes"
        ])
        for entry in collected {
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        }
    }

    func test_deviceIdIsDeclaredForAppFunctionalityOnly() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let deviceId = collected.first {
            $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeDeviceID"
        }
        XCTAssertEqual(
            deviceId?["NSPrivacyCollectedDataTypePurposes"] as? [String],
            ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        )
    }

    func test_userIdIsDeclaredForAppFunctionalityOnly() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let userId = collected.first {
            $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeUserID"
        }
        XCTAssertEqual(
            userId?["NSPrivacyCollectedDataTypePurposes"] as? [String],
            ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        )
    }
}

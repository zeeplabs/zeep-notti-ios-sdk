import XCTest
@testable import NottiSDKExtension

final class PrivacyManifestTests: XCTestCase {
    func test_manifestIsBundledAndDeclaresNoRequiredReasonApi() throws {
        let url = try XCTUnwrap(
            NottiSDKExtensionResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy missing from the NottiSDKExtension resource bundle"
        )
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertTrue(apis.isEmpty, "the extension calls no required-reason API (fileSizeKey only)")
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertTrue(collected.isEmpty)
    }
}

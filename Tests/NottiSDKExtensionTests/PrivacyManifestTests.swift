import XCTest
@testable import NottiSDKExtension

final class PrivacyManifestTests: XCTestCase {
    func test_manifestIsBundledAndDeclaresFileTimestamp() throws {
        let url = try XCTUnwrap(
            NottiSDKExtensionResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy missing from the NottiSDKExtension resource bundle"
        )
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let fileTimestamp = apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
        }
        XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
    }
}

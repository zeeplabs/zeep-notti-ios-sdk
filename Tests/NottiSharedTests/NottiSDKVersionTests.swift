import XCTest
@testable import NottiShared

final class NottiSDKVersionTests: XCTestCase {
    func test_currentIsASemanticVersion() {
        let pattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#
        XCTAssertNotNil(
            NottiSDKVersion.current.range(of: pattern, options: .regularExpression),
            "NottiSDKVersion.current must be semver, got \(NottiSDKVersion.current)"
        )
    }

    /// AD-025: the wire values are asserted as literals, never through the constant.
    func test_platformAndNameAreTheWireLiteralsOfThisBuild() {
        #if os(macOS)
            XCTAssertEqual(NottiSDKVersion.platform, "macos")
            XCTAssertEqual(NottiSDKVersion.name, "macos")
        #else
            XCTAssertEqual(NottiSDKVersion.platform, "ios")
            XCTAssertEqual(NottiSDKVersion.name, "ios")
        #endif
    }
}

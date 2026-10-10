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
}

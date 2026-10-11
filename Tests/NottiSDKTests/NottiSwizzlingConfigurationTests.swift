import XCTest
@testable import NottiSDK

final class NottiSwizzlingConfigurationTests: XCTestCase {

    func test_nilDictionaryKeepsSwizzlingOn() {
        let config = NottiSwizzlingConfiguration(infoDictionary: nil)

        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.invalidValueWarning)
    }

    func test_missingKeyKeepsSwizzlingOn() {
        let config = NottiSwizzlingConfiguration(infoDictionary: ["CFBundleName": "fixture"])

        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.invalidValueWarning)
    }

    func test_booleanFalseKeepsSwizzlingOn() {
        let config = NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: false])

        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.invalidValueWarning)
    }

    func test_booleanTrueTurnsSwizzlingOff() {
        let config = NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: true])

        XCTAssertFalse(config.isEnabled)
        XCTAssertFalse(config.invalidValueWarning)
    }

    func test_stringValueKeepsSwizzlingOnAndWarns() {
        for value in ["YES", "true", "fixture"] {
            let config = NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: value])

            XCTAssertTrue(config.isEnabled, value)
            XCTAssertTrue(config.invalidValueWarning, value)
        }
    }

    func test_numberValueKeepsSwizzlingOnAndWarns() {
        for value in [1, 0, 2] {
            let config = NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: value])

            XCTAssertTrue(config.isEnabled, "\(value)")
            XCTAssertTrue(config.invalidValueWarning, "\(value)")
        }
    }

    func test_nsNumberBooleanTrueTurnsSwizzlingOff() {
        // What a decoded Info.plist `<true/>` looks like.
        let config = NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: NSNumber(value: true)])

        XCTAssertFalse(config.isEnabled)
    }

    // G1 (DEL-02): the key is the public Info.plist contract. These two use the literal on purpose:
    // a test that read the constant would follow a typo in it instead of catching it.
    func test_infoPlistKeyIsTheDocumentedLiteral() {
        XCTAssertEqual(NottiSwizzlingConfiguration.infoPlistKey, "NottiDisableSwizzling")
    }

    func test_literalNottiDisableSwizzlingKeyTurnsSwizzlingOff() {
        let config = NottiSwizzlingConfiguration(infoDictionary: ["NottiDisableSwizzling": true])

        XCTAssertFalse(config.isEnabled)
        XCTAssertFalse(config.invalidValueWarning)
    }
}

import XCTest
@testable import NottiSDKExtension

final class NottiRichMediaURLTests: XCTestCase {
    // The key is written as a literal on purpose (NSE-18): the code reads `NottiPayloadKeys.imageUrl`.
    private let key = "notti_image_url"

    private func parse(_ value: Any?) -> NottiRichMediaURL.Parsed {
        var userInfo: [AnyHashable: Any] = ["aps": ["mutable-content": 1]]
        if let value { userInfo[key] = value }
        return NottiRichMediaURL.parse(userInfo)
    }

    func test_missingKeyIsAbsent() {
        XCTAssertEqual(NottiRichMediaURL.parse(["aps": [:]]), .absent)
    }

    func test_nonStringValuesAreAbsent() {
        XCTAssertEqual(parse(42), .absent)
        XCTAssertEqual(parse(["url": "https://media.example.invalid/a.png"]), .absent)
        XCTAssertEqual(parse(URL(string: "https://media.example.invalid/a.png")!), .absent)
    }

    func test_emptyStringIsInvalid() {
        XCTAssertEqual(parse(""), .invalid)
    }

    func test_unparsableTextIsInvalid() {
        XCTAssertEqual(parse("not a url with spaces"), .invalid)
        XCTAssertEqual(parse("https://exa mple.invalid/a.png"), .invalid)
    }

    func test_fileSchemeIsInvalid() {
        XCTAssertEqual(parse("file:///fixture/a.png"), .invalid)
    }

    func test_httpSchemeIsInvalid() {
        XCTAssertEqual(parse("http://media.example.invalid/a.png"), .invalid)
    }

    func test_ftpSchemeIsInvalid() {
        XCTAssertEqual(parse("ftp://media.example.invalid/a.png"), .invalid)
    }

    func test_customSchemeIsInvalid() {
        XCTAssertEqual(parse("fixture-scheme://media.example.invalid/a.png"), .invalid)
    }

    func test_httpsWithoutHostIsInvalid() {
        XCTAssertEqual(parse("https:///a.png"), .invalid)
        XCTAssertEqual(parse("https:a.png"), .invalid)
    }

    func test_uppercaseSchemeIsValid() {
        let text = "HTTPS://media.example.invalid/a.png"
        XCTAssertEqual(parse(text), .valid(URL(string: text)!))
    }

    func test_validHttpsUrlIsValid() {
        let text = "https://media.example.invalid/path/a.png?fixture=1"
        XCTAssertEqual(parse(text), .valid(URL(string: text)!))
    }
}

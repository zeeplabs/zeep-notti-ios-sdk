import XCTest
@testable import NottiSDKExtension

final class NottiRichMediaDropReasonTests: XCTestCase {
    func test_defaultLimitsAreTheContractLiterals() {
        XCTAssertEqual(NottiRichMediaLimits.default.maxBytes, 10_485_760)
        XCTAssertEqual(NottiRichMediaLimits.default.deadline, 20)
        XCTAssertEqual(NottiRichMediaLimits().maxBytes, 10_485_760)
        XCTAssertEqual(NottiRichMediaLimits().deadline, 20)
    }

    func test_fixedCodesAreLiterals() {
        XCTAssertEqual(NottiRichMediaDropReason.invalidURL.code, "invalid_url")
        XCTAssertEqual(NottiRichMediaDropReason.redirectNotHTTPS.code, "redirect_not_https")
        XCTAssertEqual(NottiRichMediaDropReason.httpStatus(404).code, "http_404")
        XCTAssertEqual(NottiRichMediaDropReason.oversize.code, "oversize")
        XCTAssertEqual(NottiRichMediaDropReason.noFile.code, "no_file")
        XCTAssertEqual(NottiRichMediaDropReason.deadline.code, "deadline")
        XCTAssertEqual(NottiRichMediaDropReason.expired.code, "expired")
    }

    func test_errorReasonsCarryOnlyDomainAndCode() {
        XCTAssertEqual(
            NottiRichMediaDropReason.transport(domain: "NSURLErrorDomain", code: -1001).code,
            "transport:NSURLErrorDomain#-1001"
        )
        XCTAssertEqual(
            NottiRichMediaDropReason.moveFailed(domain: "NSCocoaErrorDomain", code: 4).code,
            "move_failed:NSCocoaErrorDomain#4"
        )
        XCTAssertEqual(
            NottiRichMediaDropReason.attachmentRejected(domain: "UNErrorDomain", code: 100).code,
            "attachment_rejected:UNErrorDomain#100"
        )
    }

    func test_errorReasonsNeverUseTheErrorMessageOrUserInfo() {
        let sentinel = "https://sentinel.example.invalid/secret?token=fixture"
        let error = NSError(
            domain: "FixtureDomain",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: sentinel,
                NSURLErrorFailingURLStringErrorKey: sentinel,
                NSURLErrorFailingURLErrorKey: URL(string: sentinel)!
            ]
        )
        XCTAssertEqual(NottiRichMediaDropReason.transport(error).code, "transport:FixtureDomain#7")
        XCTAssertEqual(NottiRichMediaDropReason.moveFailed(error).code, "move_failed:FixtureDomain#7")
        XCTAssertEqual(
            NottiRichMediaDropReason.attachmentRejected(error).code, "attachment_rejected:FixtureDomain#7"
        )
        for reason in [
            NottiRichMediaDropReason.transport(error), .moveFailed(error), .attachmentRejected(error)
        ] {
            XCTAssertFalse(reason.code.contains("sentinel"))
            XCTAssertFalse(reason.code.contains("https"))
        }
    }
}

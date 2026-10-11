import UserNotifications
import XCTest
@testable import NottiSDKExtension
@testable import NottiShared

/// NSE-18: the frozen contract values, asserted as literals and not through the constants the code reads
/// (the `delegate-integration` G1 lesson: a test that reads the same constant as the code passes when the
/// constant is wrong). The registry's 16-job bound is an implementation detail, not contract.
final class NottiRichMediaContractTests: NottiRichMediaJobTestCase {
    func test_theKeyIsNottiImageUrlAndTheParserReadsExactlyThatKey() {
        XCTAssertEqual(NottiPayloadKeys.imageUrl, "notti_image_url")

        let url = "https://media.example.invalid/fixture/media.png"
        XCTAssertEqual(NottiRichMediaURL.parse(["notti_image_url": url]), .valid(URL(string: url)!))
        XCTAssertEqual(NottiRichMediaURL.parse(["notti-image-url": url]), .absent)
        XCTAssertEqual(NottiRichMediaURL.parse(["image_url": url]), .absent)
    }

    func test_theSizeCapIs10MiBAsALiteralAndEnforcedAtThatBoundary() {
        XCTAssertEqual(NottiRichMediaLimits.default.maxBytes, 10485760)
        XCTAssertEqual(NottiRichMediaEnvironment.live.limits.maxBytes, 10485760)

        // One byte over, declared by the server: dropped before the body. One byte under: not an oversize drop.
        StubURLProtocol.register(
            StubURLProtocol.Behavior(headers: ["Content-Type": "image/png"], declaredLength: 10485761, chunks: [Data(count: 16)]),
            for: mediaURL
        )
        let (_, over) = startJob(environment: makeEnvironment(limits: .default))
        waitForHandler(over)
        settle()
        XCTAssertEqual(logs.messages, ["rich media dropped: oversize"])
    }

    func test_aBodyDeclaredAtExactlyTheCapIsNotCutOff() {
        StubURLProtocol.register(
            StubURLProtocol.Behavior(headers: ["Content-Type": "image/png"], declaredLength: 10485760, chunks: [MediaSamples.png]),
            for: mediaURL
        )
        let (_, recorder) = startJob(environment: makeEnvironment(limits: .default))
        waitForHandler(recorder)
        settle()

        XCTAssertFalse(logs.messages.contains { $0.contains("oversize") })
        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
    }

    func test_theDeadlineIs20SecondsAsALiteral() {
        XCTAssertEqual(NottiRichMediaLimits.default.deadline, 20)
        XCTAssertEqual(NottiRichMediaEnvironment.live.limits.deadline, 20)
    }

    func test_theFiveAllowedMimeTypesMapToTheirExtensions() {
        let plain = URL(string: "https://media.example.invalid/fixture")!
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/jpeg", url: plain), "jpg")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/png", url: plain), "png")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/gif", url: plain), "gif")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "video/mp4", url: plain), "mp4")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "audio/mpeg", url: plain), "mp3")
    }

    func test_onlyTheFiveUrlExtensionsAreTrustedAndTheDefaultIsJpg() {
        let base = "https://media.example.invalid/fixture/file."
        for ext in ["jpg", "png", "gif", "mp4", "mp3"] {
            XCTAssertEqual(
                NottiMediaFileType.fileExtension(mimeType: nil, url: URL(string: base + ext)!), ext
            )
        }
        for ext in ["webp", "heic", "mov", "wav", "jpeg", "txt"] {
            XCTAssertEqual(
                NottiMediaFileType.fileExtension(mimeType: nil, url: URL(string: base + ext)!), "jpg",
                "\(ext) must not be trusted"
            )
        }
        XCTAssertEqual(
            NottiMediaFileType.fileExtension(mimeType: "image/webp", url: URL(string: base + "png")!), "png"
        )
        XCTAssertEqual(
            NottiMediaFileType.fileExtension(mimeType: nil, url: URL(string: "https://media.example.invalid/fixture")!), "jpg"
        )
    }

    func test_theTwoPublicSelectorsAndTheClassNameAreTheDocumentedOnes() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString("NottiNotificationServiceExtension"))
        XCTAssertTrue(cls.responds(to: NSSelectorFromString("didReceive:withContentHandler:")))
        XCTAssertTrue(cls.responds(to: NSSelectorFromString("serviceExtensionTimeWillExpireFor:contentHandler:")))
    }
}

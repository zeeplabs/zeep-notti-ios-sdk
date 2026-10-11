import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-01/02/03/11/12 through the facade, with an injected environment (the OS does not run an NSE in the
/// simulator, so the helper is called directly).
final class NottiNotificationServiceExtensionTests: NottiRichMediaJobTestCase {
    private typealias Behavior = StubURLProtocol.Behavior
    private typealias Facade = NottiNotificationServiceExtension

    /// A request whose content is a notification with `notti_image_url` set to `value` (when not nil).
    private func makeRequest(
        imageURL value: Any?, extra: [AnyHashable: Any] = [:]
    ) -> UNNotificationRequest {
        let content = makeOriginalContent()
        var userInfo = content.userInfo
        if let value { userInfo["notti_image_url"] = value }
        for (key, item) in extra { userInfo[key] = item }
        content.userInfo = userInfo
        return UNNotificationRequest(identifier: "fixture-request", content: content, trigger: nil)
    }

    private func deliver(
        _ request: UNNotificationRequest, environment: NottiRichMediaEnvironment? = nil
    ) -> Recorder {
        let recorder = Recorder()
        Facade.didReceive(
            request, withContentHandler: { recorder.record($0) },
            environment: environment ?? makeEnvironment()
        )
        return recorder
    }

    func test_aValidUrlAttachesOnceAndKeepsEveryOtherField() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)
        let request = makeRequest(imageURL: mediaURL.absoluteString)

        let recorder = deliver(request)
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        let content = recorder.contents[0]
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.title, "fixture title")
        XCTAssertEqual(content.subtitle, "fixture subtitle")
        XCTAssertEqual(content.body, "fixture body")
        XCTAssertEqual(content.badge, 3)
        XCTAssertEqual(content.categoryIdentifier, "fixture-category")
        XCTAssertEqual(content.threadIdentifier, "fixture-thread")
        XCTAssertTrue((content.userInfo as NSDictionary).isEqual(to: request.content.userInfo))
        XCTAssertEqual(logs.messages, [])
    }

    func test_anUppercaseHttpsSchemeIsAccepted() {
        let upper = URL(string: "HTTPS://media.example.invalid/fixture/upper.png")!
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: upper)

        let recorder = deliver(makeRequest(imageURL: "HTTPS://media.example.invalid/fixture/upper.png"))
        waitForHandler(recorder)

        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
    }

    func test_aMissingKeyCallsTheHandlerOnceStartsNoRequestAndLogsNothing() {
        let recorder = deliver(makeRequest(imageURL: nil))
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [])
        XCTAssertEqual(logs.messages, [])
    }

    func test_aNonStringValueIsTreatedAsMissing() {
        let recorder = deliver(makeRequest(imageURL: 42))
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(StubURLProtocol.requestedURLs, [])
        XCTAssertEqual(logs.messages, [])
    }

    private func assertInvalid(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let recorder = deliver(makeRequest(imageURL: value))
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1, file: file, line: line)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0, file: file, line: line)
        XCTAssertEqual(StubURLProtocol.requestedURLs, [], file: file, line: line)
        XCTAssertEqual(logs.messages, ["rich media dropped: invalid_url"], file: file, line: line)
        XCTAssertEqual(logs.lines.first?.level, .error, file: file, line: line)
        XCTAssertFalse(logs.messages.joined().contains("fixture"), file: file, line: line)
    }

    func test_aFileUrlIsInvalid() { assertInvalid("file:///fixture/media.png") }
    func test_anHttpUrlIsInvalid() { assertInvalid("http://media.example.invalid/fixture/media.png") }
    func test_anEmptyStringIsInvalid() { assertInvalid("") }

    func test_aNonSuccessStatusCallsTheHandlerOnceWithTheOriginalContent() {
        StubURLProtocol.register(.body(Data("fixture".utf8), mimeType: "text/plain", status: 500), for: mediaURL)

        let request = makeRequest(imageURL: mediaURL.absoluteString)
        let recorder = deliver(request)
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        XCTAssertEqual(recorder.contents.first?.title, "fixture title")
        XCTAssertTrue((recorder.contents[0].userInfo as NSDictionary).isEqual(to: request.content.userInfo))
        XCTAssertEqual(logs.messages, ["rich media dropped: http_500"])
    }

    func test_contentThatCannotBeCopiedCallsTheHandlerOnceWithTheRequestContent() throws {
        final class UncopyableContent: UNNotificationContent {
            override func mutableCopy(with zone: NSZone? = nil) -> Any { NSObject() }
        }
        let request = UNNotificationRequest(identifier: "fixture-request", content: UncopyableContent(), trigger: nil)
        try XCTSkipUnless(request.content is UncopyableContent, "the system copied the content into its own class")
        let recorder = Recorder()

        Facade.didReceive(request, withContentHandler: { recorder.record($0) }, environment: makeEnvironment())
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.contents.first === request.content)
        XCTAssertEqual(StubURLProtocol.requestedURLs, [])
    }

    // MARK: - Expiry

    private func expire(
        _ content: UNNotificationContent?, environment: NottiRichMediaEnvironment, recorder: Recorder
    ) {
        Facade.serviceExtensionTimeWillExpire(
            for: content, contentHandler: { recorder.record($0) }, environment: environment
        )
    }

    func test_expiryThroughTheFacadeCancelsTheMatchingJobAndCallsTheHandlerOnce() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let environment = makeEnvironment()
        let request = makeRequest(imageURL: mediaURL.absoluteString)
        let recorder = deliver(request, environment: environment)
        settle(0.2)

        let host = makeOriginalContent()
        host.userInfo = request.content.userInfo
        host.title = "host best attempt"
        expire(host, environment: environment, recorder: Recorder())
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.contents.first === host)
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopCount(for: mediaURL), 1)
        XCTAssertEqual(logs.messages, ["rich media dropped: expired"])
    }

    func test_expiryWithNilContentCallsNoHandler() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let environment = makeEnvironment()
        let jobRecorder = deliver(makeRequest(imageURL: mediaURL.absoluteString), environment: environment)
        let expiryRecorder = Recorder()
        settle(0.2)

        expire(nil, environment: environment, recorder: expiryRecorder)
        settle()

        XCTAssertEqual(expiryRecorder.count, 0)
        XCTAssertEqual(jobRecorder.count, 0)
        XCTAssertEqual(StubURLProtocol.stopCount(for: mediaURL), 0)

        // Clean up the in-flight job.
        let host = makeOriginalContent()
        expire(host, environment: environment, recorder: Recorder())
        waitForHandler(jobRecorder)
    }

    func test_expiryWithNoMatchingJobCallsTheHostHandlerDirectly() {
        let environment = makeEnvironment()
        let recorder = Recorder()
        let host = makeOriginalContent()

        expire(host, environment: environment, recorder: recorder)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.contents.first === host)
        XCTAssertEqual(logs.messages, [])
    }

    func test_expiryLeavesAJobOfAnotherNotificationRunning() {
        let otherURL = URL(string: "https://media.example.invalid/fixture/other.png")!
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        StubURLProtocol.register(Behavior.neverResponds, for: otherURL)
        let environment = makeEnvironment()
        let first = makeRequest(imageURL: mediaURL.absoluteString, extra: ["delivery_id": "fixture-1"])
        let second = makeRequest(imageURL: otherURL.absoluteString, extra: ["delivery_id": "fixture-2"])
        let firstRecorder = deliver(first, environment: environment)
        let secondRecorder = deliver(second, environment: environment)
        settle(0.2)

        let host = makeOriginalContent()
        host.userInfo = first.content.userInfo
        expire(host, environment: environment, recorder: Recorder())
        waitForHandler(firstRecorder)
        settle()

        XCTAssertEqual(firstRecorder.count, 1)
        XCTAssertEqual(secondRecorder.count, 0)
        XCTAssertEqual(StubURLProtocol.stopCount(for: otherURL), 0)

        let hostTwo = makeOriginalContent()
        hostTwo.userInfo = second.content.userInfo
        expire(hostTwo, environment: environment, recorder: Recorder())
        waitForHandler(secondRecorder)
    }

    func test_expiryStillFindsTheJobWhenTheHostChangedAnotherUserInfoKey() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let environment = makeEnvironment()
        let request = makeRequest(imageURL: mediaURL.absoluteString)
        let recorder = deliver(request, environment: environment)
        settle(0.2)

        let host = makeOriginalContent()
        var mutated = request.content.userInfo
        mutated["host_added"] = "fixture"
        host.userInfo = mutated
        let expiryRecorder = Recorder()
        expire(host, environment: environment, recorder: expiryRecorder)
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(expiryRecorder.count, 0)
        XCTAssertTrue(recorder.contents.first === host)
    }
}

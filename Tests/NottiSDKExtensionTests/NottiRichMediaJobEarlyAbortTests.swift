import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-04 and NSE-17: refuse a non-https redirect and an oversize body before the body is read.
final class NottiRichMediaJobEarlyAbortTests: NottiRichMediaJobTestCase {
    private typealias Behavior = StubURLProtocol.Behavior
    private let httpTarget = URL(string: "http://media.example.invalid/fixture/target.png")!
    private let httpsTarget = URL(string: "https://cdn.example.invalid/fixture/target.png")!
    private let chunk = Data(count: 64 * 1024)

    private func assertDropped(
        _ recorder: Recorder, log expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(recorder.count, 1, file: file, line: line)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0, file: file, line: line)
        if let content = recorder.contents.first { assertFieldsEqualToOriginal(content, file: file, line: line) }
        XCTAssertEqual(logs.messages, ["rich media dropped: \(expected)"], file: file, line: line)
        XCTAssertEqual(directoryContents(), [], file: file, line: line)
    }

    /// Goals: only https is ever fetched, after redirects too. The refused target must not even be requested.
    private func assertNoHttpRequest(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(
            StubURLProtocol.requestedURLs.filter { $0.scheme?.lowercased() != "https" }, [], file: file, line: line
        )
    }

    func test_aRedirectToHttpEndsBeforeAnyBodyByteIsServedEvenWhenTheStubIgnoresTheRefusal() {
        StubURLProtocol.register(.redirect(to: httpTarget), for: mediaURL)
        // A target that would happily serve a body if it were ever contacted.
        StubURLProtocol.register(
            Behavior(headers: ["Content-Type": "image/png"], chunks: Array(repeating: chunk, count: 20), chunkInterval: 0.01),
            for: httpTarget
        )

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        assertDropped(recorder, log: "redirect_not_https")
        XCTAssertEqual(StubURLProtocol.servedBytes(for: httpTarget), 0)
        assertNoHttpRequest()
    }

    func test_aRedirectToHttpWhoseTargetNeverRespondsStillEndsAtOnce() {
        StubURLProtocol.register(.redirect(to: httpTarget), for: mediaURL)
        StubURLProtocol.register(Behavior.neverResponds, for: httpTarget)

        let (_, recorder) = startJob()
        waitForHandler(recorder, timeout: 5)
        settle()

        assertDropped(recorder, log: "redirect_not_https")
        assertNoHttpRequest()
    }

    func test_aRedirectChainThatEndsOnHttpsStillAttaches() {
        StubURLProtocol.register(.redirect(to: httpsTarget), for: mediaURL)
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: httpsTarget)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(logs.messages, [])
        XCTAssertEqual(directoryContents().count, 1)
    }

    func test_aDeclaredLengthOverTheCapIsCancelledBeforeTheBody() {
        StubURLProtocol.register(
            Behavior(
                headers: ["Content-Type": "image/png"], declaredLength: 11 * 1024 * 1024,
                chunks: Array(repeating: chunk, count: 150), chunkInterval: 0.02
            ),
            for: mediaURL
        )

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        assertDropped(recorder, log: "oversize")
        XCTAssertLessThan(StubURLProtocol.servedBytes(for: mediaURL), 2 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopCount(for: mediaURL), 1)
    }

    func test_aBodyWithNoLengthIsCancelledOnceTheCapIsCrossed() {
        let oneMiB = Data(count: 1024 * 1024)
        StubURLProtocol.register(
            Behavior(headers: ["Content-Type": "image/png"], endlessChunk: oneMiB, finishes: false)
                .with(interval: 0.01),
            for: mediaURL
        )

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        assertDropped(recorder, log: "oversize")
        let served = StubURLProtocol.servedBytes(for: mediaURL)
        XCTAssertGreaterThan(served, 10 * 1024 * 1024)
        XCTAssertLessThan(served, 16 * 1024 * 1024)
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopCount(for: mediaURL), 1)
    }
}

private extension StubURLProtocol.Behavior {
    func with(interval: TimeInterval) -> StubURLProtocol.Behavior {
        var copy = self
        copy.chunkInterval = interval
        return copy
    }
}

import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-11 (job side): expiry cancels the job, one handler call, a late completion adds none.
final class NottiRichMediaJobExpiryTests: NottiRichMediaJobTestCase {
    private typealias Behavior = StubURLProtocol.Behavior

    private func hostContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "host best attempt"
        return content
    }

    func test_expireOnAnInFlightJobCancelsItAndCallsTheHandlerOnceWithTheHostContent() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let (job, recorder) = startJob()
        settle(0.2)

        let host = hostContent()
        job.expire(with: host)
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(recorder.contents.first === host)
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopCount(for: mediaURL), 1)
        XCTAssertEqual(directoryContents(), [])
        XCTAssertEqual(logs.messages, ["rich media dropped: expired"])
        XCTAssertEqual(logs.lines.first?.level, .error)
    }

    func test_aLateCompletionAfterExpiryAddsNoCallAndNoFile() {
        // The body would finish at about 0.6 s; the expiry lands first.
        StubURLProtocol.register(
            Behavior(
                headers: ["Content-Type": "image/png"],
                chunks: [MediaSamples.png, Data()], chunkInterval: 0.6
            ),
            for: mediaURL
        )
        let (job, recorder) = startJob()
        settle(0.2)

        job.expire(with: hostContent())
        waitForHandler(recorder)
        settle(1.0)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        XCTAssertEqual(directoryContents(), [])
    }

    func test_expireOnAFinishedJobCallsNothing() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)
        let (job, recorder) = startJob()
        waitForHandler(recorder)

        job.expire(with: hostContent())
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
        XCTAssertEqual(logs.messages, [])
    }

    func test_aSecondExpireCallsNothing() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let (job, recorder) = startJob()

        job.expire(with: hostContent())
        job.expire(with: hostContent())
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(logs.messages, ["rich media dropped: expired"])
    }

    func test_theDeadlineAfterAnExpiryAddsNoCall() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let (job, recorder) = startJob(environment: makeEnvironment(limits: NottiRichMediaLimits(deadline: 0.3)))

        job.expire(with: hostContent())
        waitForHandler(recorder)
        settle(0.8)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(logs.messages, ["rich media dropped: expired"])
    }

    func test_expiringOneOfTwoInFlightJobsLeavesTheOtherRunning() {
        let otherURL = URL(string: "https://media.example.invalid/fixture/other.png")!
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        StubURLProtocol.register(Behavior.neverResponds, for: otherURL)
        let (first, firstRecorder) = startJob()
        let (second, secondRecorder) = startJob(url: otherURL)
        settle(0.2)

        first.expire(with: hostContent())
        waitForHandler(firstRecorder)
        settle()

        XCTAssertEqual(firstRecorder.count, 1)
        XCTAssertEqual(secondRecorder.count, 0)
        XCTAssertEqual(StubURLProtocol.stopCount(for: otherURL), 0)

        second.expire(with: hostContent())
        waitForHandler(secondRecorder)
        XCTAssertEqual(secondRecorder.count, 1)
    }

    func test_theJobKeepsTheUserInfoOfItsNotification() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)
        let (job, recorder) = startJob()

        XCTAssertTrue(job.userInfo.isEqual(makeOriginalContent().userInfo as NSDictionary))
        job.expire(with: hostContent())
        waitForHandler(recorder)
    }
}

import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-10: one deadline for the whole download.
final class NottiRichMediaJobDeadlineTests: NottiRichMediaJobTestCase {
    private typealias Behavior = StubURLProtocol.Behavior

    private func shortDeadline(_ seconds: TimeInterval = 0.2) -> NottiRichMediaEnvironment {
        makeEnvironment(limits: NottiRichMediaLimits(deadline: seconds))
    }

    func test_aStubThatNeverFinishesEndsAtTheDeadlineWithTheTaskCancelledAndNoFile() {
        StubURLProtocol.register(Behavior.neverResponds, for: mediaURL)

        let (_, recorder) = startJob(environment: shortDeadline())
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertGreaterThanOrEqual(StubURLProtocol.stopCount(for: mediaURL), 1)
        XCTAssertEqual(directoryContents(), [])
        XCTAssertEqual(logs.messages, ["rich media dropped: deadline"])
        XCTAssertEqual(logs.lines.first?.level, .error)
    }

    func test_aResponseThatTricklesBytesStillEndsAtTheDeadline() {
        // 20 small chunks every 50 ms would take 1 s and finish; the deadline at 0.2 s must win.
        StubURLProtocol.register(
            Behavior(
                headers: ["Content-Type": "image/png"], declaredLength: 1024,
                chunks: Array(repeating: Data(count: 50), count: 20), chunkInterval: 0.05
            ),
            for: mediaURL
        )
        let started = Date()

        let (_, recorder) = startJob(environment: shortDeadline())
        waitForHandler(recorder)
        let elapsed = Date().timeIntervalSince(started)
        settle(1.2)

        XCTAssertLessThan(elapsed, 0.9)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(logs.messages, ["rich media dropped: deadline"])
        XCTAssertEqual(directoryContents(), [])
    }

    func test_aJobThatFinishesFirstCancelsTheTimer() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)

        let (_, recorder) = startJob(environment: shortDeadline(0.5))
        waitForHandler(recorder)
        settle(1.0)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
        XCTAssertEqual(logs.messages, [])
    }

    func test_theDeadlineIsMeasuredFromStartNotFromTheLastByte() {
        StubURLProtocol.register(
            Behavior(headers: ["Content-Type": "image/png"], chunkInterval: 0.02, endlessChunk: Data(count: 10), finishes: false),
            for: mediaURL
        )

        let (_, recorder) = startJob(environment: shortDeadline(0.3))
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(logs.messages, ["rich media dropped: deadline"])
    }

    func test_aResponseThatSendsLargeChunksStillEndsAtTheDeadlineBecauseProgressDoesNotRearmIt() {
        // 64 KiB chunks make URLSession call `didWriteData` on every chunk (50-byte chunks never do), so a
        // timer re-armed on progress would let this 1 s body finish. The 0.3 s deadline must win.
        StubURLProtocol.register(
            Behavior(
                headers: ["Content-Type": "image/png"],
                chunks: Array(repeating: Data(count: 64 * 1024), count: 20), chunkInterval: 0.05
            ),
            for: mediaURL
        )
        let started = Date()

        let (_, recorder) = startJob(environment: shortDeadline(0.3))
        waitForHandler(recorder)
        let elapsed = Date().timeIntervalSince(started)
        settle(1.2)

        XCTAssertLessThan(elapsed, 0.8)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        XCTAssertEqual(logs.messages, ["rich media dropped: deadline"])
        XCTAssertEqual(directoryContents(), [])
    }

    /// NSE-09 on the race path: a completion that lands while the deadline or an expiry wins must not leave
    /// the moved file behind. Whatever the interleaving, files on disk equal attachments delivered.
    func test_aCompletionRacingTheDeadlineOrExpiryLeavesNoFileWithoutAnAttachment() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)
        let racers = DispatchQueue(label: "nse.race", attributes: .concurrent)
        var recorders: [Recorder] = []
        for _ in 0..<300 {
            let deadline = Double.random(in: 0.0003...0.006)
            let (job, recorder) = startJob(environment: shortDeadline(deadline))
            recorders.append(recorder)
            let delay = Double.random(in: 0...0.006)
            racers.asyncAfter(deadline: .now() + delay) { job.expire(with: UNMutableNotificationContent()) }
        }

        for recorder in recorders { waitForHandler(recorder, timeout: 10) }
        settle(1.5)

        XCTAssertTrue(recorders.allSatisfy { $0.count == 1 })
        let attached = recorders.filter { $0.contents.first?.attachments.count == 1 }.count
        XCTAssertEqual(directoryContents().count, attached)
    }
}

import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-01 and NSE-05: the happy path per media type and the simple drops.
final class NottiRichMediaJobTests: NottiRichMediaJobTestCase {
    private func assertAttached(
        mimeType: String, data: Data, expectedExtension: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        StubURLProtocol.register(.body(data, mimeType: mimeType), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1, file: file, line: line)
        guard let content = recorder.contents.first else { return XCTFail("no content", file: file, line: line) }
        XCTAssertEqual(content.attachments.count, 1, file: file, line: line)
        XCTAssertEqual(content.attachments.first?.url.pathExtension, expectedExtension, file: file, line: line)
        assertFieldsEqualToOriginal(content, file: file, line: line)
        XCTAssertEqual(logs.messages, [], file: file, line: line)
    }

    func test_pngIsAttached() {
        assertAttached(mimeType: "image/png", data: MediaSamples.png, expectedExtension: "png")
    }

    func test_jpgIsAttached() {
        assertAttached(mimeType: "image/jpeg", data: MediaSamples.jpg, expectedExtension: "jpg")
    }

    func test_gifIsAttached() {
        assertAttached(mimeType: "image/gif", data: MediaSamples.gif, expectedExtension: "gif")
    }

    func test_mp4IsAttached() {
        assertAttached(mimeType: "video/mp4", data: MediaSamples.mp4, expectedExtension: "mp4")
    }

    func test_mp3IsAttached() {
        assertAttached(mimeType: "audio/mpeg", data: MediaSamples.mp3, expectedExtension: "mp3")
    }

    func test_successLeavesOnlyTheAttachmentFileInTheDirectory() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)

        let files = directoryContents()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first, recorder.contents.first?.attachments.first?.url.lastPathComponent)
    }

    func test_notFoundDropsWithTheUntouchedContent() {
        StubURLProtocol.register(.body(Data("fixture".utf8), mimeType: "text/plain", status: 404), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(directoryContents(), [])
        XCTAssertEqual(logs.messages, ["rich media dropped: http_404"])
        XCTAssertEqual(logs.lines.first?.level, .error)
    }

    func test_transportErrorDropsWithDomainAndCodeOnly() {
        StubURLProtocol.register(.failure(URLError(.notConnectedToInternet)), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(directoryContents(), [])
        XCTAssertEqual(logs.messages, ["rich media dropped: transport:NSURLErrorDomain#-1009"])
    }

    func test_completionWithoutAFileDropsAsNoFile() {
        // A completion with no error and no file never comes from a 2xx download task, so the delegate
        // method is called directly on a job that has not received a file.
        let recorder = Recorder()
        let gate = NottiHandlerGate { recorder.record($0) }
        // swiftlint:disable:next force_cast
        let copy = makeOriginalContent().mutableCopy() as! UNMutableNotificationContent
        let job = NottiRichMediaJob(content: copy, gate: gate, environment: makeEnvironment())
        let scratch = URLSession(configuration: .ephemeral)
        defer { scratch.invalidateAndCancel() }

        job.urlSession(scratch, task: scratch.downloadTask(with: mediaURL), didCompleteWithError: nil)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(logs.messages, ["rich media dropped: no_file"])
    }

    // The job must be released after every path: `finish` invalidates the session, which drops its delegate.

    private func assertReleased(
        register: () -> Void, file: StaticString = #filePath, line: UInt = #line
    ) {
        register()
        let recorder = Recorder()
        weak var weakJob: NottiRichMediaJob?
        // The pool matters: objects autoreleased while starting a job would otherwise outlive the test method.
        autoreleasepool {
            let started = startJob(recorder: recorder, retain: false)
            weakJob = started.job
        }
        waitForHandler(recorder)

        let released = expectation(description: "job released")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(5)
            while weakJob != nil && Date() < deadline { usleep(20_000) }
            released.fulfill()
        }
        wait(for: [released], timeout: 10)
        XCTAssertNil(weakJob, "the job is still alive after it finished", file: file, line: line)
    }

    func test_theJobIsReleasedAfterSuccess() {
        assertReleased { StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL) }
    }

    func test_theJobIsReleasedAfterAStatusDrop() {
        assertReleased { StubURLProtocol.register(.body(Data(), status: 500), for: mediaURL) }
    }

    func test_theJobIsReleasedAfterATransportDrop() {
        assertReleased { StubURLProtocol.register(.failure(URLError(.timedOut)), for: mediaURL) }
    }
}

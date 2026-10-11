import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-04 (final URL), NSE-06, NSE-08 and NSE-09: what the job checks once the file is on disk.
final class NottiRichMediaJobDropTests: NottiRichMediaJobTestCase {
    private func assertDropped(
        _ recorder: Recorder, log expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(recorder.count, 1, file: file, line: line)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0, file: file, line: line)
        if let content = recorder.contents.first { assertFieldsEqualToOriginal(content, file: file, line: line) }
        XCTAssertEqual(logs.messages.count, 1, file: file, line: line)
        XCTAssertTrue(
            logs.messages.first?.hasPrefix("rich media dropped: \(expected)") ?? false,
            "unexpected log \(logs.messages)", file: file, line: line
        )
        XCTAssertEqual(directoryContents(), [], file: file, line: line)
    }

    func test_aFinalUrlThatIsNotHttpsIsDiscarded() {
        let finalURL = URL(string: "http://media.example.invalid/fixture/final.png")!
        StubURLProtocol.register(
            StubURLProtocol.Behavior(
                headers: ["Content-Type": "image/png"], chunks: [MediaSamples.png], responseURL: finalURL
            ),
            for: mediaURL
        )

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        assertDropped(recorder, log: "redirect_not_https")
    }

    /// Calls the delegate with a file of the given size, as the system does when a download completes.
    private func finishDownload(
        bytes: Int, limits: NottiRichMediaLimits, recorder: Recorder
    ) -> URL {
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("NottiRichMediaTests-source-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: location.path, contents: Data(count: bytes))
        addTeardownBlock { try? FileManager.default.removeItem(at: location) }
        let gate = NottiHandlerGate { recorder.record($0) }
        // swiftlint:disable:next force_cast
        let copy = makeOriginalContent().mutableCopy() as! UNMutableNotificationContent
        let job = NottiRichMediaJob(content: copy, gate: gate, environment: makeEnvironment(limits: limits))
        let scratch = URLSession(configuration: .ephemeral)
        defer { scratch.invalidateAndCancel() }
        job.urlSession(scratch, downloadTask: scratch.downloadTask(with: mediaURL), didFinishDownloadingTo: location)
        return location
    }

    func test_aFileOverTheCapIsDeletedAndNotAttached() {
        let recorder = Recorder()
        let limits = NottiRichMediaLimits(maxBytes: 1024, deadline: 20)

        let location = finishDownload(bytes: 1025, limits: limits, recorder: recorder)

        assertDropped(recorder, log: "oversize")
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    func test_aFileExactlyAtTheCapIsAccepted() {
        let recorder = Recorder()
        let limits = NottiRichMediaLimits(maxBytes: 1024, deadline: 20)

        _ = finishDownload(bytes: 1024, limits: limits, recorder: recorder)

        // Zero bytes of fixture data are not a valid image, so the OS may still refuse the attachment.
        // The point here is that the size check did not drop it.
        XCTAssertEqual(recorder.count, 1)
        XCTAssertFalse(logs.messages.contains { $0.contains("oversize") })
    }

    func test_aDirectoryThatCannotBeWrittenDropsAsMoveFailed() throws {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("NottiRichMediaTests-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        let unwritable = blocker.appendingPathComponent("media", isDirectory: true)
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)

        let (_, recorder) = startJob(environment: makeEnvironment(directory: unwritable))
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.contents.first?.attachments.count, 0)
        assertFieldsEqualToOriginal(recorder.contents[0])
        XCTAssertEqual(logs.messages.count, 1)
        XCTAssertTrue(logs.messages[0].hasPrefix("rich media dropped: move_failed:NSCocoaErrorDomain#"))
        XCTAssertFalse(logs.messages[0].contains(blocker.lastPathComponent))
    }

    func test_bytesTheSystemRejectsDropAsAttachmentRejectedAndTheMovedFileIsDeleted() {
        // An MP3 above the system's audio limit passes the 10 MiB cap and is refused by `UNNotificationAttachment`.
        let tooBigForAudio = Data(count: 6 * 1024 * 1024)
        StubURLProtocol.register(.body(tooBigForAudio, mimeType: "audio/mpeg"), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        assertDropped(recorder, log: "attachment_rejected:")
    }

    func test_aSuccessfulAttachmentIsTheOnlyFileInTheDirectory() {
        StubURLProtocol.register(.body(MediaSamples.gif, mimeType: "image/gif"), for: mediaURL)

        let (_, recorder) = startJob()
        waitForHandler(recorder)
        settle()

        XCTAssertEqual(recorder.contents.first?.attachments.count, 1)
        XCTAssertEqual(directoryContents().count, 1)
    }
}

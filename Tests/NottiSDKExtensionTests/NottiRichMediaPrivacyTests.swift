import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// NSE-13, NSE-09 and the goal "never twice": one test per path of the facade, each with a sentinel in the URL
/// host, path and query and in the title and body. After every path: no log line holds a sentinel, the handler
/// ran exactly once (checked after a grace period), and the directory is clean (or holds only the attachment).
final class NottiRichMediaPrivacyTests: NottiRichMediaJobTestCase {
    private typealias Behavior = StubURLProtocol.Behavior
    private typealias Facade = NottiNotificationServiceExtension

    private let sentinels = ["sentinel-host", "sentinel-path", "sentinel-query", "sentinel-title", "sentinel-body"]
    private let sentinelURLString = "https://sentinel-host.example.invalid/sentinel-path/media.png?token=sentinel-query"
    private var sentinelURL: URL { URL(string: sentinelURLString)! }

    private func makeRequest(imageURL: Any?) -> UNNotificationRequest {
        let content = makeOriginalContent()
        content.title = "sentinel-title"
        content.body = "sentinel-body"
        var userInfo = content.userInfo
        if let imageURL { userInfo["notti_image_url"] = imageURL }
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

    private func finishPath(
        _ recorder: Recorder, log expected: String?, attached: Bool = false, grace: TimeInterval = 0.5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        waitForHandler(recorder)
        settle(grace)

        XCTAssertEqual(recorder.count, 1, "handler must run exactly once", file: file, line: line)
        XCTAssertEqual(recorder.contents.first?.attachments.count, attached ? 1 : 0, file: file, line: line)
        for message in logs.messages {
            for sentinel in sentinels {
                XCTAssertFalse(message.contains(sentinel), "log line leaked \(sentinel)", file: file, line: line)
            }
        }
        if let expected {
            XCTAssertEqual(logs.lines.count, 1, file: file, line: line)
            XCTAssertEqual(logs.lines.first?.level, .error, file: file, line: line)
            XCTAssertTrue(
                logs.messages.first?.hasPrefix("rich media dropped: \(expected)") ?? false,
                "unexpected log: \(logs.messages)", file: file, line: line
            )
        } else {
            XCTAssertEqual(logs.messages, [], file: file, line: line)
        }
        XCTAssertEqual(directoryContents().count, attached ? 1 : 0, file: file, line: line)
    }

    func test_pathSuccess() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: sentinelURL)
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: nil, attached: true)
    }

    func test_pathAbsent() {
        finishPath(deliver(makeRequest(imageURL: nil)), log: nil)
    }

    func test_pathInvalidScheme() {
        finishPath(
            deliver(makeRequest(imageURL: "ftp://sentinel-host.example.invalid/sentinel-path?token=sentinel-query")),
            log: "invalid_url"
        )
    }

    func test_pathHttpScheme() {
        finishPath(
            deliver(makeRequest(imageURL: "http://sentinel-host.example.invalid/sentinel-path?token=sentinel-query")),
            log: "invalid_url"
        )
    }

    func test_pathNotFound() {
        StubURLProtocol.register(.body(Data("fixture".utf8), mimeType: "text/plain", status: 404), for: sentinelURL)
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: "http_404")
    }

    func test_pathTransportError() {
        // An error whose userInfo carries the URL, as URLSession's own errors do.
        let error = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
            userInfo: [
                NSURLErrorFailingURLStringErrorKey: sentinelURLString,
                NSLocalizedDescriptionKey: "sentinel-host sentinel-path sentinel-query"
            ]
        )
        StubURLProtocol.register(.failure(error), for: sentinelURL)
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: "transport:NSURLErrorDomain#-1009")
    }

    func test_pathOversizeDeclaredEarly() {
        StubURLProtocol.register(
            Behavior(
                headers: ["Content-Type": "image/png"], declaredLength: 11 * 1024 * 1024,
                chunks: Array(repeating: Data(count: 64 * 1024), count: 40), chunkInterval: 0.02
            ),
            for: sentinelURL
        )
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: "oversize")
    }

    func test_pathOversizeByBytesWithNoHeader() {
        StubURLProtocol.register(
            Behavior(headers: ["Content-Type": "image/png"], chunks: [Data(count: 4096)]),
            for: sentinelURL
        )
        let environment = makeEnvironment(limits: NottiRichMediaLimits(maxBytes: 1024, deadline: 20))
        finishPath(deliver(makeRequest(imageURL: sentinelURLString), environment: environment), log: "oversize")
    }

    func test_pathOversizeAfterDownload() {
        // The second barrier: the delegate callback with a finished file over the cap, as a direct call.
        let recorder = Recorder()
        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("NottiRichMediaTests-source-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: location.path, contents: Data(count: 2048))
        addTeardownBlock { try? FileManager.default.removeItem(at: location) }
        // swiftlint:disable:next force_cast
        let copy = makeOriginalContent().mutableCopy() as! UNMutableNotificationContent
        copy.title = "sentinel-title"
        copy.body = "sentinel-body"
        let job = NottiRichMediaJob(
            content: copy, gate: NottiHandlerGate { recorder.record($0) },
            environment: makeEnvironment(limits: NottiRichMediaLimits(maxBytes: 1024, deadline: 20))
        )
        let scratch = URLSession(configuration: .ephemeral)
        defer { scratch.invalidateAndCancel() }

        job.urlSession(scratch, downloadTask: scratch.downloadTask(with: sentinelURL), didFinishDownloadingTo: location)

        finishPath(recorder, log: "oversize")
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    func test_pathRedirectToHttp() {
        let target = URL(string: "http://sentinel-host.example.invalid/sentinel-path/target.png?token=sentinel-query")!
        StubURLProtocol.register(.redirect(to: target), for: sentinelURL)
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: target)
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: "redirect_not_https")
    }

    func test_pathAttachmentRejected() {
        StubURLProtocol.register(.body(Data(count: 6 * 1024 * 1024), mimeType: "audio/mpeg"), for: sentinelURL)
        finishPath(deliver(makeRequest(imageURL: sentinelURLString)), log: "attachment_rejected:")
    }

    func test_pathDeadline() {
        StubURLProtocol.register(Behavior.neverResponds, for: sentinelURL)
        let environment = makeEnvironment(limits: NottiRichMediaLimits(deadline: 0.3))
        finishPath(deliver(makeRequest(imageURL: sentinelURLString), environment: environment), log: "deadline")
    }

    func test_pathExpiry() {
        StubURLProtocol.register(Behavior.neverResponds, for: sentinelURL)
        let environment = makeEnvironment()
        let request = makeRequest(imageURL: sentinelURLString)
        let recorder = deliver(request, environment: environment)
        settle(0.2)

        let host = makeOriginalContent()
        host.title = "sentinel-title"
        host.body = "sentinel-body"
        host.userInfo = request.content.userInfo
        Facade.serviceExtensionTimeWillExpire(
            for: host, contentHandler: { _ in XCTFail("the expiry handler must not run for a matched job") },
            environment: environment
        )

        finishPath(recorder, log: "expired")
    }

    /// The sink cannot see the category (`NottiShared` is out of scope for this feature), so the category is
    /// enforced on the source: every `NottiLogger.log` call in the extension must name category `nse`.
    func test_everyLogCallInTheExtensionSourcesUsesCategoryNse() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NottiSDKExtension")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        try XCTSkipIf(files.isEmpty, "extension sources are not reachable from the test host")

        var calls = 0
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("NottiLogger.log(") {
                calls += 1
                XCTAssertTrue(line.contains("category: \"nse\""), "\(file): log call without category nse")
            }
        }
        XCTAssertGreaterThanOrEqual(calls, 2)
    }
}

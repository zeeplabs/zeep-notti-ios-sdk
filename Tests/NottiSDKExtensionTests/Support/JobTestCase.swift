import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// Shared setup for the `NottiRichMediaJob*` tests: stub routes, a per-test temp directory, a log sink
/// and a handler recorder. Nothing here touches the network.
class NottiRichMediaJobTestCase: XCTestCase {
    final class Recorder {
        private let lock = NSLock()
        private var storage: [UNNotificationContent] = []
        let called = XCTestExpectation(description: "content handler called")

        init() { called.assertForOverFulfill = false }

        func record(_ content: UNNotificationContent) {
            lock.lock(); storage.append(content); lock.unlock()
            called.fulfill()
        }

        var contents: [UNNotificationContent] { lock.withLock { storage } }
        var count: Int { contents.count }
    }

    let mediaURL = URL(string: "https://media.example.invalid/fixture/media.png")!
    let logs = LogSink()
    var directory: URL!
    private var liveJobs: [NottiRichMediaJob] = []

    /// The first `UNNotificationAttachment` in a process on a clean simulator takes up to ~20 s (measured on
    /// a freshly created iPhone 17 Pro, iOS 26.5: 20.2 s, then 9 ms), longer than any `waitForHandler`. Pay it
    /// once, here, where nothing is timed, so the first test that attaches media does not time out.
    private static let attachmentWarmUp: Void = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NottiAttachmentWarmUp-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("warmup.png")
            try MediaSamples.png.write(to: file)
            _ = try UNNotificationAttachment(identifier: "warm-up", url: file, options: nil)
        } catch {
            // Best effort: a failure here only brings the old cold-start timing back.
        }
    }()

    override class func setUp() {
        super.setUp()
        _ = attachmentWarmUp
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        logs.install()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NottiRichMediaTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        liveJobs.removeAll()
        try? FileManager.default.removeItem(at: directory)
        logs.uninstall()
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// A notification content with every field the helper must leave alone.
    func makeOriginalContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "fixture title"
        content.subtitle = "fixture subtitle"
        content.body = "fixture body"
        content.sound = .default
        content.badge = 3
        content.categoryIdentifier = "fixture-category"
        content.threadIdentifier = "fixture-thread"
        content.userInfo = ["aps": ["mutable-content": 1], "delivery_id": "delivery-fixture"]
        return content
    }

    func makeEnvironment(
        limits: NottiRichMediaLimits = .default, directory: URL? = nil
    ) -> NottiRichMediaEnvironment {
        NottiRichMediaEnvironment(
            makeConfiguration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [StubURLProtocol.self]
                return configuration
            },
            limits: limits,
            directory: directory ?? self.directory
        )
    }

    /// Starts a job over `makeOriginalContent()`'s copy. The test keeps the job alive in `liveJobs`
    /// unless `retain` is false (used by the release tests).
    @discardableResult
    func startJob(
        url: URL? = nil, environment: NottiRichMediaEnvironment? = nil, recorder: Recorder = Recorder(),
        retain: Bool = true
    ) -> (job: NottiRichMediaJob, recorder: Recorder) {
        let gate = NottiHandlerGate { recorder.record($0) }
        // swiftlint:disable:next force_cast
        let copy = makeOriginalContent().mutableCopy() as! UNMutableNotificationContent
        let job = NottiRichMediaJob(content: copy, gate: gate, environment: environment ?? makeEnvironment())
        if retain { liveJobs.append(job) }
        job.start(url: url ?? mediaURL)
        return (job, recorder)
    }

    func waitForHandler(_ recorder: Recorder, timeout: TimeInterval = 5) {
        wait(for: [recorder.called], timeout: timeout)
    }

    /// Lets a late second handler call (or a late callback) show up before a count is asserted.
    func settle(_ seconds: TimeInterval = 0.3) {
        let pause = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { pause.fulfill() }
        wait(for: [pause], timeout: seconds + 5)
    }

    func directoryContents() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func assertFieldsEqualToOriginal(
        _ content: UNNotificationContent, file: StaticString = #filePath, line: UInt = #line
    ) {
        let original = makeOriginalContent()
        XCTAssertEqual(content.title, original.title, file: file, line: line)
        XCTAssertEqual(content.subtitle, original.subtitle, file: file, line: line)
        XCTAssertEqual(content.body, original.body, file: file, line: line)
        XCTAssertEqual(content.sound, original.sound, file: file, line: line)
        XCTAssertEqual(content.badge, original.badge, file: file, line: line)
        XCTAssertEqual(content.categoryIdentifier, original.categoryIdentifier, file: file, line: line)
        XCTAssertEqual(content.threadIdentifier, original.threadIdentifier, file: file, line: line)
        XCTAssertTrue(
            (content.userInfo as NSDictionary).isEqual(to: original.userInfo), "userInfo changed",
            file: file, line: line
        )
    }
}

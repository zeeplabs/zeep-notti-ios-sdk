import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// Records every hop; runs `execute` inline so a pass is deterministic. The flusher never waits itself.
private final class RecordingScheduler: NottiInAppScheduling {
    private let lock = NSLock()
    private var executeCount = 0
    private var delays: [TimeInterval] = []

    var executed: Int { lock.withLock { executeCount } }
    var scheduledDelays: [TimeInterval] { lock.withLock { delays } }

    func execute(_ task: @escaping () -> Void) {
        lock.withLock { executeCount += 1 }
        task()
    }

    func schedule(after seconds: TimeInterval, _ task: @escaping () -> Void) {
        lock.withLock { delays.append(seconds) }
    }
}

/// IAM-30, IAM-31, IAM-32. Port of RN `runFlushPass` cases (`NottiInAppCoordinatorTests`, 0.8.0) over the
/// real store and client with `StubURLProtocol`. Statuses, the 7 day limit and `Retry-After` values are
/// literals. Synthetic values only; the `sentinel` values must never reach a log line.
final class NottiInAppEventFlusherTests: XCTestCase {

    private let appId = "sentinel-app"
    private let otherApp = "sentinel-other-app"
    private let identity = NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token")

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var now: Int64 = 1_000_000_000_000
    private var store: NottiInAppEventStore!
    private var session: URLSession!
    private var scheduler: RecordingScheduler!
    private var flusher: NottiInAppEventFlusher!
    private var logs: LogSink!
    private var savedLevel = NottiLogLevel.error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiInAppEventFlusherTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        now = 1_000_000_000_000
        store = NottiInAppEventStore(defaults: defaults, clock: { [unowned self] in self.now })
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        let client = NottiInAppApiClient(
            session: session, baseUrl: "https://api.example.invalid", appId: appId, clientKey: "sentinel-key"
        )!
        scheduler = RecordingScheduler()
        flusher = NottiInAppEventFlusher(store: store, reporter: client, scheduler: scheduler)
        let sink = LogSink()
        logs = sink
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        NottiLogger.sink = { _, message in sink.append(message) }
    }

    override func tearDown() {
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        flusher = nil
        store = nil
        super.tearDown()
    }

    private func pass(singleAttempt: Bool = false, headFailures: Int = 0) -> NottiInAppFlushOutcome? {
        let done = expectation(description: "pass")
        var outcome: NottiInAppFlushOutcome?
        flusher.runPass(appId: appId, identity: identity, singleAttempt: singleAttempt, headFailures: headFailures) {
            outcome = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return outcome
    }

    @discardableResult
    private func enqueue(_ type: String = "impression", app: String? = nil, message: String = "sentinel-message") -> NottiInAppEventRecord {
        store.enqueue(appId: app ?? appId, messageId: message, type: type, buttonId: type == "click" ? "sentinel-button" : nil)
    }

    private func sentBodies() -> [[String: Any]] {
        StubURLProtocol.recordedRequests().compactMap { request in
            request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    private func sentPaths() -> [String] {
        StubURLProtocol.recordedRequests().compactMap { $0.url?.path }
    }

    // MARK: - 2xx (IAM-31)

    private func assertSuccessRemovesAndContinues(_ status: Int, file: StaticString = #filePath, line: UInt = #line) {
        let first = enqueue()
        let second = enqueue("click")
        StubURLProtocol.enqueue(.status(status))
        StubURLProtocol.enqueue(.status(status))

        XCTAssertEqual(pass(), .done, file: file, line: line)

        XCTAssertTrue(store.all().isEmpty, file: file, line: line)
        XCTAssertEqual(sentBodies().compactMap { $0["event_id"] as? String }, [first.eventId, second.eventId], file: file, line: line)
        XCTAssertTrue(logs.messages.isEmpty, file: file, line: line)
    }

    func test_201RemovesTheRecordAndContinues() { assertSuccessRemovesAndContinues(201) }

    func test_200RemovesTheRecordAndContinues() { assertSuccessRemovesAndContinues(200) }

    func test_204RemovesTheRecordAndContinues() { assertSuccessRemovesAndContinues(204) }

    // MARK: - Permanent 4xx (IAM-31)

    private func assertDropRemovesLogsAndContinues(_ status: Int, file: StaticString = #filePath, line: UInt = #line) {
        enqueue()
        let second = enqueue("click")
        StubURLProtocol.enqueue(.status(status, body: "sentinel-body"))
        StubURLProtocol.enqueue(.status(201))

        XCTAssertEqual(pass(), .done, file: file, line: line)

        XCTAssertTrue(store.all().isEmpty, file: file, line: line)
        XCTAssertEqual(sentBodies().last?["event_id"] as? String, second.eventId, file: file, line: line)
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 2, file: file, line: line)
        XCTAssertEqual(logs.messages, ["Notti.inapp: event rejected by the server, dropped"], file: file, line: line)
    }

    func test_404RemovesTheRecordLogsOneFixedCodeAndContinues() { assertDropRemovesLogsAndContinues(404) }

    func test_422RemovesTheRecordLogsOneFixedCodeAndContinues() { assertDropRemovesLogsAndContinues(422) }

    func test_400RemovesTheRecordLogsOneFixedCodeAndContinues() { assertDropRemovesLogsAndContinues(400) }

    // MARK: - 401 and 403 (IAM-31)

    func test_401ReturnsUnauthorizedWithTheQueueIntact() {
        let first = enqueue()
        let second = enqueue("click")
        StubURLProtocol.enqueue(.status(401, body: "sentinel-body"))

        XCTAssertEqual(pass(), .unauthorized)

        XCTAssertEqual(store.all().map(\.id), [first.id, second.id])
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)
    }

    func test_403ReturnsForbiddenWithTheQueueIntact() {
        let first = enqueue()
        let second = enqueue("click")
        StubURLProtocol.enqueue(.status(403, body: "sentinel-body"))

        XCTAssertEqual(pass(), .forbidden)

        XCTAssertEqual(store.all().map(\.id), [first.id, second.id])
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)
    }

    func test_noLogLineCarriesATokenIdUrlOrBodyOnAnyPath() {
        for status in [401, 403, 404, 429, 503] {
            enqueue(message: "sentinel-message-\(status)")
            StubURLProtocol.enqueue(.status(status, body: "sentinel-body", headers: ["Retry-After": "7"]))
            _ = pass(singleAttempt: true)
        }
        now += 604_800_001
        _ = pass()

        XCTAssertFalse(logs.messages.isEmpty)
        for line in logs.messages {
            XCTAssertFalse(line.contains("sentinel"), line)
            XCTAssertFalse(line.contains("example.invalid"), line)
            XCTAssertFalse(line.contains("/v1/"), line)
        }
    }

    // MARK: - Transient (IAM-31)

    private func assertTransientBacksOffWithTheSameEventId(_ status: Int, file: StaticString = #filePath, line: UInt = #line) {
        let head = enqueue()
        let next = enqueue("click")
        var outcomes: [NottiInAppFlushOutcome?] = []
        for failures in 0..<5 {
            StubURLProtocol.enqueue(.status(status))
            outcomes.append(pass(headFailures: failures))
        }

        XCTAssertEqual(outcomes, [.backoff(failures: 1), .backoff(failures: 2), .backoff(failures: 3), .backoff(failures: 4), .failed],
                       file: file, line: line)
        XCTAssertEqual(sentBodies().compactMap { $0["event_id"] as? String }, Array(repeating: head.eventId, count: 5),
                       file: file, line: line)
        XCTAssertEqual(store.all().map(\.id), [head.id, next.id], file: file, line: line)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty, "the flusher never waits; the engine owns the backoff", file: file, line: line)
    }

    func test_408OnTheHeadBacksOffFourTimesWithTheSameEventIdThenFails() { assertTransientBacksOffWithTheSameEventId(408) }

    func test_503OnTheHeadBacksOffFourTimesWithTheSameEventIdThenFails() { assertTransientBacksOffWithTheSameEventId(503) }

    func test_singleAttemptModeFailsAfterOneRequest() {
        let head = enqueue()
        for response in [StubURLProtocol.StubResponse.status(408), .status(503), .networkError()] {
            StubURLProtocol.enqueue(response)
            XCTAssertEqual(pass(singleAttempt: true), .failed)
        }
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 3)
        XCTAssertEqual(store.all().map(\.id), [head.id])
    }

    func test_aSuccessResetsTheHeadFailureCount() {
        enqueue()
        let next = enqueue("click")
        StubURLProtocol.enqueue(.status(201))
        StubURLProtocol.enqueue(.status(503))

        XCTAssertEqual(pass(headFailures: 3), .backoff(failures: 1))
        XCTAssertEqual(store.all().map(\.id), [next.id])
    }

    // MARK: - 429 (IAM-31)

    func test_429ReturnsPausedWithTheUnclampedSecondsAndSendsNothingMore() {
        let first = enqueue()
        let second = enqueue("click")
        StubURLProtocol.enqueue(.status(429, headers: ["Retry-After": "7"]))
        StubURLProtocol.enqueue(.status(201))

        XCTAssertEqual(pass(), .paused(retryAfterSeconds: 7))

        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)
        XCTAssertEqual(store.all().map(\.id), [first.id, second.id])
    }

    func test_429WithoutRetryAfterIsNilAndALargeValueIsNotClamped() {
        enqueue()
        StubURLProtocol.enqueue(.status(429))
        XCTAssertEqual(pass(), .paused(retryAfterSeconds: nil))
        StubURLProtocol.enqueue(.status(429, headers: ["Retry-After": "1200"]))
        XCTAssertEqual(pass(), .paused(retryAfterSeconds: 1200))
        XCTAssertEqual(store.all().count, 1)
    }

    // MARK: - App purge, FIFO, expiry (IAM-30, IAM-32)

    func test_aRecordOfAnotherAppIsPurgedBeforeSendingAndNeverSent() {
        enqueue(app: otherApp, message: "sentinel-other-message")
        let mine = enqueue(message: "sentinel-mine")
        StubURLProtocol.enqueue(.status(201))
        StubURLProtocol.enqueue(.status(201))

        XCTAssertEqual(pass(), .done)

        XCTAssertEqual(sentPaths(), ["/v1/apps/sentinel-app/in-app-messages/sentinel-mine/events"])
        XCTAssertEqual(sentBodies().compactMap { $0["event_id"] as? String }, [mine.eventId])
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_onlyOtherAppRecordsMakeNoRequest() {
        enqueue(app: otherApp)
        enqueue("click", app: otherApp)

        XCTAssertEqual(pass(), .done)

        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_aFailingHeadIsNeverSkipped() {
        let impression = enqueue("impression")
        let click = enqueue("click")
        StubURLProtocol.enqueue(.status(503))
        StubURLProtocol.enqueue(.networkError())

        XCTAssertEqual(pass(), .backoff(failures: 1))
        XCTAssertEqual(pass(singleAttempt: true), .failed)

        XCTAssertEqual(sentBodies().compactMap { $0["type"] as? String }, ["impression", "impression"])
        XCTAssertEqual(store.all().map(\.id), [impression.id, click.id])
    }

    func test_recordsOlderThan7DaysAreRemovedWithoutARequest() {
        enqueue()
        now += 1
        let kept = enqueue("click")
        now += 604_800_000
        StubURLProtocol.enqueue(.status(201))

        XCTAssertEqual(pass(), .done)

        XCTAssertEqual(sentBodies().compactMap { $0["event_id"] as? String }, [kept.eventId])
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(logs.messages, ["Notti.inapp: expired events dropped"])
    }

    func test_anEmptyQueueIsDoneWithNoRequestAndNoLog() {
        XCTAssertEqual(pass(), .done)
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
        XCTAssertTrue(logs.messages.isEmpty)
    }

    func test_everyResponseIsHandledThroughTheScheduler() {
        enqueue()
        enqueue("click")
        StubURLProtocol.enqueue(.status(201))
        StubURLProtocol.enqueue(.status(404))

        XCTAssertEqual(pass(), .done)

        XCTAssertEqual(scheduler.executed, 2)
    }

    func test_theIdentityNeverPrintsItsValues() {
        let text = "\(identity) \(String(reflecting: identity))"
        XCTAssertFalse(text.contains("sentinel"))
    }
}

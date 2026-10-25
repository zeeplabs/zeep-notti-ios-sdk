import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-02, IAM-04, IAM-29, IAM-31. Port of the In-App cases of RN `NottiApiClientTests` (0.8.0) over the
/// non-blocking client. Paths, headers, body keys, statuses and `Retry-After` values are literals.
/// Synthetic values only.
final class NottiInAppApiClientTests: XCTestCase {

    private let deviceId = "fixture-device"
    private let messageId = "fixture-message"
    private var sessions: [URLSession] = []
    private var client: NottiInAppApiClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = makeClient(appId: "fixture-app")
    }

    override func tearDown() {
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    private func makeClient(appId: String, baseUrl: String = "https://api.example.invalid") -> NottiInAppApiClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        // A valid base URL always builds a client; `test_theBaseUrlIsValidatedAndNormalized` covers nil.
        return NottiInAppApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: "fixture-key")!
    }

    private func record(
        type: String = "impression",
        buttonId: String? = nil,
        reason: String? = nil,
        messageId: String? = nil,
        occurredAtMs: Int64 = 1_792_247_405_000
    ) -> NottiInAppEventRecord {
        NottiInAppEventRecord(
            id: "fixture-local", eventId: "00000000-0000-4000-8000-0000000000e1", appId: "fixture-app",
            messageId: messageId ?? self.messageId, type: type, buttonId: buttonId, reason: reason,
            occurredAtMs: occurredAtMs
        )
    }

    private func eligible(_ client: NottiInAppApiClient? = nil) -> NottiInAppEligibleResult? {
        let done = expectation(description: "eligible")
        var result: NottiInAppEligibleResult?
        (client ?? self.client).eligible(deviceId: deviceId, token: "fixture-token") { outcome in
            result = outcome
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result
    }

    private func report(_ event: NottiInAppEventRecord, _ client: NottiInAppApiClient? = nil) -> NottiInAppEventResult? {
        let done = expectation(description: "report")
        var result: NottiInAppEventResult?
        (client ?? self.client).report(event, deviceId: deviceId, token: "fixture-token") { outcome in
            result = outcome
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result
    }

    private func sentJson(_ index: Int) -> [String: Any] {
        let recorded = StubURLProtocol.recordedRequests()
        guard
            index < recorded.count,
            let body = recorded[index].httpBody,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            XCTFail("no JSON body for request \(index)")
            return [:]
        }
        return json
    }

    private func encodedPath(_ index: Int) -> String? {
        let recorded = StubURLProtocol.recordedRequests()
        guard index < recorded.count, let url = recorded[index].url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
    }

    private func isTransient(_ result: NottiInAppEligibleResult?) -> Bool {
        if case .transient = result { return true }
        return false
    }

    // MARK: - eligible (IAM-02)

    func test_eligibleSendsTheDocumentedRequestAndParsesTheMessages() throws {
        StubURLProtocol.enqueue(.status(
            200, body: #"{"messages":[{"id":"m1","title":"fixture","trigger":{"type":"session_start"}}]}"#
        ))

        let result = eligible()

        let recorded = StubURLProtocol.recordedRequests()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.httpMethod, "POST")
        XCTAssertEqual(recorded.first?.url?.host, "api.example.invalid")
        XCTAssertEqual(encodedPath(0), "/v1/apps/fixture-app/in-app-messages/eligible")
        XCTAssertEqual(recorded.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertEqual(recorded.first?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(recorded.first?.timeoutInterval, 15)
        let sent = sentJson(0)
        XCTAssertEqual(Set(sent.keys), ["device_id", "token"])
        XCTAssertEqual(sent["device_id"] as? String, "fixture-device")
        XCTAssertEqual(sent["token"] as? String, "fixture-token")
        guard case .messages(let messages) = try XCTUnwrap(result) else { return XCTFail("expected messages") }
        XCTAssertEqual(messages.map(\.id), ["m1"])
    }

    func test_eligibleWithAnEmptyMessagesArrayIsAValidResult() throws {
        StubURLProtocol.enqueue(.status(200, body: #"{"messages":[]}"#))

        guard case .messages(let messages) = try XCTUnwrap(eligible()) else { return XCTFail("expected messages") }
        XCTAssertTrue(messages.isEmpty)
    }

    func test_eligibleClassifiesEachStatusWithOneRequestEach() {
        StubURLProtocol.enqueue(.status(401))
        guard case .unauthorized = eligible() else { return XCTFail("401") }
        StubURLProtocol.enqueue(.status(403))
        guard case .forbidden = eligible() else { return XCTFail("403") }
        for status in [404, 422, 400] {
            StubURLProtocol.enqueue(.status(status))
            guard case .terminal(let code) = eligible() else { return XCTFail("status \(status)") }
            XCTAssertEqual(code, status)
        }
        for status in [408, 500, 503] {
            StubURLProtocol.enqueue(.status(status))
            XCTAssertTrue(isTransient(eligible()), "status \(status)")
        }
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 8)
    }

    func test_eligibleWithAnUnparseable2xxOrATransportErrorIsTransient() {
        StubURLProtocol.enqueue(.status(200, body: "<html>fixture portal</html>"))
        XCTAssertTrue(isTransient(eligible()))
        StubURLProtocol.enqueue(.status(200, body: #"{"messages":"fixture"}"#))
        XCTAssertTrue(isTransient(eligible()))
        StubURLProtocol.enqueue(.networkError())
        XCTAssertTrue(isTransient(eligible()))
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 3)
    }

    // MARK: - Retry-After (IAM-04, IAM-31)

    func test_eligible429CarriesRetryAfterAsUnclampedIntegerSecondsOrNil() {
        func retryAfter(_ header: String?) -> Int?? {
            StubURLProtocol.enqueue(.status(429, headers: header.map { ["Retry-After": $0] } ?? [:]))
            guard case .rateLimited(let seconds) = eligible() else {
                XCTFail("expected rateLimited for \(String(describing: header))")
                return .none
            }
            return .some(seconds)
        }
        XCTAssertEqual(retryAfter("7"), .some(7))
        XCTAssertEqual(retryAfter("0"), .some(0))
        XCTAssertEqual(retryAfter(" 120 "), .some(120))
        XCTAssertEqual(retryAfter("99999999999"), .some(2_147_483_647))
        XCTAssertEqual(retryAfter(nil), .some(nil))
        XCTAssertEqual(retryAfter("soon"), .some(nil))
        XCTAssertEqual(retryAfter("-5"), .some(nil))
        XCTAssertEqual(retryAfter("1.5"), .some(nil))
        XCTAssertEqual(retryAfter("Wed, 21 Oct 2026 07:28:00 GMT"), .some(nil))
    }

    func test_parseRetryAfterAcceptsOnlyAsciiDigits() {
        XCTAssertEqual(NottiInAppApiClient.parseRetryAfter(" 2 "), 2)
        XCTAssertEqual(NottiInAppApiClient.parseRetryAfter("2147483648"), 2_147_483_647)
        XCTAssertNil(NottiInAppApiClient.parseRetryAfter("+2"))
        XCTAssertNil(NottiInAppApiClient.parseRetryAfter(""))
        XCTAssertNil(NottiInAppApiClient.parseRetryAfter("   "))
        XCTAssertNil(NottiInAppApiClient.parseRetryAfter("\u{0663}"))
        XCTAssertNil(NottiInAppApiClient.parseRetryAfter(nil))
    }

    func test_events429CarriesRetryAfter() {
        StubURLProtocol.enqueue(.status(429, headers: ["Retry-After": "7"]))
        XCTAssertEqual(report(record()), .rateLimited(retryAfterSeconds: 7))
        StubURLProtocol.enqueue(.status(429, headers: ["Retry-After": " 120 "]))
        XCTAssertEqual(report(record()), .rateLimited(retryAfterSeconds: 120))
        StubURLProtocol.enqueue(.status(429))
        XCTAssertEqual(report(record()), .rateLimited(retryAfterSeconds: nil))
    }

    // MARK: - events (IAM-29)

    func test_eventsSendTheDocumentedRequestForEachType() {
        for _ in 0..<3 { StubURLProtocol.enqueue(.status(201, body: #"{"duplicate":false}"#)) }

        _ = report(record())
        _ = report(record(type: "click", buttonId: "fixture-button"))
        _ = report(record(type: "dismiss", reason: "auto"))

        let recorded = StubURLProtocol.recordedRequests()
        XCTAssertEqual(recorded.count, 3)
        XCTAssertEqual(recorded.first?.httpMethod, "POST")
        XCTAssertEqual(encodedPath(0), "/v1/apps/fixture-app/in-app-messages/fixture-message/events")
        XCTAssertEqual(recorded.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertEqual(recorded.first?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let impression = sentJson(0)
        XCTAssertEqual(Set(impression.keys), ["device_id", "token", "event_id", "type", "occurred_at"])
        XCTAssertEqual(impression["device_id"] as? String, "fixture-device")
        XCTAssertEqual(impression["token"] as? String, "fixture-token")
        XCTAssertEqual(impression["event_id"] as? String, "00000000-0000-4000-8000-0000000000e1")
        XCTAssertEqual(impression["type"] as? String, "impression")
        let click = sentJson(1)
        XCTAssertEqual(Set(click.keys), ["device_id", "token", "event_id", "type", "occurred_at", "button_id"])
        XCTAssertEqual(click["button_id"] as? String, "fixture-button")
        let dismiss = sentJson(2)
        XCTAssertEqual(Set(dismiss.keys), ["device_id", "token", "event_id", "type", "occurred_at", "reason"])
        XCTAssertEqual(dismiss["reason"] as? String, "auto")
    }

    func test_buttonIdAndReasonAreSentOnlyForTheirOwnType() {
        for _ in 0..<3 { StubURLProtocol.enqueue(.status(201)) }

        _ = report(record(buttonId: "fixture-button", reason: "auto"))
        _ = report(record(type: "click", reason: "auto"))
        _ = report(record(type: "dismiss", buttonId: "fixture-button"))

        for index in 0..<3 {
            XCTAssertEqual(Set(sentJson(index).keys), ["device_id", "token", "event_id", "type", "occurred_at"])
        }
    }

    func test_occurredAtIsUtcWithMilliseconds() {
        StubURLProtocol.enqueue(.status(201))
        StubURLProtocol.enqueue(.status(201))

        _ = report(record(occurredAtMs: 1_792_247_405_000))
        _ = report(record(occurredAtMs: 1_792_247_405_123))

        XCTAssertEqual(sentJson(0)["occurred_at"] as? String, "2026-10-17T14:30:05.000Z")
        XCTAssertEqual(sentJson(1)["occurred_at"] as? String, "2026-10-17T14:30:05.123Z")
    }

    func test_events2xxIsRecorded() {
        for status in [200, 201, 204] {
            StubURLProtocol.enqueue(.status(status, body: status == 200 ? #"{"duplicate":true}"# : ""))
            XCTAssertEqual(report(record()), .recorded, "status \(status)")
        }
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 3)
    }

    func test_eventsPermanent4xxIsDrop() {
        for status in [400, 404, 409, 422] {
            StubURLProtocol.enqueue(.status(status))
            XCTAssertEqual(report(record()), .drop, "status \(status)")
        }
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 4)
    }

    func test_events401And403StayDistinctAnd408And5xxAndTransportAreTransient() {
        StubURLProtocol.enqueue(.status(401))
        XCTAssertEqual(report(record()), .unauthorized)
        StubURLProtocol.enqueue(.status(403))
        XCTAssertEqual(report(record()), .forbidden)
        for status in [408, 500, 503] {
            StubURLProtocol.enqueue(.status(status))
            XCTAssertEqual(report(record()), .transient, "status \(status)")
        }
        StubURLProtocol.enqueue(.networkError())
        XCTAssertEqual(report(record()), .transient)
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 6)
    }

    // MARK: - Path encoding and config

    func test_eachPathComponentWithASpaceOrSlashIsOneEncodedSegment() {
        let hostile = makeClient(appId: "fixture app/x?y=1#f")
        StubURLProtocol.enqueue(.status(200, body: #"{"messages":[]}"#))
        StubURLProtocol.enqueue(.status(201))

        _ = eligible(hostile)
        _ = report(record(messageId: "fixture message/../x"), hostile)

        XCTAssertEqual(encodedPath(0), "/v1/apps/fixture%20app%2Fx%3Fy=1%23f/in-app-messages/eligible")
        XCTAssertEqual(encodedPath(1), "/v1/apps/fixture%20app%2Fx%3Fy=1%23f/in-app-messages/fixture%20message%2F..%2Fx/events")
        XCTAssertNil(StubURLProtocol.recordedRequests().first?.url?.query)
    }

    func test_theBaseUrlIsValidatedAndNormalized() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        XCTAssertNil(NottiInAppApiClient(session: session, baseUrl: "fixture not a url", appId: "a", clientKey: "k"))
        XCTAssertNil(NottiInAppApiClient(session: session, baseUrl: "", appId: "a", clientKey: "k"))

        let trailing = makeClient(appId: "fixture-app", baseUrl: "https://api.example.invalid/base//")
        StubURLProtocol.enqueue(.status(200, body: #"{"messages":[]}"#))
        _ = eligible(trailing)
        XCTAssertEqual(encodedPath(0), "/base/v1/apps/fixture-app/in-app-messages/eligible")
    }

    // MARK: - Privacy (IAM-43)

    func test_theClientLogsNothingOnAnyPath() {
        let sink = LogSink()
        let savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        NottiLogger.sink = { _, message in sink.append(message) }
        defer {
            NottiLogger.sink = nil
            NottiLogger.level = savedLevel
        }

        StubURLProtocol.enqueue(.status(200, body: "fixture-sentinel"))
        _ = eligible()
        StubURLProtocol.enqueue(.status(401, body: "fixture-sentinel"))
        _ = eligible()
        StubURLProtocol.enqueue(.networkError())
        _ = report(record())
        StubURLProtocol.enqueue(.status(422, body: "fixture-sentinel"))
        _ = report(record())

        XCTAssertTrue(sink.messages.isEmpty)
    }
}

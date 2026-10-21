import XCTest
@testable import NottiExample

@MainActor
final class ExampleLogTests: XCTestCase {
    private let sentinel = "SENTINEL-4f9a"

    func test_everyEventConstructorKeepsTheSentinelOutOfTheRows() {
        let log = ExampleLog()
        log.record(.notConfigured)
        for call in ExampleCall.allCases {
            log.record(.call(call, .ok))
            log.record(.call(call, .failed))
            log.record(.call(call, .skipped))
        }
        log.record(.permission(granted: true))
        log.record(.permission(granted: false))
        log.record(.payload(.received, keys: [sentinel]))
        log.record(.payload(.clicked, keys: [sentinel, "notification_id", "x-\(sentinel)"]))

        XCTAssertFalse(log.rows.isEmpty)
        XCTAssertFalse(log.rows.contains { $0.contains(sentinel) })
    }

    func test_payloadShowsKnownKeysAndCountsTheOthers() {
        let log = ExampleLog()
        log.record(.payload(.received, keys: ["delivery_id", "notification_id", "campaign", "segment"]))
        XCTAssertEqual(log.rows, ["received: keys [delivery_id, notification_id, +2 other]"])
    }

    func test_payloadWithNoKeysIsEmptyBrackets() {
        XCTAssertEqual(LogEvent.payload(.clicked, keys: []).text, "clicked: keys []")
    }

    func test_callRowNamesTheCallAndOutcomeOnly() {
        XCTAssertEqual(LogEvent.call(.setEmail, .ok).text, "setEmail: ok")
        XCTAssertEqual(LogEvent.call(.login, .failed).text, "login: failed")
    }

    func test_notConfiguredRowSaysTheSdkWasNotCalled() {
        let log = ExampleLog()
        log.record(.notConfigured)
        XCTAssertEqual(log.rows, ["not configured: Notti.initialize skipped"])
    }

    func test_rowsAreCappedAtTheMaximumAndKeepTheNewest() {
        let log = ExampleLog()
        for _ in 0..<(ExampleLog.maxRows + 25) { log.record(.call(.login, .ok)) }
        log.record(.call(.logout, .ok))
        XCTAssertEqual(log.rows.count, ExampleLog.maxRows)
        XCTAssertEqual(log.rows.last, "logout: ok")
    }

    func test_clearEmptiesTheRows() {
        let log = ExampleLog()
        log.record(.notConfigured)
        log.clear()
        XCTAssertTrue(log.rows.isEmpty)
    }
}

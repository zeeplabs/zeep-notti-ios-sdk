import XCTest
@testable import NottiShared

final class NottiLoggerTests: XCTestCase {
    private var captured: [(NottiLogLevel, String)] = []
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        savedLevel = NottiLogger.level
        captured = []
        NottiLogger.sink = { [weak self] level, message in self?.captured.append((level, message)) }
    }

    override func tearDown() {
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        super.tearDown()
    }

    func test_defaultLevelIsErrorOnly() {
        XCTAssertEqual(NottiLogger.defaultLevel, .error)

        NottiLogger.level = NottiLogger.defaultLevel
        NottiLogger.log(.warn, "careful")
        NottiLogger.log(.error, "boom")

        XCTAssertEqual(captured.map(\.1), ["boom"])
    }

    func test_messageAtOrAboveTheLevelReachesTheSink() {
        NottiLogger.level = .warn
        NottiLogger.log(.error, "boom")
        NottiLogger.log(.warn, "careful")

        XCTAssertEqual(captured.map(\.0), [.error, .warn])
        XCTAssertEqual(captured.map(\.1), ["boom", "careful"])
    }

    func test_messageBelowTheLevelIsDroppedWithoutEvaluatingIt() {
        NottiLogger.level = .error
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "noise"
        }

        NottiLogger.log(.debug, expensive())

        XCTAssertTrue(captured.isEmpty)
        XCTAssertFalse(evaluated)
    }

    func test_messageAtLevelNoneIsNeverEmittedEvenAtVerbose() {
        NottiLogger.level = .verbose
        var evaluated = false
        func expensive() -> String {
            evaluated = true
            return "noise"
        }

        NottiLogger.log(.none, expensive())

        XCTAssertTrue(captured.isEmpty)
        XCTAssertFalse(evaluated)
    }

    func test_levelNoneDropsEverything() {
        NottiLogger.level = .none
        NottiLogger.log(.error, "boom")

        XCTAssertTrue(captured.isEmpty)
    }
}

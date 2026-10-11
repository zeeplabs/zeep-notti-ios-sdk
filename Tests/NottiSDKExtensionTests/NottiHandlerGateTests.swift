import UserNotifications
import XCTest
@testable import NottiSDKExtension

final class NottiHandlerGateTests: XCTestCase {
    private final class Counter {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    func test_secondFireDoesNotCallTheHandler() {
        let counter = Counter()
        let gate = NottiHandlerGate { _ in counter.increment() }
        let content = UNMutableNotificationContent()

        XCTAssertTrue(gate.fire(content))
        XCTAssertFalse(gate.fire(content))
        XCTAssertEqual(counter.count, 1)
    }

    func test_manyConcurrentFiresCallTheHandlerOnce() {
        let counter = Counter()
        let gate = NottiHandlerGate { _ in counter.increment() }
        let content = UNMutableNotificationContent()
        let wins = Counter()

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            if gate.fire(content) { wins.increment() }
        }

        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(wins.count, 1)
    }

    func test_handlerRunsOutsideTheLock() {
        let counter = Counter()
        var gate: NottiHandlerGate!
        var reentrant: Bool?
        gate = NottiHandlerGate { content in
            counter.increment()
            // Would deadlock if the lock were still held.
            reentrant = gate.fire(content)
        }

        XCTAssertTrue(gate.fire(UNMutableNotificationContent()))
        XCTAssertEqual(reentrant, false)
        XCTAssertEqual(counter.count, 1)
    }
}

// Ported from react-native-notti 52e4b55 ios/Tests/NottiNetworkObserverTests.swift (AD-002).
// Changes: `@testable import NottiSDK`; the inline `FakePathMonitor` moved to `Support/FakePathMonitor.swift`.

import Network
import XCTest
@testable import NottiSDK

final class NottiNetworkObserverTests: XCTestCase {

    func test_transitionToSatisfiedTriggersAFlush() {
        let monitor = FakePathMonitor()
        var flushes = 0
        let observer = NottiNetworkObserver(monitor: monitor, onNetworkAvailable: { flushes += 1 })
        observer.start()
        XCTAssertEqual(monitor.startCount, 1)

        monitor.pathUpdateHandler?(.satisfied)
        XCTAssertEqual(flushes, 1, "the first observed satisfied path triggers a flush")

        monitor.pathUpdateHandler?(.satisfied)
        XCTAssertEqual(flushes, 1, "staying satisfied must not re-trigger")

        monitor.pathUpdateHandler?(.unsatisfied)
        monitor.pathUpdateHandler?(.satisfied)
        XCTAssertEqual(flushes, 2, "an offline -> online transition triggers again")
    }

    func test_noSatisfiedTransitionNeverFlushes() {
        let monitor = FakePathMonitor()
        var flushes = 0
        let observer = NottiNetworkObserver(monitor: monitor, onNetworkAvailable: { flushes += 1 })
        observer.start()

        monitor.pathUpdateHandler?(.unsatisfied)
        monitor.pathUpdateHandler?(.requiresConnection)

        XCTAssertEqual(flushes, 0)
    }

    func test_startIsIdempotent() {
        let monitor = FakePathMonitor()
        let observer = NottiNetworkObserver(monitor: monitor, onNetworkAvailable: {})

        observer.start()
        observer.start()

        XCTAssertEqual(monitor.startCount, 1, "a second start must be a no-op")
    }

    func test_cancelStopsTheUnderlyingMonitor() {
        let monitor = FakePathMonitor()
        let observer = NottiNetworkObserver(monitor: monitor, onNetworkAvailable: {})

        observer.start()
        observer.cancel()

        XCTAssertEqual(monitor.cancelCount, 1)
    }
}

import XCTest
@testable import NottiSDK

final class NottiListenerHubTests: XCTestCase {

    // MARK: - Test doubles

    /// Stands in for `NottiEventBuffer.setHandler`: records attach/detach, keeps
    /// the handler, and can replay a payload synchronously inside `attach`.
    private final class FakeSource {
        private let lock = NSLock()
        private var _handler: ((String) -> Void)?
        private var _attachCount = 0
        private var _detachCount = 0
        var replayOnAttach: String?
        /// Widens the window between the list update and the source call, so a
        /// missing lock shows up as a wrong final state.
        var callDelayMicros: UInt32 = 0

        var handler: ((String) -> Void)? { lock.withLock { _handler } }
        var attachCount: Int { lock.withLock { _attachCount } }
        var detachCount: Int { lock.withLock { _detachCount } }

        func attach(_ handler: @escaping (String) -> Void) {
            if callDelayMicros > 0 { usleep(callDelayMicros) }
            lock.withLock {
                _attachCount += 1
                _handler = handler
            }
            if let replay = replayOnAttach {
                handler(replay)
            }
        }

        func detach() {
            if callDelayMicros > 0 { usleep(callDelayMicros) }
            lock.withLock {
                _detachCount += 1
                _handler = nil
            }
        }

        func emit(_ payload: String) {
            handler?(payload)
        }
    }

    /// Queues blocks instead of running them, so a test controls when "main" runs.
    private final class RecordingDispatcher {
        private let lock = NSLock()
        private var queue: [() -> Void] = []
        var pending: Int { lock.withLock { queue.count } }

        func dispatch(_ block: @escaping () -> Void) {
            lock.withLock { queue.append(block) }
        }

        func drain() {
            while true {
                let next: (() -> Void)? = lock.withLock { queue.isEmpty ? nil : queue.removeFirst() }
                guard let block = next else { return }
                block()
            }
        }
    }

    private final class Log {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ value: String) { lock.withLock { items.append(value) } }
        var values: [String] { lock.withLock { items } }
    }

    private var source: FakeSource!
    private var dispatcher: RecordingDispatcher!
    private var hub: NottiListenerHub<String>!

    override func setUp() {
        super.setUp()
        source = FakeSource()
        dispatcher = RecordingDispatcher()
        hub = makeHub()
    }

    private func makeHub() -> NottiListenerHub<String> {
        let source = self.source!
        let dispatcher = self.dispatcher!
        return NottiListenerHub<String>(
            attach: { source.attach($0) },
            detach: { source.detach() },
            dispatcher: { dispatcher.dispatch($0) }
        )
    }

    // MARK: - Attach and detach

    func test_attachOnFirstListenerAndDetachOnLastOnly() {
        XCTAssertEqual(source.attachCount, 0)

        let first = hub.add { _ in }
        XCTAssertEqual(source.attachCount, 1)
        let second = hub.add { _ in }
        XCTAssertEqual(source.attachCount, 1, "the second listener does not attach again")

        first.remove()
        XCTAssertEqual(source.detachCount, 0, "one listener is still registered")
        second.remove()
        XCTAssertEqual(source.detachCount, 1)
        XCTAssertNil(source.handler)
        XCTAssertEqual(hub.count, 0)
    }

    func test_reattachesWhenAListenerArrivesAfterTheLastWasRemoved() {
        hub.add { _ in }.remove()
        _ = hub.add { _ in }

        XCTAssertEqual(source.attachCount, 2)
        XCTAssertEqual(source.detachCount, 1)
    }

    // MARK: - Replay

    func test_synchronousReplayInsideAttachReachesTheFirstListenerOnly() {
        source.replayOnAttach = "buffered"
        let firstLog = Log()
        let secondLog = Log()

        _ = hub.add { firstLog.append($0) }
        _ = hub.add { secondLog.append($0) }
        dispatcher.drain()

        XCTAssertEqual(firstLog.values, ["buffered"])
        XCTAssertEqual(secondLog.values, [])
    }

    // MARK: - Delivery

    func test_deliveryIsNeverInlineAndFollowsRegistrationOrder() {
        let log = Log()
        _ = hub.add { log.append("A:\($0)") }
        _ = hub.add { log.append("B:\($0)") }

        source.emit("one")
        source.emit("two")

        XCTAssertEqual(log.values, [], "nothing runs until the dispatcher does")
        XCTAssertEqual(dispatcher.pending, 2)
        dispatcher.drain()
        XCTAssertEqual(log.values, ["A:one", "B:one", "A:two", "B:two"])
    }

    func test_aListenerAddedInsideACallbackReceivesOnlyLaterEvents() {
        let log = Log()
        var added = false
        _ = hub.add { [unowned self] payload in
            log.append("A:\(payload)")
            if !added {
                added = true
                _ = self.hub.add { log.append("B:\($0)") }
            }
        }

        source.emit("one")
        dispatcher.drain()
        source.emit("two")
        dispatcher.drain()

        XCTAssertEqual(log.values, ["A:one", "A:two", "B:two"])
    }

    func test_aListenerRemovedInsideACallbackStopsFromTheNextEvent() {
        let log = Log()
        var subscription: NottiSubscription?
        subscription = hub.add { payload in
            log.append("A:\(payload)")
            subscription?.remove()
        }
        _ = hub.add { log.append("B:\($0)") }

        source.emit("one")
        dispatcher.drain()
        source.emit("two")
        dispatcher.drain()

        XCTAssertEqual(log.values, ["A:one", "B:one", "B:two"])
        XCTAssertEqual(hub.count, 1)
    }

    // MARK: - Remove

    func test_removeTwiceIsSafeAndTheHandlerIsNotCalledAfterwards() {
        let log = Log()
        let subscription = hub.add { log.append($0) }
        _ = hub.add { _ in }

        subscription.remove()
        subscription.remove()
        source.emit("late")
        dispatcher.drain()

        XCTAssertEqual(log.values, [])
        XCTAssertEqual(hub.count, 1)
        XCTAssertEqual(source.detachCount, 0)
    }

    func test_aListenerRemovedAfterTheEventWasQueuedIsNotCalled() {
        let log = Log()
        let subscription = hub.add { log.append($0) }

        source.emit("queued")
        subscription.remove()
        dispatcher.drain()

        XCTAssertEqual(log.values, [])
    }

    func test_removeReleasesTheHandlerClosure() {
        weak var weakProbe: AnyObject?
        var subscription: NottiSubscription?
        autoreleasepool {
            let probe = NSObject()
            weakProbe = probe
            subscription = hub.add { _ in _ = probe }
        }
        XCTAssertNotNil(weakProbe, "the hub keeps the handler while registered")

        subscription?.remove()

        XCTAssertNil(weakProbe)
    }

    // MARK: - Concurrency

    func test_concurrentAddAndRemoveNeverLeaveTheSourceAttachedToAnEmptyList() {
        source.callDelayMicros = 200
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hub-stress", attributes: .concurrent)
        for _ in 0..<8 {
            group.enter()
            queue.async { [hub = self.hub!] in
                for _ in 0..<40 {
                    hub.add { _ in }.remove()
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)

        XCTAssertEqual(hub.count, 0)
        XCTAssertNil(source.handler, "no listener left, so the source must be detached")
        XCTAssertEqual(source.attachCount, source.detachCount)
    }

    func test_concurrentAddsKeepTheSourceAttachedWhileListenersExist() {
        source.callDelayMicros = 200
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hub-stress-keep", attributes: .concurrent)
        let kept = Log()
        for index in 0..<64 {
            group.enter()
            queue.async { [hub = self.hub!] in
                let subscription = hub.add { _ in }
                if index % 2 == 0 {
                    subscription.remove()
                } else {
                    kept.append("kept")
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)

        XCTAssertEqual(hub.count, kept.values.count)
        XCTAssertNotNil(source.handler, "listeners exist, so the source must be attached")
        XCTAssertEqual(source.attachCount - source.detachCount, 1)
    }
}

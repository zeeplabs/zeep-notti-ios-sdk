import UserNotifications
import XCTest

/// Re-proves on the iOS Simulator the three results the design measured with `swiftc` on macOS
/// (`design.md`, "Spike results"). If one of these fails, the design reopens (D4 or D10).
final class NottiRichMediaSpikeTests: XCTestCase {
    private let sourceURL = URL(string: "https://media.example.invalid/spike/source.png")!
    private let httpTarget = URL(string: "http://media.example.invalid/spike/target.png")!

    private typealias Behavior = StubURLProtocol.Behavior
    private var session: URLSession?

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        session?.invalidateAndCancel()
        session = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// A delegate with the three callbacks the job relies on, each overridable by a closure.
    private final class SpikeDelegate: NSObject, URLSessionDownloadDelegate {
        var onRedirect: ((URLSessionTask, @escaping (URLRequest?) -> Void) -> Void)?
        var onWrite: ((URLSessionDownloadTask, Int64, Int64) -> Void)?
        var onComplete: ((Error?) -> Void)?
        private let lock = NSLock()
        private var writes: [(written: Int64, expected: Int64)] = []

        var recordedWrites: [(written: Int64, expected: Int64)] {
            lock.withLock { writes }
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            if let onRedirect { onRedirect(task, completionHandler) } else { completionHandler(request) }
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            lock.withLock { writes.append((totalBytesWritten, totalBytesExpectedToWrite)) }
            onWrite?(downloadTask, totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            onComplete?(error)
        }
    }

    private func makeSession(_ delegate: SpikeDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        return session
    }

    // Spike 3: refusing a redirect needs `cancel()`.

    func test_refusingARedirectWithNilAloneDoesNotCompleteTheTask_andCancelDoes() {
        StubURLProtocol.register(.redirect(to: httpTarget), for: sourceURL)
        StubURLProtocol.register(Behavior.neverResponds, for: httpTarget)
        let delegate = SpikeDelegate()
        var task: URLSessionTask?
        delegate.onRedirect = { redirected, completion in
            task = redirected
            completion(nil)
        }
        let completed = expectation(description: "completed after nil only")
        completed.isInverted = true
        delegate.onComplete = { _ in completed.fulfill() }
        makeSession(delegate).downloadTask(with: sourceURL).resume()

        // Design result: nil alone leaves the task open. Observed on the simulator below.
        wait(for: [completed], timeout: 3)

        let cancelled = expectation(description: "completed after cancel")
        var completionError: NSError?
        delegate.onComplete = { error in
            completionError = error as NSError?
            cancelled.fulfill()
        }
        task?.cancel()
        wait(for: [cancelled], timeout: 5)
        XCTAssertEqual(completionError?.domain, NSURLErrorDomain)
        XCTAssertEqual(completionError?.code, NSURLErrorCancelled)
        XCTAssertEqual(StubURLProtocol.servedBytes(for: httpTarget), 0)
    }

    func test_refusingARedirectWithNilAndCancelCompletesWithCancelledBeforeAnyBody() {
        StubURLProtocol.register(.redirect(to: httpTarget), for: sourceURL)
        StubURLProtocol.register(Behavior(chunks: [Data(count: 1024)], chunkInterval: 0.01), for: httpTarget)
        let delegate = SpikeDelegate()
        delegate.onRedirect = { task, completion in
            completion(nil)
            task.cancel()
        }
        let done = expectation(description: "completed")
        var completionError: NSError?
        delegate.onComplete = { error in
            completionError = error as NSError?
            done.fulfill()
        }
        makeSession(delegate).downloadTask(with: sourceURL).resume()

        wait(for: [done], timeout: 5)
        XCTAssertEqual(completionError?.domain, NSURLErrorDomain)
        XCTAssertEqual(completionError?.code, NSURLErrorCancelled)
        XCTAssertEqual(StubURLProtocol.servedBytes(for: httpTarget), 0)
    }

    // Spike 2: the declared length arrives early and `cancel()` stops the body.

    func test_declaredLengthArrivesInTheFirstWriteAndCancelStopsTheBody() {
        let elevenMiB: Int64 = 11 * 1024 * 1024
        let chunk = Data(count: 64 * 1024)
        StubURLProtocol.register(
            Behavior(declaredLength: elevenMiB, chunks: Array(repeating: chunk, count: 150), chunkInterval: 0.02),
            for: sourceURL
        )
        let delegate = SpikeDelegate()
        delegate.onWrite = { task, _, expected in
            if expected > 10 * 1024 * 1024 { task.cancel() }
        }
        let done = expectation(description: "completed")
        var completionError: NSError?
        delegate.onComplete = { error in
            completionError = error as NSError?
            done.fulfill()
        }
        makeSession(delegate).downloadTask(with: sourceURL).resume()

        wait(for: [done], timeout: 5)
        XCTAssertEqual(delegate.recordedWrites.first?.expected, elevenMiB)
        XCTAssertEqual(completionError?.code, NSURLErrorCancelled)
        XCTAssertLessThan(StubURLProtocol.servedBytes(for: sourceURL), 2 * 1024 * 1024)
        // The system stops the protocol after a cancel. Give it a moment, it is asynchronous.
        let stopped = expectation(description: "stopLoading")
        DispatchQueue.global().async {
            while StubURLProtocol.stopCount(for: self.sourceURL) == 0 { usleep(10_000) }
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 5)
    }

    // Spike 1: two mutable copies of one request's content have equal `userInfo`.

    func test_twoMutableCopiesOfTheSameRequestHaveEqualUserInfoAndADifferentOneDoesNot() throws {
        let content = UNMutableNotificationContent()
        content.title = "fixture title"
        content.userInfo = [
            "aps": ["mutable-content": 1, "alert": ["title": "fixture"]],
            "notti_image_url": "https://media.example.invalid/spike/a.png",
            "delivery_id": "delivery-fixture"
        ]
        let request = UNNotificationRequest(identifier: "fixture", content: content, trigger: nil)

        let first = try XCTUnwrap(request.content.mutableCopy() as? UNMutableNotificationContent)
        let second = try XCTUnwrap(request.content.mutableCopy() as? UNMutableNotificationContent)
        XCTAssertTrue((first.userInfo as NSDictionary).isEqual(to: second.userInfo))
        XCTAssertTrue((request.content.userInfo as NSDictionary).isEqual(to: first.userInfo))

        let other = UNMutableNotificationContent()
        other.userInfo = ["notti_image_url": "https://media.example.invalid/spike/b.png"]
        XCTAssertFalse((first.userInfo as NSDictionary).isEqual(to: other.userInfo))
    }
}

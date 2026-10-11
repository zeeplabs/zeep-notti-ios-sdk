import Foundation
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// One media download for one notification, with one exit (design: `NottiRichMediaJob`).
///
/// Every way out goes through `finish`, which runs once. The host's handler is reached only through
/// `NottiHandlerGate`. Nothing here logs a URL, host, query, title or body (NSE-13).
final class NottiRichMediaJob: NSObject, URLSessionDownloadDelegate {
    enum Outcome {
        case attached(UNNotificationAttachment)
        case dropped(NottiRichMediaDropReason)
    }

    private let content: UNMutableNotificationContent
    private let gate: NottiHandlerGate
    private let environment: NottiRichMediaEnvironment
    private let delegateQueue: OperationQueue

    private let lock = NSLock()
    private var finished = false
    private var sawFile = false
    private var session: URLSession?
    private var task: URLSessionTask?

    /// `content` is the mutable copy the helper hands back; it stays untouched until an attachment is added.
    init(
        content: UNMutableNotificationContent,
        gate: NottiHandlerGate,
        environment: NottiRichMediaEnvironment
    ) {
        self.content = content
        self.gate = gate
        self.environment = environment
        let queue = OperationQueue()
        queue.name = "app.notti.sdk.nse.media"
        queue.maxConcurrentOperationCount = 1
        self.delegateQueue = queue
        super.init()
    }

    func start(url: URL) {
        let session = URLSession(
            configuration: environment.makeConfiguration(), delegate: self, delegateQueue: delegateQueue
        )
        let task = session.downloadTask(with: url)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    // MARK: - The one exit

    /// First caller wins. Cancels the transfer, invalidates the session (which releases this delegate),
    /// logs a drop and fires the gate.
    private func finish(_ outcome: Outcome) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let session = self.session
        let task = self.task
        self.session = nil
        self.task = nil
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()

        switch outcome {
        case .attached(let attachment):
            content.attachments = [attachment]
        case .dropped(let reason):
            NottiLogger.log(.error, "rich media dropped: \(reason.code)", category: "nse")
        }
        gate.fire(content)
    }

    private var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    // MARK: - URLSessionDownloadDelegate

    /// Runs synchronously: the system deletes `location` as soon as this returns.
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard !isFinished else { return }
        lock.lock(); sawFile = true; lock.unlock()

        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.dropped(.httpStatus(http.statusCode)))
            return
        }

        let fileExtension = NottiMediaFileType.fileExtension(
            mimeType: downloadTask.response?.mimeType,
            url: downloadTask.originalRequest?.url ?? location
        )
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        let destination = environment.directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            finish(.dropped(.moveFailed(error)))
            return
        }

        do {
            let attachment = try UNNotificationAttachment(
                identifier: UUID().uuidString, url: destination, options: nil
            )
            finish(.attached(attachment))
        } catch {
            try? fileManager.removeItem(at: destination)
            finish(.dropped(.attachmentRejected(error)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isFinished else { return }
        if let error {
            finish(.dropped(.transport(error)))
            return
        }
        lock.lock()
        let seen = sawFile
        lock.unlock()
        if !seen { finish(.dropped(.noFile)) }
    }
}

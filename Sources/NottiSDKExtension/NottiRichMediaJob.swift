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
    private var deadlineItem: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "app.notti.sdk.nse.media.deadline")

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
        // One deadline for the whole download (NSE-10). A response that keeps sending bytes does not move it.
        let item = DispatchWorkItem { [weak self] in self?.finish(.dropped(.deadline)) }
        lock.lock()
        self.session = session
        self.task = task
        self.deadlineItem = item
        lock.unlock()
        timerQueue.asyncAfter(deadline: .now() + environment.limits.deadline, execute: item)
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
        let deadlineItem = self.deadlineItem
        self.session = nil
        self.task = nil
        self.deadlineItem = nil
        lock.unlock()

        deadlineItem?.cancel()
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

    /// Refuses a redirect to anything but https (NSE-04). Answering `nil` alone does not end the task
    /// (proved in `NottiRichMediaSpikeTests`), so `finish` also cancels it.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard !isFinished, request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            finish(.dropped(.redirectNotHTTPS))
            return
        }
        completionHandler(request)
    }

    /// Aborts as soon as the declared length or the bytes received pass the cap (NSE-17).
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let maxBytes = environment.limits.maxBytes
        if totalBytesExpectedToWrite > maxBytes || totalBytesWritten > maxBytes {
            finish(.dropped(.oversize))
        }
    }

    /// Runs synchronously: the system deletes `location` as soon as this returns.
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard !isFinished else { return }
        lock.lock(); sawFile = true; lock.unlock()

        let fileManager = FileManager.default
        // The system deletes `location` after this returns; removing it on a drop keeps NSE-09 true even
        // for a caller that hands over a file of its own.
        func drop(_ reason: NottiRichMediaDropReason) {
            try? fileManager.removeItem(at: location)
            finish(.dropped(reason))
        }

        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            drop(.httpStatus(http.statusCode))
            return
        }
        // Second barrier for NSE-04: the final URL, after any redirect, must still be https.
        if let finalURL = downloadTask.response?.url, finalURL.scheme?.lowercased() != "https" {
            drop(.redirectNotHTTPS)
            return
        }
        // Second barrier for NSE-06: the size of the file on disk. `fileSizeKey` avoids `attributesOfItem` (D9).
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            drop(.noFile)
            return
        }
        if Int64(size) > environment.limits.maxBytes {
            drop(.oversize)
            return
        }

        let fileExtension = NottiMediaFileType.fileExtension(
            mimeType: downloadTask.response?.mimeType,
            url: downloadTask.originalRequest?.url ?? location
        )
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

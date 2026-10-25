import Foundation
import ImageIO
import UIKit

/// Downloads and decodes a message's `image_url`, a port of RN `NottiInAppImageLoader.swift` (0.8.0).
/// The host is chosen by the message author, so the request goes through a dedicated ephemeral session:
/// no Authorization header, no cookies, no URL cache, no credential storage, and no redirect to a
/// non-`https` URL (IAM-40, IAM-42). Bounded in time (10 s for the whole call) and size (5 MiB), decoded
/// downsampled, cached in memory only. Any failure is "no image" (IAM-41). Never logs the URL.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppImageLoader {

    /// Starts a one-shot timer of `seconds` and returns its cancel.
    typealias TimerStarter = (_ seconds: TimeInterval, _ fire: @escaping () -> Void) -> () -> Void

    static let timeout: TimeInterval = 10
    static let maxBytes = 5 * 1024 * 1024
    static let cacheEntries = 5

    /// Production timer: a wall-clock deadline (no uptime clock, D8).
    static let wallClockTimer: TimerStarter = { seconds, fire in
        let item = DispatchWorkItem(block: fire)
        DispatchQueue.global(qos: .utility).asyncAfter(wallDeadline: .now() + max(seconds, 0), execute: item)
        return { item.cancel() }
    }

    private let makeSession: (URLSessionConfiguration, URLSessionDelegate, OperationQueue) -> URLSession
    private let startTimer: TimerStarter
    private let center: NotificationCenter
    private var memoryObserver: NSObjectProtocol?

    private let lock = NSLock()
    /// Least recently used first; at most `cacheEntries`.
    private var cache: [(key: String, image: UIImage)] = []

    /// `makeSession` lets tests add their `URLProtocol` to the configuration. Takes no credentials.
    init(
        makeSession: @escaping (URLSessionConfiguration, URLSessionDelegate, OperationQueue) -> URLSession = {
            URLSession(configuration: $0, delegate: $1, delegateQueue: $2)
        },
        startTimer: @escaping TimerStarter = NottiInAppImageLoader.wallClockTimer,
        center: NotificationCenter = .default
    ) {
        self.makeSession = makeSession
        self.startTimer = startTimer
        self.center = center
        memoryObserver = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.clear()
        }
    }

    deinit {
        if let observer = memoryObserver { center.removeObserver(observer) }
    }

    /// The credential-free configuration: no cookies, no cache, no credentials.
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpAdditionalHeaders = [:]
        return config
    }

    static func isHttps(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    /// `done` runs once, on any thread; nil means "no image". `maxSidePx` is the screen's longest side in
    /// physical pixels (the caller's choice, RN `NottiInAppPresenter.swift:263`).
    func load(url: URL, maxSidePx: CGFloat, done: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString
        if let hit = cached(key) {
            done(hit)
            return
        }
        guard Self.isHttps(url) else {
            done(nil)
            return
        }
        let download = Download(maxBytes: Self.maxBytes) { [weak self] data in
            let image = data.flatMap { Self.decode($0, maxSidePx: maxSidePx) }
            if let image = image { self?.store(key, image) }
            done(image)
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = makeSession(Self.configuration(), download, queue)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpShouldHandleCookies = false
        download.start(session.dataTask(with: request), session: session, timer: startTimer, timeout: Self.timeout)
    }

    /// Drops every cached image (memory warning).
    func clear() {
        lock.withLock { cache.removeAll() }
    }

    private func cached(_ key: String) -> UIImage? {
        lock.withLock {
            guard let index = cache.firstIndex(where: { $0.key == key }) else { return nil }
            let entry = cache.remove(at: index)
            cache.append(entry)
            return entry.image
        }
    }

    private func store(_ key: String, _ image: UIImage) {
        lock.withLock {
            cache.removeAll { $0.key == key }
            cache.append((key, image))
            while cache.count > Self.cacheEntries { cache.removeFirst() }
        }
    }

    /// Always through the thumbnail path, the only one that applies the EXIF orientation, so a small photo
    /// is upright too; `min(longest side, maxSidePx)`, so never upscaled. Nil when the bytes are not an image.
    static func decode(_ data: Data, maxSidePx: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let source = CGImageSourceCreateWithData(data as CFData, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else {
            return nil
        }
        let longest = CGFloat(max(width, height))
        let maxPixelSize = maxSidePx > 0 ? min(longest, maxSidePx) : longest
        let thumbnailOptions = [
            // An embedded (smaller) thumbnail is never used: always the full image.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions).map { UIImage(cgImage: $0) }
    }

    /// One request: `https` only, bounded in size and time, ends exactly once.
    private final class Download: NSObject, URLSessionDataDelegate {

        private let maxBytes: Int
        private let finish: (Data?) -> Void
        private let lock = NSLock()
        private var buffer = Data()
        private var finished = false
        private var accepted = false
        private var task: URLSessionDataTask?
        private var session: URLSession?
        private var cancelTimer: (() -> Void)?

        init(maxBytes: Int, finish: @escaping (Data?) -> Void) {
            self.maxBytes = maxBytes
            self.finish = finish
        }

        func start(_ task: URLSessionDataTask, session: URLSession, timer: TimerStarter, timeout: TimeInterval) {
            lock.withLock {
                self.task = task
                self.session = session
            }
            // The whole call is bounded, not only each read.
            let cancel = timer(timeout) { [weak self] in self?.end(nil) }
            let alreadyFinished: Bool = lock.withLock {
                cancelTimer = cancel
                return finished
            }
            if alreadyFinished { cancel() }
            task.resume()
        }

        /// The first outcome wins; the timer, the task and the session are released.
        private func end(_ data: Data?) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            finished = true
            let task = self.task
            let session = self.session
            let cancelTimer = self.cancelTimer
            self.task = nil
            self.session = nil
            self.cancelTimer = nil
            lock.unlock()
            cancelTimer?()
            task?.cancel()
            session?.invalidateAndCancel()
            finish(data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // https -> https is followed without cookies; anything else is refused.
            if let next = request.url, NottiInAppImageLoader.isHttps(next) {
                var followed = request
                followed.httpShouldHandleCookies = false
                followed.setValue(nil, forHTTPHeaderField: "Authorization")
                completionHandler(followed)
            } else {
                completionHandler(nil)
                end(nil)
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                http.url?.scheme?.lowercased() == "https",
                http.expectedContentLength <= Int64(maxBytes)
            else {
                completionHandler(.cancel)
                end(nil)
                return
            }
            lock.withLock { accepted = true }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let tooLarge: Bool = lock.withLock {
                guard accepted, !finished else { return false }
                buffer.append(data)
                return buffer.count > maxBytes
            }
            // Aborted as soon as the body passes the limit: the rest is never read.
            if tooLarge { end(nil) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let body: Data? = lock.withLock { error == nil && accepted ? buffer : nil }
            end(body)
        }
    }
}

// Adapted from Tests/NottiSDKTests/Support/StubURLProtocol.swift for the extension tests (test support).
// A different stub on purpose: the NSE helper needs redirects, a declared length, chunked and endless
// bodies, a response that never finishes and a served-byte counter. Routes are keyed by absolute URL.
// swiftlint:disable static_over_final_class

import Foundation

final class StubURLProtocol: URLProtocol {
    struct Behavior {
        var status = 200
        var headers: [String: String] = [:]
        /// `Content-Length` to declare, independent of the bytes actually served.
        var declaredLength: Int64?
        var chunks: [Data] = []
        /// Delay before each chunk. Zero serves them back to back.
        var chunkInterval: TimeInterval = 0
        /// Serve `endlessChunk` forever, every `chunkInterval`, after `chunks`.
        var endlessChunk: Data?
        /// `false` leaves the response open after the last chunk (the load never ends by itself).
        var finishes = true
        /// `false` never sends a response at all.
        var responds = true
        /// Answers with a redirect to this URL instead of a body.
        var redirectTo: URL?
        var error: Error?

        static func body(_ data: Data, mimeType: String? = nil, status: Int = 200) -> Behavior {
            var headers: [String: String] = [:]
            if let mimeType { headers["Content-Type"] = mimeType }
            return Behavior(status: status, headers: headers, chunks: [data])
        }

        static func redirect(to url: URL) -> Behavior { Behavior(redirectTo: url) }
        static func failure(_ error: Error) -> Behavior { Behavior(error: error) }
        static var neverResponds: Behavior { Behavior(responds: false) }
    }

    private static let lock = NSLock()
    private static var routes: [String: Behavior] = [:]
    private static var requests: [URL] = []
    private static var served: [String: Int] = [:]
    private static var stops: [String: Int] = [:]

    static func register(_ behavior: Behavior, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        routes[url.absoluteString] = behavior
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes.removeAll(); requests.removeAll(); served.removeAll(); stops.removeAll()
    }

    static var requestedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    /// Body bytes handed to the client for `url`.
    static func servedBytes(for url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return served[url.absoluteString] ?? 0
    }

    /// How many times the system stopped loading `url` (cancel, completion or invalidation).
    static func stopCount(for url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return stops[url.absoluteString] ?? 0
    }

    private static func behavior(for url: URL) -> Behavior? {
        lock.lock(); defer { lock.unlock() }
        requests.append(url)
        return routes[url.absoluteString]
    }

    private static func addServed(_ count: Int, for key: String) {
        lock.lock(); defer { lock.unlock() }
        served[key, default: 0] += count
    }

    private static func addStop(for key: String) {
        lock.lock(); defer { lock.unlock() }
        stops[key, default: 0] += 1
    }

    private let stateLock = NSLock()
    private var stopped = false
    private let queue = DispatchQueue(label: "StubURLProtocol.serve")

    private var isStopped: Bool { stateLock.withLock { stopped } }
    private var key: String { request.url?.absoluteString ?? "" }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let behavior = Self.behavior(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = behavior.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard behavior.responds else { return }

        var headers = behavior.headers
        if let declared = behavior.declaredLength { headers["Content-Length"] = String(declared) }

        if let target = behavior.redirectTo {
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }

        let response = HTTPURLResponse(
            url: url, statusCode: behavior.status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        serve(behavior, index: 0)
    }

    private func serve(_ behavior: Behavior, index: Int) {
        queue.asyncAfter(deadline: .now() + (index == 0 ? 0 : behavior.chunkInterval)) { [weak self] in
            guard let self, !self.isStopped else { return }
            if index < behavior.chunks.count {
                let chunk = behavior.chunks[index]
                Self.addServed(chunk.count, for: self.key)
                self.client?.urlProtocol(self, didLoad: chunk)
                self.serve(behavior, index: index + 1)
            } else if let endless = behavior.endlessChunk {
                Self.addServed(endless.count, for: self.key)
                self.client?.urlProtocol(self, didLoad: endless)
                self.serve(behavior, index: index + 1)
            } else if behavior.finishes {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
        Self.addStop(for: key)
    }
}

// swiftlint:enable static_over_final_class

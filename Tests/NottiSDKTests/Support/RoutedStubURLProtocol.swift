// Adapted from Tests/NottiSDKExtensionTests/Support/StubURLProtocol.swift for the In-App image loader tests
// (test support; that one lives in another test target). Routes are keyed by absolute URL; it serves
// redirects, a declared length, chunked and endless bodies and a response that never finishes, records
// every request with its headers and counts served bytes and stops.
// swiftlint:disable static_over_final_class

import Foundation

final class RoutedStubURLProtocol: URLProtocol {
    struct Behavior {
        var status = 200
        var headers: [String: String] = [:]
        /// `Content-Length` to declare, independent of the bytes actually served.
        var declaredLength: Int64?
        var chunks: [Data] = []
        /// Serve this forever, back to back, after `chunks`.
        var endlessChunk: Data?
        /// `false` leaves the response open after the last chunk (the load never ends by itself).
        var finishes = true
        /// Answers with a redirect to this URL instead of a body.
        var redirectTo: URL?
        var error: Error?

        static func body(_ data: Data, status: Int = 200) -> Behavior {
            Behavior(status: status, chunks: [data])
        }

        static func redirect(to url: URL) -> Behavior { Behavior(redirectTo: url) }
        static func failure(_ error: Error) -> Behavior { Behavior(error: error) }
    }

    private static let lock = NSLock()
    private static var routes: [String: Behavior] = [:]
    private static var recorded: [URLRequest] = []
    private static var served: [String: Int] = [:]
    private static var stops: [String: Int] = [:]

    static func register(_ behavior: Behavior, for url: URL) {
        lock.withLock { routes[url.absoluteString] = behavior }
    }

    static func reset() {
        lock.withLock {
            routes.removeAll()
            recorded.removeAll()
            served.removeAll()
            stops.removeAll()
        }
    }

    static var requests: [URLRequest] { lock.withLock { recorded } }

    static func servedBytes(for url: URL) -> Int {
        lock.withLock { served[url.absoluteString] ?? 0 }
    }

    static func stopCount(for url: URL) -> Int {
        lock.withLock { stops[url.absoluteString] ?? 0 }
    }

    private static func behavior(for request: URLRequest) -> Behavior? {
        lock.withLock {
            recorded.append(request)
            return request.url.flatMap { routes[$0.absoluteString] }
        }
    }

    private static func addServed(_ count: Int, for key: String) {
        lock.withLock { served[key, default: 0] += count }
    }

    private static func addStop(for key: String) {
        lock.withLock { stops[key, default: 0] += 1 }
    }

    private let stateLock = NSLock()
    private var stopped = false
    private let queue = DispatchQueue(label: "RoutedStubURLProtocol.serve")

    private var isStopped: Bool { stateLock.withLock { stopped } }
    private var key: String { request.url?.absoluteString ?? "" }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let behavior = Self.behavior(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = behavior.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        var headers = behavior.headers
        if let declared = behavior.declaredLength { headers["Content-Length"] = String(declared) }

        if let target = behavior.redirectTo {
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            )
            if let response = response {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            return
        }

        let response = HTTPURLResponse(
            url: url, statusCode: behavior.status, httpVersion: "HTTP/1.1", headerFields: headers
        )
        guard let response = response else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        serve(behavior, index: 0)
    }

    private func serve(_ behavior: Behavior, index: Int) {
        queue.async { [weak self] in
            guard let self = self, !self.isStopped else { return }
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

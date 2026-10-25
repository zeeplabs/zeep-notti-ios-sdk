import ImageIO
import UIKit
import XCTest
@testable import NottiSDK

/// Fires the loader's whole-call deadline when the test says so, and records the requested seconds.
private final class ManualTimer {
    private let lock = NSLock()
    private var fires: [() -> Void] = []
    private var cancels = 0
    private(set) var requested: [TimeInterval] = []

    var start: NottiInAppImageLoader.TimerStarter {
        { [unowned self] seconds, fire in
            self.lock.withLock {
                self.requested.append(seconds)
                self.fires.append(fire)
            }
            return { [unowned self] in self.lock.withLock { self.cancels += 1 } }
        }
    }

    var cancelCount: Int { lock.withLock { cancels } }

    func fireAll() {
        let pending = lock.withLock { fires }
        pending.forEach { $0() }
    }
}

/// IAM-40, IAM-41 (loader side), IAM-42. Port of RN `NottiInAppImageLoaderTests` (0.8.0) over a routed
/// `URLProtocol` stub and a manual deadline timer: no network, no sleeps. The 5 MiB, 10 s and 5-entry
/// limits are literals here. Synthetic hosts only (`example.invalid`).
final class NottiInAppImageLoaderTests: XCTestCase {

    private let mib = 1024 * 1024
    private let imageUrl = URL(string: "https://img.example.invalid/a.png")!
    private var center: NotificationCenter!
    private var timer: ManualTimer!

    override func setUp() {
        super.setUp()
        RoutedStubURLProtocol.reset()
        center = NotificationCenter()
        timer = ManualTimer()
    }

    override func tearDown() {
        RoutedStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeLoader() -> NottiInAppImageLoader {
        NottiInAppImageLoader(
            makeSession: { config, delegate, queue in
                config.protocolClasses = [RoutedStubURLProtocol.self]
                return URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
            },
            startTimer: timer.start,
            center: center
        )
    }

    private func png(_ width: Int, _ height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A JPEG of `width` x `height` stored pixels tagged with EXIF `orientation`.
    private func jpeg(_ width: Int, _ height: Int, orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixels(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private func load(_ loader: NottiInAppImageLoader, _ url: URL? = nil, maxSide: CGFloat = 2000) -> UIImage? {
        let finished = expectation(description: "loaded")
        var result: UIImage?
        loader.load(url: url ?? imageUrl, maxSidePx: maxSide) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        return result
    }

    // MARK: - Decode (IAM-40)

    func test_a4000x1000PngWithMaxSide1000HasALongestSideOf1000() throws {
        let image = try XCTUnwrap(NottiInAppImageLoader.decode(png(4000, 1000), maxSidePx: 1000))
        XCTAssertEqual(pixels(image).width, 1000, accuracy: 1)
        XCTAssertEqual(pixels(image).height, 250, accuracy: 1)
    }

    func test_a200x100PngIsNeverUpscaled() throws {
        let image = try XCTUnwrap(NottiInAppImageLoader.decode(png(200, 100), maxSidePx: 1000))
        XCTAssertEqual(pixels(image), CGSize(width: 200, height: 100))
    }

    func test_aSmallJpegWithExifOrientation6DecodesUpright() throws {
        // Stored 40 x 20, orientation 6 (rotate 90 degrees clockwise to display): upright it is 20 x 40.
        let image = try XCTUnwrap(NottiInAppImageLoader.decode(jpeg(40, 20, orientation: 6), maxSidePx: 1000))
        XCTAssertEqual(pixels(image), CGSize(width: 20, height: 40))
        XCTAssertEqual(image.imageOrientation, .up)
    }

    func test_aDownloadedImageIsDownsampledToMaxSide() throws {
        RoutedStubURLProtocol.register(.body(png(4000, 1000)), for: imageUrl)
        let image = try XCTUnwrap(load(makeLoader(), maxSide: 1000))
        XCTAssertEqual(max(pixels(image).width, pixels(image).height), 1000, accuracy: 1)
        XCTAssertEqual(timer.requested, [10])
        XCTAssertEqual(timer.cancelCount, 1)
    }

    // MARK: - Size, status, deadline (IAM-40, IAM-41)

    func test_aDeclaredLengthOf6MiBIsRefusedEvenWithAValidBody() {
        var behavior = RoutedStubURLProtocol.Behavior.body(png(40, 20))
        behavior.declaredLength = Int64(6 * mib)
        RoutedStubURLProtocol.register(behavior, for: imageUrl)
        XCTAssertNil(load(makeLoader()))
    }

    func test_6MiBSentWithoutALengthIsAbortedPastTheLimit() {
        // A valid image padded to 6 MiB: only the limit can make it fail.
        var body = png(40, 20)
        body.append(Data(count: 6 * mib - body.count))
        let chunks = stride(from: 0, to: body.count, by: mib).map { body.subdata(in: $0..<min($0 + mib, body.count)) }
        RoutedStubURLProtocol.register(RoutedStubURLProtocol.Behavior(chunks: chunks), for: imageUrl)
        XCTAssertNil(load(makeLoader()))
        XCTAssertGreaterThanOrEqual(RoutedStubURLProtocol.stopCount(for: imageUrl), 1)
    }

    func test_aBodyOfExactly5MiBIsLoaded() {
        var body = png(40, 20)
        body.append(Data(count: 5 * mib - body.count))
        RoutedStubURLProtocol.register(.body(body), for: imageUrl)
        XCTAssertNotNil(load(makeLoader()))
    }

    func test_a404ReturnsNilEvenWithAnImageBody() {
        RoutedStubURLProtocol.register(.body(png(40, 20), status: 404), for: imageUrl)
        XCTAssertNil(load(makeLoader()))
    }

    func test_aResponseThatNeverEndsReturnsNilWhenThe10SecondDeadlineFires() {
        RoutedStubURLProtocol.register(RoutedStubURLProtocol.Behavior(chunks: [png(40, 20)], finishes: false), for: imageUrl)
        let loader = makeLoader()
        let finished = expectation(description: "loaded")
        var result: UIImage? = UIImage()
        loader.load(url: imageUrl, maxSidePx: 1000) {
            result = $0
            finished.fulfill()
        }
        let url = imageUrl
        let started = NSPredicate { _, _ in RoutedStubURLProtocol.servedBytes(for: url) > 0 }
        let requested = expectation(for: started, evaluatedWith: nil)
        wait(for: [requested], timeout: 10)
        XCTAssertEqual(timer.requested, [10])
        timer.fireAll()
        wait(for: [finished], timeout: 10)
        XCTAssertNil(result)
    }

    // MARK: - Redirects and bodies (IAM-41)

    func test_aRedirectToHttpReturnsNil() {
        let http = URL(string: "http://img.example.invalid/b.png")!
        RoutedStubURLProtocol.register(.redirect(to: http), for: imageUrl)
        RoutedStubURLProtocol.register(.body(png(40, 20)), for: http)
        XCTAssertNil(load(makeLoader()))
        XCTAssertEqual(RoutedStubURLProtocol.requests.map(\.url), [imageUrl])
    }

    func test_anHttpsRedirectIsFollowedWithoutCredentials() {
        let cdn = URL(string: "https://cdn.example.invalid/b.png")!
        RoutedStubURLProtocol.register(.redirect(to: cdn), for: imageUrl)
        RoutedStubURLProtocol.register(.body(png(40, 20)), for: cdn)
        XCTAssertNotNil(load(makeLoader()))
        let requests = RoutedStubURLProtocol.requests
        XCTAssertEqual(requests.map(\.url), [imageUrl, cdn])
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Cookie"))
    }

    func test_aNonImageBodyReturnsNil() {
        RoutedStubURLProtocol.register(.body(Data("fixture, not an image".utf8)), for: imageUrl)
        XCTAssertNil(load(makeLoader()))
    }

    func test_aTransportErrorReturnsNil() {
        RoutedStubURLProtocol.register(.failure(URLError(.notConnectedToInternet)), for: imageUrl)
        XCTAssertNil(load(makeLoader()))
    }

    func test_aNonHttpsUrlIsRejectedBeforeAnyConnection() {
        let loader = makeLoader()
        let rejected = ["http://img.example.invalid/a.png", "ftp://img.example.invalid/a.png", "file:///tmp/a.png", "https:///a.png"]
        for raw in rejected {
            XCTAssertNil(load(loader, URL(string: raw)), raw)
        }
        XCTAssertTrue(RoutedStubURLProtocol.requests.isEmpty)
    }

    // MARK: - No credentials (IAM-42)

    func test_theRequestCarriesNoAuthorizationAndNoCookies() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "img.example.invalid", .path: "/", .name: "fixture", .value: "sentinel-cookie", .secure: "TRUE"
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        RoutedStubURLProtocol.register(.body(png(40, 20)), for: imageUrl)
        XCTAssertNotNil(load(makeLoader()))
        let request = try XCTUnwrap(RoutedStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func test_theSessionConfigurationHasNoUrlCacheCookieStorageOrCredentialStorage() {
        let config = NottiInAppImageLoader.configuration()
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(config.timeoutIntervalForRequest, 10)
        XCTAssertEqual(config.timeoutIntervalForResource, 10)
    }

    // MARK: - Cache (IAM-40)

    func test_theSecondRequestForTheSameUrlIsServedFromTheCache() {
        let loader = makeLoader()
        RoutedStubURLProtocol.register(.body(png(40, 20)), for: imageUrl)
        let first = load(loader)
        let second = load(loader)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 1)
    }

    func test_theSixthDistinctUrlEvictsTheLeastRecentlyUsed() {
        let loader = makeLoader()
        let urls = (1...6).compactMap { URL(string: "https://img.example.invalid/\($0).png") }
        for url in urls { RoutedStubURLProtocol.register(.body(png(40, 20)), for: url) }
        for url in urls.prefix(5) { XCTAssertNotNil(load(loader, url)) }
        // 1 is used again, so 2 is now the least recently used.
        XCTAssertNotNil(load(loader, urls[0]))
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 5)
        XCTAssertNotNil(load(loader, urls[5]))
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 6)
        for url in [urls[0], urls[2], urls[3], urls[4], urls[5]] { XCTAssertNotNil(load(loader, url)) }
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 6)
        XCTAssertNotNil(load(loader, urls[1]))
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 7)
    }

    func test_aMemoryWarningEmptiesTheCache() {
        let loader = makeLoader()
        RoutedStubURLProtocol.register(.body(png(40, 20)), for: imageUrl)
        XCTAssertNotNil(load(loader))
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNotNil(load(loader))
        XCTAssertEqual(RoutedStubURLProtocol.requests.count, 2)
    }

    // MARK: - Production timer

    func test_theProductionDeadlineTimerFiresAndCanBeCancelled() {
        let fired = expectation(description: "fired")
        _ = NottiInAppImageLoader.wallClockTimer(0.05) { fired.fulfill() }
        let cancelled = expectation(description: "cancelled")
        cancelled.isInverted = true
        let cancel = NottiInAppImageLoader.wallClockTimer(0.05) { cancelled.fulfill() }
        cancel()
        wait(for: [fired, cancelled], timeout: 0.5)
    }
}

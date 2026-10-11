import XCTest
@testable import NottiSDKExtension

final class NottiMediaFileTypeTests: XCTestCase {
    private func url(_ path: String) -> URL { URL(string: "https://media.example.invalid\(path)")! }

    func test_eachAllowedMimeTypeMapsToItsExtension() {
        let plain = url("/fixture")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/jpeg", url: plain), "jpg")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/png", url: plain), "png")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/gif", url: plain), "gif")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "video/mp4", url: plain), "mp4")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "audio/mpeg", url: plain), "mp3")
    }

    func test_mimeMatchIsCaseInsensitive() {
        let plain = url("/fixture")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "Image/PNG", url: plain), "png")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "VIDEO/MP4", url: plain), "mp4")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "Audio/Mpeg", url: plain), "mp3")
    }

    func test_mimeTypeWinsOverTheUrlExtension() {
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "image/png", url: url("/a.gif")), "png")
    }

    func test_unknownMimeFallsBackToAnAllowlistedUrlExtension() {
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "application/octet-stream", url: url("/a.mp4")), "mp4")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: url("/a.GIF")), "gif")
    }

    func test_unknownMimeAndUnlistedUrlExtensionFallBackToJpg() {
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "text/html", url: url("/a.webp")), "jpg")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: url("/a.jpeg")), "jpg")
    }

    func test_noMimeAndNoExtensionFallBackToJpg() {
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: url("/fixture")), "jpg")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: "", url: url("/")), "jpg")
    }

    func test_aPathLikeExtensionNeverReachesTheResult() {
        let hostile = URL(string: "https://media.example.invalid/a.png%2F..%2Fescape")!
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: hostile), "jpg")
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: url("/a.sh")), "jpg")
    }

    func test_onlyTheLastPathComponentExtensionCounts() {
        XCTAssertEqual(NottiMediaFileType.fileExtension(mimeType: nil, url: url("/dir.png/fixture")), "jpg")
    }
}

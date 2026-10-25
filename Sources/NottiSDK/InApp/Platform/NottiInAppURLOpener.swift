import Foundation
import UIKit
#if canImport(NottiShared)
import NottiShared
#endif

/// Opens an In-App `url` action in the external browser (AD-020, in-app-open-url IOU-01, IOU-02, IOU-06).
///
/// The engine decides on its queue whether a tap opens anything: only a `url` action, only while
/// `Notti.Options.opensInAppURLs` is true, and only a value `openableURL(from:)` accepts. It then hands the
/// validated URL to `open(_:)` through the main dispatcher, after the click listeners and the close. A
/// `deeplink` never reaches this type.
///
/// AD-020: one of the two files allowed to open a URL (`scripts/check-no-url-open.sh` allowlists it by path,
/// next to `NottiPushPermissionAction.swift`), and the only URL it opens is the one `openableURL(from:)`
/// returned. The OS call is injected, so every row is a plain XCTest. No line here logs the URL.
final class NottiInAppURLOpener {

    /// Logged by the engine (at `.debug`) when a `url` action is not opened because of its value.
    static let refusedLog = "Notti.inapp: url action not opened: only http and https links with a host are opened"
    /// Logged when the OS reports that the URL could not be opened. Never retried.
    static let failedLog = "Notti.inapp: url action could not be opened"

    /// Schemes the SDK opens, compared lowercased.
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// The OS side: how a URL is opened (`system` in production). `completion` receives whether it opened.
    struct Platform {
        let open: (URL, @escaping (Bool) -> Void) -> Void

        @available(iOSApplicationExtension, unavailable)
        static let system = Platform(open: NottiInAppURLOpener.openInSystemBrowser)
    }

    private let platform: Platform
    private let logger: (String) -> Void

    init(
        platform: Platform,
        logger: @escaping (String) -> Void = { NottiLogger.log(.warn, $0, category: "inapp") }
    ) {
        self.platform = platform
        self.logger = logger
    }

    /// Hands an already validated URL to the OS once; a failure logs one fixed line and is not retried.
    func open(_ url: URL) {
        platform.open(url) { [logger] opened in
            if !opened { logger(Self.failedLog) }
        }
    }

    /// The URL to open for a `url` action's value, or nil when the SDK must not open it.
    ///
    /// Accepts only `http` and `https` (any letter case) with a non-empty host. A value that is empty or holds
    /// whitespace or control characters is refused before parsing, so iOS 15/16 and iOS 17+ (which
    /// percent-encodes invalid characters) decide the same way. The returned URL is built from the value
    /// unchanged; nothing is rewritten.
    static func openableURL(from value: String) -> URL? {
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), allowedSchemes.contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    /// The production opener: the external browser (or the app of a universal link), on the main thread.
    @available(iOSApplicationExtension, unavailable)
    static func openInSystemBrowser(_ url: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }
}

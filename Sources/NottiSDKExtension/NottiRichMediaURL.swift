import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// Reads the rich media URL from a push `userInfo` (NSE-02, NSE-03).
enum NottiRichMediaURL {
    enum Parsed: Equatable {
        /// The key is missing or its value is not a `String`. Nothing to do, nothing to log.
        case absent
        /// A `String` that is empty, unparsable, has no host or is not `https`.
        case invalid
        case valid(URL)
    }

    static func parse(_ userInfo: [AnyHashable: Any]) -> Parsed {
        guard let text = userInfo[NottiPayloadKeys.imageUrl] as? String else { return .absent }
        guard !text.isEmpty,
              let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return .invalid
        }
        return .valid(url)
    }
}

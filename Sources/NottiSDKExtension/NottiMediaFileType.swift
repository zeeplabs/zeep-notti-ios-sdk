import Foundation

/// Picks the attachment file extension (NSE-07).
///
/// Ported from `react-native-notti` 0.6.0 (`52e4b55`), except that the MIME match is case-insensitive.
enum NottiMediaFileType {
    private static let knownExtensions: Set<String> = ["jpg", "png", "gif", "mp4", "mp3"]

    /// MIME type (lowercased) first, then the URL extension when allowlisted, else `jpg`.
    static func fileExtension(mimeType: String?, url: URL) -> String {
        if let mimeType, let mapped = fileExtension(forMimeType: mimeType.lowercased()) {
            return mapped
        }
        // The URL is payload-controlled: never let an unlisted extension reach a file path.
        let candidate = url.pathExtension.lowercased()
        return knownExtensions.contains(candidate) ? candidate : "jpg"
    }

    private static func fileExtension(forMimeType mimeType: String) -> String? {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "video/mp4": return "mp4"
        case "audio/mpeg": return "mp3"
        default: return nil
        }
    }
}

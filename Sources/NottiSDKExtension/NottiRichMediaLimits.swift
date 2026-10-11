import Foundation

/// Size and time bounds of one rich media download (NSE-06, NSE-10, NSE-17, NSE-18).
struct NottiRichMediaLimits: Equatable {
    /// Largest accepted media file: 10 MiB.
    var maxBytes: Int64 = 10 * 1024 * 1024
    /// Total time for the whole download, in seconds. Under the OS budget of about 30 s.
    var deadline: TimeInterval = 20

    static let `default` = NottiRichMediaLimits()
}

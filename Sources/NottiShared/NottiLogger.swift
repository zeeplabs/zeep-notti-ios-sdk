import Foundation
import os

/// Log verbosity, ordered from quietest to noisiest.
package enum NottiLogLevel: Int, Comparable, CustomStringConvertible {
    case none = 0
    case error
    case warn
    case info
    case debug
    case verbose

    package static func < (lhs: NottiLogLevel, rhs: NottiLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    package var description: String {
        switch self {
        case .none: return "none"
        case .error: return "error"
        case .warn: return "warn"
        case .info: return "info"
        case .debug: return "debug"
        case .verbose: return "verbose"
        }
    }
}

/// The SDK's single logger (CORE-12).
///
/// Rule for every call site: messages never contain PII (email, phone, push token,
/// external user id, country, tag values). That rule is what allows emitting them
/// with `privacy: .public` in `os.Logger`.
package enum NottiLogger {
    package static let subsystem = "app.notti.sdk"

    /// Release default: errors only (CORE-13).
    package static let defaultLevel: NottiLogLevel = .error

    private static let lock = NSLock()
    private static var _level: NottiLogLevel = defaultLevel
    private static var _sink: ((NottiLogLevel, String) -> Void)?

    /// Messages above this level are dropped without evaluating them. Starts at `defaultLevel`.
    package static var level: NottiLogLevel {
        get { lock.withLock { _level } }
        set { lock.withLock { _level = newValue } }
    }

    /// Test seam. When set, receives messages instead of `os.Logger`.
    package static var sink: ((NottiLogLevel, String) -> Void)? {
        get { lock.withLock { _sink } }
        set { lock.withLock { _sink = newValue } }
    }

    package static func log(
        _ messageLevel: NottiLogLevel,
        _ message: @autoclosure () -> String,
        category: String = "core"
    ) {
        guard messageLevel != .none else { return }
        let (currentLevel, currentSink) = lock.withLock { (_level, _sink) }
        guard messageLevel <= currentLevel else { return }
        let text = message()
        if let currentSink {
            currentSink(messageLevel, text)
            return
        }
        let logger = Logger(subsystem: subsystem, category: category)
        switch messageLevel {
        case .error: logger.error("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .debug, .verbose: logger.debug("\(text, privacy: .public)")
        case .none: break
        }
    }
}

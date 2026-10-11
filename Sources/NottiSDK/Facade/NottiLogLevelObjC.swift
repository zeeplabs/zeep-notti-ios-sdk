import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// Verbosity of the SDK's own logs. Swift hosts use it as `Notti.LogLevel`.
///
/// It is a top-level type because an `@objc` enum nested in the non-`@objc`
/// `Notti` namespace is silently left out of the generated Objective-C header
/// (public-api design, "Spike results"). The `Notti.LogLevel` alias is declared
/// next to the `Notti` namespace. A separate public type (instead of exposing
/// `NottiLogLevel`) keeps `package` types out of public signatures (API-15).
///
/// The default is `.error`. No level ever logs email, phone, push token,
/// external user id, country or tag values.
@objc(NottiLogLevel)
public enum NottiLogLevelObjC: Int {
    case none = 0
    case error
    case warn
    case info
    case debug
    case verbose
}

extension NottiLogLevelObjC {
    /// Both mappings are exhaustive switches without `default`, so a new case on
    /// either side stops the build until it is mapped.
    init(_ level: NottiLogLevel) {
        switch level {
        case .none: self = .none
        case .error: self = .error
        case .warn: self = .warn
        case .info: self = .info
        case .debug: self = .debug
        case .verbose: self = .verbose
        }
    }

    var coreLevel: NottiLogLevel {
        switch self {
        case .none: return .none
        case .error: return .error
        case .warn: return .warn
        case .info: return .info
        case .debug: return .debug
        case .verbose: return .verbose
        }
    }
}

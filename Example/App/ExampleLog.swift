import Foundation

/// The example's own calls into the SDK. Closed on purpose: a row names a call, never its arguments.
enum ExampleCall: String, CaseIterable {
    case initialize
    case requestPermission
    case login
    case logout
    case setEmail
    case clearEmail
    case setPhone
    case clearPhone
    case addTag
    case removeTag
    case setLocationSharing
    case setSubscription
    case setLogLevel
}

enum CallOutcome: String {
    case ok
    case skipped
    case failed
}

enum PayloadKind: String {
    case received
    case clicked
}

/// Everything the log can say. There is no case that carries a free string to print:
/// SDK data (token, email, phone, client key, payload values) cannot reach a row
/// (EXR-03, LGPD). Payload keys are the one string input, and only keys from
/// `ExampleLog.knownPayloadKeys` are shown; the rest is counted.
enum LogEvent {
    case notConfigured
    case call(ExampleCall, CallOutcome)
    case permission(granted: Bool)
    case payload(PayloadKind, keys: [String])

    var text: String {
        switch self {
        case .notConfigured:
            return "not configured: Notti.initialize skipped"
        case let .call(call, outcome):
            return "\(call.rawValue): \(outcome.rawValue)"
        case let .permission(granted):
            return "permission: \(granted ? "granted" : "denied")"
        case let .payload(kind, keys):
            let known = Set(keys).intersection(ExampleLog.knownPayloadKeys).sorted()
            let otherCount = Set(keys).subtracting(ExampleLog.knownPayloadKeys).count
            var parts = known
            if otherCount > 0 { parts.append("+\(otherCount) other") }
            return "\(kind.rawValue): keys [\(parts.joined(separator: ", "))]"
        }
    }
}

@MainActor
final class ExampleLog: ObservableObject {
    /// Payload keys the backend defines. A host or campaign can add any other key, whose
    /// name may itself carry data, so those are counted, not named.
    nonisolated static let knownPayloadKeys: Set<String> = ["notification_id", "delivery_id"]
    nonisolated static let maxRows = 200

    @Published private(set) var rows: [String] = []

    func record(_ event: LogEvent) {
        rows.append(event.text)
        if rows.count > Self.maxRows { rows.removeFirst(rows.count - Self.maxRows) }
    }

    func clear() {
        rows.removeAll()
    }
}

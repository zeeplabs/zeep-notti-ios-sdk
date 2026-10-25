import Foundation

/// Layout chosen by the server. An unknown value renders as `.center` (IAM-05).
enum NottiInAppFormat: Equatable {
    case top
    case center
    case bottom
    case full
}

enum NottiInAppTrigger: Equatable {
    case sessionStart
    /// Never empty; matched byte for byte against `trackEvent` (IAM-08).
    case event(String)
    /// Unknown trigger type, or an `event` trigger without a name.
    case unsupported
}

enum NottiInAppLinkType: String, Equatable {
    case url
    case deeplink
}

/// A link the integrator handles. The SDK never opens it; `value` is exactly what the server sent.
struct NottiInAppLinkAction: Equatable {
    let type: NottiInAppLinkType
    let value: String
}

/// A button action: a link, or `push_permission` (button only, no value, run by the SDK, IAM-49).
enum NottiInAppButtonAction: Equatable {
    case link(NottiInAppLinkAction)
    case pushPermission
}

/// `action` is nil when the payload had an unknown or malformed action.
struct NottiInAppButton: Equatable {
    let id: String
    let label: String
    let action: NottiInAppButtonAction?
}

/// A message from the `eligible` response (port of RN `InAppMessage`, 0.8.0). `renderable` is false
/// when the SDK must skip it (IAM-16). `rawStyle` is the payload's `style` object as parsed (empty for
/// `null`, absent or a non-object), resolved into tokens by `NottiInAppStyle`.
struct NottiInAppMessage {
    let id: String
    let format: NottiInAppFormat
    let title: String
    let body: String
    let imageUrl: URL?
    let imageAction: NottiInAppLinkAction?
    let rawStyle: [String: Any]
    let dismissAfterSeconds: Int?
    let trigger: NottiInAppTrigger
    let buttons: [NottiInAppButton]
    let renderable: Bool
}

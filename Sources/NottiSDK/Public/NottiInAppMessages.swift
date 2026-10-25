import Foundation

// MARK: - In-App messages (public shell)

@available(iOSApplicationExtension, unavailable)
extension Notti {

    /// Reports an app event. Shows the oldest waiting In-App message whose trigger names it (exact,
    /// case-sensitive match). Matched on the device: the name is never sent, stored or logged.
    ///
    /// An empty or whitespace-only name, and a call before `initialize`, do nothing.
    public static func trackEvent(_ name: String) {
        NottiFacade.shared.trackEvent(name)
    }

    /// Taps on In-App messages.
    public enum InAppMessages {
        /// Called on the main thread when the user taps a button, the image or the body of a message.
        ///
        /// The SDK never opens a `url` or `deeplink`: the host decides what the link means. A
        /// `push_permission` button arrives with `action == nil`. Keep the subscription and call
        /// `remove()` to stop; it is not removed on `deinit`.
        @discardableResult
        public static func addClickListener(_ handler: @escaping (NottiInAppClick) -> Void) -> NottiSubscription {
            NottiFacade.shared.addInAppClickListener(handler)
        }
    }
}

/// A tap on an In-App message, delivered to `Notti.InAppMessages.addClickListener`.
public struct NottiInAppClick: Equatable, Sendable {
    /// The id of the message the server sent.
    public let messageId: String
    /// The tapped button's id; `image` for the image.
    public let buttonId: String
    /// The link to handle, exactly as the server sent it; nil for a button without a valid action and for a
    /// `push_permission` button.
    public let action: NottiInAppAction?
}

/// A link of an In-App message. The SDK never opens, validates or rewrites it.
public struct NottiInAppAction: Equatable, Sendable {
    /// `url` or `deeplink`, as the server sent it.
    public enum ActionType: String, Sendable {
        case url
        case deeplink
    }

    public let type: ActionType
    /// The untouched link value.
    public let value: String

    init(type: ActionType, value: String) {
        self.type = type
        self.value = value
    }

    /// The public form of a parsed link (IAM-24): same type, same value.
    init(link: NottiInAppLinkAction) {
        switch link.type {
        case .url: self.init(type: .url, value: link.value)
        case .deeplink: self.init(type: .deeplink, value: link.value)
        }
    }
}

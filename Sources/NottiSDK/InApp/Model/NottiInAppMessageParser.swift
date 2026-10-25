import Foundation

/// Lenient parser of an `eligible` 200 body, a port of RN `NottiInAppModels.swift:81-244` (0.8.0).
/// Each message is mapped independently: unknown fields are ignored and an entry that is not an
/// object is skipped without affecting the others (IAM-05, IAM-16). Never traps, never logs.
enum NottiInAppMessageParser {

    static let maxButtons = 2
    static let dismissSecondsRange = 1.0...300.0

    /// The messages in server order, or nil (a transient failure for the caller) when the body is not
    /// a JSON object or `messages` is not an array. An empty array is a valid result.
    static func parse(_ data: Data) -> [NottiInAppMessage]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["messages"] as? [Any]
        else {
            return nil
        }
        return entries.compactMap { entry in
            (entry as? [String: Any]).map(parseMessage)
        }
    }

    private static func parseMessage(_ object: [String: Any]) -> NottiInAppMessage {
        let id = string(object["id"])
        let title = string(object["title"])
        let body = string(object["body"])
        let imageUrl = parseImageUrl(object["image_url"])
        let trigger = parseTrigger(object["trigger"])
        return NottiInAppMessage(
            id: id,
            format: parseFormat(object["format"]),
            title: title,
            body: body,
            imageUrl: imageUrl,
            imageAction: imageUrl == nil ? nil : parseLinkAction(object["image_action"]),
            rawStyle: object["style"] as? [String: Any] ?? [:],
            dismissAfterSeconds: parseDismissSeconds(object["dismiss_after_seconds"]),
            trigger: trigger,
            buttons: parseButtons(object["buttons"]),
            renderable: !id.isEmpty && (!isBlank(title) || !isBlank(body)) && trigger != .unsupported
        )
    }

    private static func string(_ raw: Any?) -> String { raw as? String ?? "" }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `https://` in any case and longer than the scheme, else dropped (IAM-16).
    private static func parseImageUrl(_ raw: Any?) -> URL? {
        guard let value = raw as? String else { return nil }
        let scheme = "https://"
        guard value.utf16.count > scheme.utf16.count, value.prefix(scheme.count).lowercased() == scheme else {
            return nil
        }
        return URL(string: value)
    }

    private static func parseFormat(_ raw: Any?) -> NottiInAppFormat {
        switch raw as? String {
        case "top": return .top
        case "bottom": return .bottom
        case "full": return .full
        default: return .center
        }
    }

    private static func parseTrigger(_ raw: Any?) -> NottiInAppTrigger {
        guard let object = raw as? [String: Any] else { return .unsupported }
        switch object["type"] as? String {
        case "session_start":
            return .sessionStart
        case "event":
            let name = string(object["name"])
            return name.isEmpty ? .unsupported : .event(name)
        default:
            return .unsupported
        }
    }

    /// `url` or `deeplink` with a non-empty string `value`, else nil.
    private static func parseLinkAction(_ raw: Any?) -> NottiInAppLinkAction? {
        guard
            let object = raw as? [String: Any],
            let type = (object["type"] as? String).flatMap(NottiInAppLinkType.init(rawValue:))
        else {
            return nil
        }
        let value = string(object["value"])
        return value.isEmpty ? nil : NottiInAppLinkAction(type: type, value: value)
    }

    /// A link, or `push_permission` (no value read). Buttons only (IAM-49).
    private static func parseButtonAction(_ raw: Any?) -> NottiInAppButtonAction? {
        if let object = raw as? [String: Any], object["type"] as? String == "push_permission" {
            return .pushPermission
        }
        return parseLinkAction(raw).map(NottiInAppButtonAction.link)
    }

    private static func parseButtons(_ raw: Any?) -> [NottiInAppButton] {
        guard let entries = raw as? [Any] else { return [] }
        var buttons: [NottiInAppButton] = []
        for entry in entries {
            if buttons.count == maxButtons { break }
            guard let object = entry as? [String: Any] else { continue }
            let id = string(object["id"])
            let label = string(object["label"])
            if id.isEmpty || label.isEmpty { continue }
            buttons.append(NottiInAppButton(id: id, label: label, action: parseButtonAction(object["action"])))
        }
        return buttons
    }

    /// A JSON number (not a boolean), integral, 1...300; else no timer.
    private static func parseDismissSeconds(_ raw: Any?) -> Int? {
        guard let seconds = NottiInAppJSON.number(raw)?.doubleValue else { return nil }
        guard seconds == seconds.rounded(.down), dismissSecondsRange.contains(seconds) else { return nil }
        return Int(seconds)
    }
}

/// Tells JSON numbers and booleans apart. `JSONSerialization` returns both as `NSNumber`, and
/// `as? Int` / `as? Bool` bridge across them (`true` reads as `1`, `1` as `true`).
enum NottiInAppJSON {

    static func number(_ raw: Any?) -> NSNumber? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }

    static func bool(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

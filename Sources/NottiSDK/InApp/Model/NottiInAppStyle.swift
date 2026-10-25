import Foundation

/// Absolute side for title and body (IAM-21): `right` stays right in a right-to-left layout.
enum NottiInAppTextAlign: Equatable {
    case left
    case center
    case right
}

/// Look tokens of a message (port of RN `InAppStyle` / `parseStyle`, 0.8.0). Colors are opaque
/// `0xFFRRGGBB` values; nil means "use the SDK default" (absent or unparseable token, IAM-20). Each
/// token is read on its own, so an invalid one never affects the others.
struct NottiInAppStyle: Equatable {
    var backgroundColor: UInt32?
    var textColor: UInt32?
    var buttonColor: UInt32?
    var buttonTextColor: UInt32?
    var textAlign: NottiInAppTextAlign = .left
    var margin = true

    init() {}

    /// From the payload's `style` object as the parser kept it (empty for `null` or absent, IAM-22).
    init(raw: [String: Any]) {
        backgroundColor = NottiInAppColor.parse(raw["background_color"])
        textColor = NottiInAppColor.parse(raw["text_color"])
        buttonColor = NottiInAppColor.parse(raw["button_color"])
        buttonTextColor = NottiInAppColor.parse(raw["button_text_color"])
        switch raw["text_align"] as? String {
        case "center": textAlign = .center
        case "right": textAlign = .right
        default: textAlign = .left
        }
        margin = NottiInAppJSON.bool(raw["margin"]) ?? true
    }
}

enum NottiInAppColor {

    /// `#RRGGBB` (either case) to an opaque `0xFFRRGGBB`; anything else (`#RGB`, alpha form, no `#`,
    /// non-hex, a sign, blank, non-string, nil) is nil. Checked byte by byte rather than with
    /// `UInt32(_:radix:)`, which accepts a leading `+`/`-` (RN `parseHexColor`). Never traps.
    static func parse(_ raw: Any?) -> UInt32? {
        guard let value = raw as? String else { return nil }
        let bytes = Array(value.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return nil }
        var rgb: UInt32 = 0
        for byte in bytes[1...] {
            guard let digit = hexDigit(byte) else { return nil }
            rgb = (rgb << 4) | digit
        }
        return 0xFF00_0000 | rgb
    }

    private static func hexDigit(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return UInt32(byte - UInt8(ascii: "A") + 10)
        default: return nil
        }
    }
}

extension NottiInAppMessage {
    /// The resolved look tokens of this message.
    var style: NottiInAppStyle { NottiInAppStyle(raw: rawStyle) }
}

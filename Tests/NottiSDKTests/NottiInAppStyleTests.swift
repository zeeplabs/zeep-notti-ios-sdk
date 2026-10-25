import XCTest
@testable import NottiSDK

/// IAM-20, IAM-21, IAM-22 (token side). Cases from RN `NottiInAppModelsTests` / `NottiInAppStyleTests`
/// (0.8.0, `parseHexColor` and `parseStyle`). JSON keys are literals on purpose.
final class NottiInAppStyleTests: XCTestCase {

    /// The style of a message whose `style` field is `json` (omitted when nil), through the T1 parser.
    private func styleOf(_ json: String?) -> NottiInAppStyle? {
        let style = json.map { #", "style": \#($0)"# } ?? ""
        let body = #"{"messages": [{"id": "fixture", "title": "t", "trigger": {"type": "session_start"}\#(style)}]}"#
        return NottiInAppMessageParser.parse(Data(body.utf8))?.first?.style
    }

    // MARK: - NottiInAppColor.parse

    func test_rrggbbParsesToTheExactOpaqueComponents() {
        XCTAssertEqual(NottiInAppColor.parse("#102030"), 0xFF10_2030)
        XCTAssertEqual(NottiInAppColor.parse("#e94b8b"), 0xFFE9_4B8B)
        XCTAssertEqual(NottiInAppColor.parse("#E94B8B"), 0xFFE9_4B8B)
        XCTAssertEqual(NottiInAppColor.parse("#FFFFFF"), 0xFFFF_FFFF)
        XCTAssertEqual(NottiInAppColor.parse("#000000"), 0xFF00_0000)
        XCTAssertEqual(NottiInAppColor.parse("#aBcDeF"), 0xFFAB_CDEF)
    }

    func test_everyOtherStringFormGivesNil() {
        let values = [
            "#FFF", "102030", "#10203040", "#GGGGGG", "#+12345", "#-12345", "", " ", "#", "red",
            "#10203", "#1020301", " #102030", "#102030 ", "#102030\n", "#10 030", "rgb(1,2,3)", "#10203é", "＃102030"
        ]
        for value in values {
            XCTAssertNil(NottiInAppColor.parse(value), "value: \(value)")
        }
    }

    func test_nonStringValuesGiveNilWithoutThrowing() {
        let values: [Any?] = [nil, 0x102030, NSNumber(value: 1_056_816), true, NSNull(), ["#102030"], ["c": "#102030"]]
        for value in values {
            XCTAssertNil(NottiInAppColor.parse(value), "value: \(String(describing: value))")
        }
    }

    // MARK: - Tokens

    func test_nullMissingOrNonObjectStyleGivesTheDefaults() {
        let defaults = NottiInAppStyle()
        XCTAssertNil(defaults.backgroundColor)
        XCTAssertNil(defaults.textColor)
        XCTAssertNil(defaults.buttonColor)
        XCTAssertNil(defaults.buttonTextColor)
        XCTAssertEqual(defaults.textAlign, .left)
        XCTAssertTrue(defaults.margin)
        XCTAssertEqual(styleOf(nil), defaults)
        XCTAssertEqual(styleOf("null"), defaults)
        XCTAssertEqual(styleOf("{}"), defaults)
        XCTAssertEqual(styleOf(#""dark""#), defaults)
    }

    func test_allTokensAreRead() throws {
        let style = try XCTUnwrap(styleOf(
            ##"{"background_color": "#102030", "text_color": "#ffffff", "button_color": "#E94B8B", "##
                + ##""button_text_color": "#000000", "text_align": "center", "margin": false}"##
        ))
        XCTAssertEqual(style.backgroundColor, 0xFF10_2030)
        XCTAssertEqual(style.textColor, 0xFFFF_FFFF)
        XCTAssertEqual(style.buttonColor, 0xFFE9_4B8B)
        XCTAssertEqual(style.buttonTextColor, 0xFF00_0000)
        XCTAssertEqual(style.textAlign, .center)
        XCTAssertFalse(style.margin)
    }

    func test_textAlignMapsLeftCenterRight() {
        XCTAssertEqual(styleOf(#"{"text_align": "left"}"#)?.textAlign, .left)
        XCTAssertEqual(styleOf(#"{"text_align": "center"}"#)?.textAlign, .center)
        XCTAssertEqual(styleOf(#"{"text_align": "right"}"#)?.textAlign, .right)
    }

    func test_textAlignAbsentOrUnknownIsLeft() {
        for json in ["{}", #"{"text_align": "justify"}"#, #"{"text_align": "CENTER"}"#,
                     #"{"text_align": "start"}"#, #"{"text_align": 1}"#, #"{"text_align": null}"#] {
            XCTAssertEqual(styleOf(json)?.textAlign, .left, json)
        }
    }

    func test_marginTrueFalseAndAbsent() {
        XCTAssertEqual(styleOf(#"{"margin": true}"#)?.margin, true)
        XCTAssertEqual(styleOf(#"{"margin": false}"#)?.margin, false)
        XCTAssertEqual(styleOf("{}")?.margin, true)
    }

    func test_aNonBooleanMarginIsTheDefaultTrue() {
        // `0` would bridge to `false` through `as? Bool`; it must fall back to the default instead.
        for json in [#"{"margin": 0}"#, #"{"margin": 1}"#, #"{"margin": "no"}"#, #"{"margin": "false"}"#,
                     #"{"margin": null}"#, #"{"margin": {}}"#] {
            XCTAssertEqual(styleOf(json)?.margin, true, json)
        }
    }

    func test_anInvalidColorTokenDoesNotAffectTheOthers() throws {
        let style = try XCTUnwrap(styleOf(
            ##"{"background_color": "red", "text_color": "#FFFFFF", "button_color": "#12345678", "##
                + ##""button_text_color": "#e94b8b", "text_align": "right", "margin": false}"##
        ))
        XCTAssertNil(style.backgroundColor)
        XCTAssertEqual(style.textColor, 0xFFFF_FFFF)
        XCTAssertNil(style.buttonColor)
        XCTAssertEqual(style.buttonTextColor, 0xFFE9_4B8B)
        XCTAssertEqual(style.textAlign, .right)
        XCTAssertFalse(style.margin)
    }

    func test_eachInvalidColorTokenFallsBackAloneWhileTheOthersApply() throws {
        let keys = ["background_color", "text_color", "button_color", "button_text_color"]
        for bad in [##""#FFF""##, #""102030""#, "5", "null", "true", ##""#GG0000""##] {
            for key in keys {
                let others = keys.filter { $0 != key }.map { ##""\##($0)": "#102030""## }
                let style = try XCTUnwrap(styleOf("{" + (others + [#""\#(key)": \#(bad)"#]).joined(separator: ", ") + "}"))
                let tokens: [String: UInt32?] = [
                    "background_color": style.backgroundColor,
                    "text_color": style.textColor,
                    "button_color": style.buttonColor,
                    "button_text_color": style.buttonTextColor
                ]
                for (name, value) in tokens {
                    XCTAssertEqual(value, name == key ? nil : 0xFF10_2030, "bad \(bad) in \(key), token \(name)")
                }
            }
        }
    }

    func test_anInvalidTextAlignOrMarginDoesNotAffectTheColors() throws {
        let style = try XCTUnwrap(styleOf(##"{"text_color": "#102030", "text_align": 3, "margin": "x"}"##))
        XCTAssertEqual(style.textColor, 0xFF10_2030)
        XCTAssertEqual(style.textAlign, .left)
        XCTAssertTrue(style.margin)
    }
}

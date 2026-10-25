import XCTest
@testable import NottiSDK

/// IAM-05, IAM-16, IAM-49 (parse side). Ported from RN `NottiInAppModelsTests.swift` (0.8.0) plus the
/// contract example of `docs/en/sdks/in-app-messages.md`. JSON keys and limits are literals on purpose.
/// Synthetic values only (`fixture`, `example.invalid`).
final class NottiInAppMessageParserTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ body: String) -> [NottiInAppMessage]? {
        NottiInAppMessageParser.parse(Data(body.utf8))
    }

    /// One message with a valid id, title, body and trigger plus `extra` fields.
    private func parseOne(
        _ extra: String...,
        id: String = #""fixture-id""#,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> NottiInAppMessage? {
        var fields = [
            #""id": \#(id)"#,
            #""title": "fixture""#,
            #""body": "fixture body""#,
            #""trigger": {"type": "session_start"}"#
        ]
        fields.append(contentsOf: extra)
        let parsed = parse(#"{"messages": [{\#(fields.joined(separator: ","))}]}"#)
        XCTAssertEqual(parsed?.count, 1, file: file, line: line)
        return parsed?.first
    }

    private func parseRaw(_ entry: String) -> NottiInAppMessage? {
        parse(#"{"messages": [\#(entry)]}"#)?.first
    }

    private func valid(_ id: String) -> String {
        #"{"id": "\#(id)", "title": "t", "trigger": {"type": "session_start"}}"#
    }

    // MARK: - Contract example payload

    private let contractExample = ##"""
    {
      "messages": [
        {
          "id": "fixture-message-a1",
          "format": "center",
          "title": "Example title",
          "body": "Example body text.",
          "image_url": "https://cdn.example.invalid/example.png",
          "image_action": { "type": "url", "value": "https://example.invalid/offer" },
          "style": {
            "background_color": "#102030",
            "text_color": "#FFFFFF",
            "button_color": "#E94B8B",
            "button_text_color": "#FFFFFF",
            "text_align": "center",
            "margin": true
          },
          "dismiss_after_seconds": 8,
          "trigger": { "type": "event", "name": "checkout_done" },
          "buttons": [
            {
              "id": "fixture-button-1",
              "label": "See more",
              "action": { "type": "deeplink", "value": "exampleapp://offers/42" }
            },
            {
              "id": "fixture-button-2",
              "label": "Docs",
              "action": { "type": "url", "value": "https://example.invalid/docs" }
            }
          ]
        }
      ]
    }
    """##

    func test_theContractExampleMapsFieldByField() throws {
        let messages = try XCTUnwrap(parse(contractExample))
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.id, "fixture-message-a1")
        XCTAssertEqual(message.format, .center)
        XCTAssertEqual(message.title, "Example title")
        XCTAssertEqual(message.body, "Example body text.")
        XCTAssertEqual(message.imageUrl, URL(string: "https://cdn.example.invalid/example.png"))
        XCTAssertEqual(message.imageAction, NottiInAppLinkAction(type: .url, value: "https://example.invalid/offer"))
        XCTAssertEqual(message.dismissAfterSeconds, 8)
        XCTAssertEqual(message.trigger, .event("checkout_done"))
        XCTAssertEqual(message.buttons, [
            NottiInAppButton(
                id: "fixture-button-1",
                label: "See more",
                action: .link(NottiInAppLinkAction(type: .deeplink, value: "exampleapp://offers/42"))
            ),
            NottiInAppButton(
                id: "fixture-button-2",
                label: "Docs",
                action: .link(NottiInAppLinkAction(type: .url, value: "https://example.invalid/docs"))
            )
        ])
        XCTAssertTrue(message.renderable)
        // The raw style object is kept verbatim for `NottiInAppStyle` (T2).
        XCTAssertEqual(message.rawStyle["background_color"] as? String, "#102030")
        XCTAssertEqual(message.rawStyle["text_color"] as? String, "#FFFFFF")
        XCTAssertEqual(message.rawStyle["button_color"] as? String, "#E94B8B")
        XCTAssertEqual(message.rawStyle["button_text_color"] as? String, "#FFFFFF")
        XCTAssertEqual(message.rawStyle["text_align"] as? String, "center")
        XCTAssertEqual(message.rawStyle["margin"] as? Bool, true)
        XCTAssertEqual(message.rawStyle.count, 6)
    }

    // MARK: - Envelope

    func test_aBodyThatIsNotAJSONObjectOrHasNoMessagesArrayGivesNil() {
        for body in ["", "not json", "[]", #""text""#, "null", "42", "{}",
                     #"{"messages": null}"#, #"{"messages": {}}"#, #"{"messages": "x"}"#] {
            XCTAssertNil(parse(body), "body: \(body)")
        }
    }

    func test_anEmptyMessagesArrayIsValidAndServerOrderIsKept() {
        XCTAssertEqual(parse(#"{"messages": []}"#)?.count, 0)
        let body = #"{"messages": [\#(valid("c")), \#(valid("a")), \#(valid("b"))]}"#
        XCTAssertEqual(parse(body)?.map(\.id), ["c", "a", "b"])
    }

    func test_unknownFieldsAreIgnoredAtEveryLevel() throws {
        let body = #"""
        {"future_root": 1, "messages": [{"id": "a", "title": "t", "future": {"x": [1]},
          "trigger": {"type": "session_start", "future": true},
          "image_url": "https://example.invalid/i.png",
          "image_action": {"type": "url", "value": "https://example.invalid/o", "future": 2},
          "style": {"future_token": "x"},
          "buttons": [{"id": "b1", "label": "Go", "future": true,
                       "action": {"type": "url", "value": "https://example.invalid/x", "future": 1}}]}]}
        """#
        let message = try XCTUnwrap(parse(body)?.first)
        XCTAssertTrue(message.renderable)
        XCTAssertEqual(message.trigger, .sessionStart)
        XCTAssertEqual(message.imageAction, NottiInAppLinkAction(type: .url, value: "https://example.invalid/o"))
        XCTAssertEqual(message.buttons.map(\.id), ["b1"])
        XCTAssertEqual(message.buttons.first?.action, .link(NottiInAppLinkAction(type: .url, value: "https://example.invalid/x")))
    }

    func test_anEntryThatIsNotAnObjectIsSkippedAndTheOthersSurvive() {
        let body = #"{"messages": [42, \#(valid("a")), "text", null, [], \#(valid("b"))]}"#
        XCTAssertEqual(parse(body)?.map(\.id), ["a", "b"])
    }

    // MARK: - Format

    func test_knownFormatsMapAndAnUnknownOrMissingFormatIsCenter() {
        XCTAssertEqual(parseOne(#""format": "top""#)?.format, .top)
        XCTAssertEqual(parseOne(#""format": "bottom""#)?.format, .bottom)
        XCTAssertEqual(parseOne(#""format": "full""#)?.format, .full)
        XCTAssertEqual(parseOne(#""format": "center""#)?.format, .center)
        XCTAssertEqual(parseOne(#""format": "carousel""#)?.format, .center)
        XCTAssertEqual(parseOne(#""format": "TOP""#)?.format, .center)
        XCTAssertEqual(parseOne(#""format": 3"#)?.format, .center)
        XCTAssertEqual(parseOne()?.format, .center)
        XCTAssertEqual(parseOne(#""format": "carousel""#)?.renderable, true)
    }

    // MARK: - Style input

    func test_nullMissingOrNonObjectStyleGivesTheDefaultStyleInput() {
        XCTAssertTrue(parseOne()?.rawStyle.isEmpty ?? false)
        XCTAssertTrue(parseOne(#""style": null"#)?.rawStyle.isEmpty ?? false)
        XCTAssertTrue(parseOne(#""style": "dark""#)?.rawStyle.isEmpty ?? false)
        XCTAssertTrue(parseOne(#""style": []"#)?.rawStyle.isEmpty ?? false)
    }

    // MARK: - Renderability (IAM-16)

    func test_anEmptyMissingOrNonStringIdIsNotRenderableAndTheOthersSurvive() {
        let body = #"""
        {"messages": [
          {"id": "", "title": "t", "trigger": {"type": "session_start"}},
          {"title": "t", "trigger": {"type": "session_start"}},
          {"id": 7, "title": "t", "trigger": {"type": "session_start"}},
          \#(valid("ok"))
        ]}
        """#
        let messages = parse(body)
        XCTAssertEqual(messages?.map(\.renderable), [false, false, false, true])
        XCTAssertEqual(messages?.last?.id, "ok")
    }

    func test_blankTitleAndBodyIsNotRenderableButOneNonBlankIsEnough() {
        let trigger = #""trigger": {"type": "session_start"}"#
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": "  \n\t", "body": "", \#(trigger)}"#)?.renderable, false)
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": " ", "body": "   ", \#(trigger)}"#)?.renderable, false)
        XCTAssertEqual(parseRaw(#"{"id": "a", \#(trigger)}"#)?.renderable, false)
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": 5, "body": null, \#(trigger)}"#)?.renderable, false)
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": "", "body": "text", \#(trigger)}"#)?.renderable, true)
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": "text", \#(trigger)}"#)?.renderable, true)
    }

    func test_titleAndBodyAreKeptVerbatim() {
        let parsed = parseRaw(
            #"{"id": "a", "title": " <b>Hi</b> **x** ", "body": "line1\nline2", "trigger": {"type": "session_start"}}"#
        )
        XCTAssertEqual(parsed?.title, " <b>Hi</b> **x** ")
        XCTAssertEqual(parsed?.body, "line1\nline2")
    }

    func test_unknownMissingOrNamelessTriggerIsNotRenderable() {
        for trigger in [
            #""trigger": {"type": "scroll"}"#,
            #""trigger": {"type": "SESSION_START"}"#,
            #""trigger": null"#,
            #""trigger": "session_start""#,
            #""trigger": {"type": "event"}"#,
            #""trigger": {"type": "event", "name": ""}"#,
            #""trigger": {"type": "event", "name": 3}"#
        ] {
            let parsed = parseRaw(#"{"id": "a", "title": "t", \#(trigger)}"#)
            XCTAssertEqual(parsed?.trigger, .unsupported, trigger)
            XCTAssertEqual(parsed?.renderable, false, trigger)
        }
        XCTAssertEqual(parseRaw(#"{"id": "a", "title": "t"}"#)?.renderable, false)
    }

    func test_anEventTriggerKeepsItsNameByteForByte() {
        let parsed = parseRaw(#"{"id": "a", "title": "t", "trigger": {"type": "event", "name": " Checkout_Done "}}"#)
        XCTAssertEqual(parsed?.trigger, .event(" Checkout_Done "))
        XCTAssertEqual(parsed?.renderable, true)
    }

    // MARK: - Buttons

    func test_aButtonWithoutIdOrLabelIsDroppedAndTheMessageStaysRenderable() {
        let parsed = parseOne(
            #""buttons": [{"id": "", "label": "No id"}, {"label": "Missing id"}, {"id": "b1", "label": ""},"#
                + #"{"id": "b2"}, {"id": 5, "label": "Bad id type"}, {"id": "b3", "label": 4}, "not an object"]"#
        )
        XCTAssertEqual(parsed?.renderable, true)
        XCTAssertEqual(parsed?.buttons, [])
    }

    func test_onlyTheFirstTwoValidButtonsAreKeptInOrder() {
        XCTAssertEqual(
            parseOne(#""buttons": [{"id": "b1", "label": "1"}, {"id": "b2", "label": "2"}, {"id": "b3", "label": "3"}]"#)?
                .buttons.map(\.id),
            ["b1", "b2"]
        )
        XCTAssertEqual(
            parseOne(#""buttons": [{"id": "", "label": "x"}, {"id": "b1", "label": "1"}, {"id": "b2", "label": "2"},"#
                + #"{"id": "b3", "label": "3"}]"#)?.buttons.map(\.id),
            ["b1", "b2"]
        )
        XCTAssertEqual(parseOne(#""buttons": null"#)?.buttons, [])
        XCTAssertEqual(parseOne(#""buttons": {}"#)?.buttons, [])
    }

    // MARK: - Actions

    func test_aLinkActionWithAnEmptyOrMissingValueIsNilAndItsButtonIsKept() {
        for action in [
            #"{"type": "url"}"#,
            #"{"type": "url", "value": ""}"#,
            #"{"type": "deeplink", "value": ""}"#,
            #"{"type": "deeplink", "value": 5}"#,
            #"{"type": "url", "value": null}"#
        ] {
            let parsed = parseOne(#""buttons": [{"id": "b1", "label": "Go", "action": \#(action)}]"#)
            XCTAssertEqual(parsed?.buttons.map(\.id), ["b1"], action)
            XCTAssertNil(parsed?.buttons.first?.action, action)
        }
    }

    func test_anUnknownMissingOrMalformedActionIsNilAndItsButtonIsKept() {
        for button in [
            #"{"id": "b1", "label": "Go", "action": {"type": "share", "value": "x"}}"#,
            #"{"id": "b1", "label": "Go", "action": {"type": "URL", "value": "x"}}"#,
            #"{"id": "b1", "label": "Go", "action": {"value": "x"}}"#,
            #"{"id": "b1", "label": "Go"}"#,
            #"{"id": "b1", "label": "Go", "action": null}"#,
            #"{"id": "b1", "label": "Go", "action": "url"}"#
        ] {
            let parsed = parseOne(#""buttons": [\#(button)]"#)
            XCTAssertEqual(parsed?.buttons.count, 1, button)
            XCTAssertNil(parsed?.buttons.first?.action, button)
            XCTAssertEqual(parsed?.renderable, true, button)
        }
    }

    func test_aLinkValueIsKeptByteForByte() {
        let value = "exampleapp://offers/42?utm=a b&x=%20  "
        let parsed = parseOne(#""buttons": [{"id": "b1", "label": "Go", "action": {"type": "deeplink", "value": "\#(value)"}}]"#)
        XCTAssertEqual(parsed?.buttons.first?.action, .link(NottiInAppLinkAction(type: .deeplink, value: value)))
    }

    func test_pushPermissionOnAButtonParsesWithoutReadingAValue() {
        for action in [#"{"type": "push_permission"}"#, #"{"type": "push_permission", "value": "ignored"}"#,
                       #"{"type": "push_permission", "value": 3}"#] {
            let parsed = parseOne(#""buttons": [{"id": "b1", "label": "Allow", "action": \#(action)}]"#)
            XCTAssertEqual(parsed?.buttons.first?.action, .pushPermission, action)
            XCTAssertEqual(parsed?.renderable, true, action)
        }
    }

    func test_pushPermissionAsImageActionIsDroppedAndTheImageStays() {
        let parsed = parseOne(
            #""image_url": "https://example.invalid/i.png""#,
            #""image_action": {"type": "push_permission"}"#
        )
        XCTAssertEqual(parsed?.imageUrl, URL(string: "https://example.invalid/i.png"))
        XCTAssertNil(parsed?.imageAction)
    }

    // MARK: - Image

    func test_anHttpsImageUrlIsKeptInAnyCaseOfTheScheme() {
        XCTAssertEqual(
            parseOne(#""image_url": "https://example.invalid/i.png""#)?.imageUrl,
            URL(string: "https://example.invalid/i.png")
        )
        XCTAssertEqual(
            parseOne(#""image_url": "HTTPS://example.invalid/i.png""#)?.imageUrl,
            URL(string: "HTTPS://example.invalid/i.png")
        )
    }

    func test_aNonHttpsImageUrlIsDroppedAndTheMessageStaysRenderable() {
        for imageUrl in [
            #""http://example.invalid/i.png""#,
            #""https://""#,
            #""HTTPS://""#,
            #""//example.invalid/i.png""#,
            #""/i.png""#,
            #""not a url at all""#,
            #""ftp://example.invalid/i.png""#,
            #""""#,
            "null",
            "5"
        ] {
            let parsed = parseOne(#""image_url": \#(imageUrl)"#)
            XCTAssertNil(parsed?.imageUrl, imageUrl)
            XCTAssertEqual(parsed?.renderable, true, imageUrl)
        }
    }

    func test_anImageActionWithoutAValidImageIsDropped() {
        let action = #""image_action": {"type": "url", "value": "https://example.invalid/offer"}"#
        XCTAssertNil(parseOne(action)?.imageAction)
        XCTAssertNil(parseOne(#""image_url": "http://example.invalid/i.png""#, action)?.imageAction)
        XCTAssertNil(parseOne(#""image_url": "https://""#, action)?.imageAction)
        let unknown = parseOne(#""image_url": "https://example.invalid/i.png""#, #""image_action": {"type": "share", "value": "x"}"#)
        XCTAssertNotNil(unknown?.imageUrl)
        XCTAssertNil(unknown?.imageAction)
    }

    // MARK: - dismiss_after_seconds

    func test_dismissAfterSecondsKeepsOnlyIntegralNumbersFrom1To300() {
        XCTAssertEqual(parseOne(#""dismiss_after_seconds": 1"#)?.dismissAfterSeconds, 1)
        XCTAssertEqual(parseOne(#""dismiss_after_seconds": 8.0"#)?.dismissAfterSeconds, 8)
        XCTAssertEqual(parseOne(#""dismiss_after_seconds": 300"#)?.dismissAfterSeconds, 300)
        for value in ["0", "-1", "301", "100000", "8.5", "true", "false", #""8""#, "null", "{}", "[]"] {
            XCTAssertNil(parseOne(#""dismiss_after_seconds": \#(value)"#)?.dismissAfterSeconds, value)
        }
        XCTAssertNil(parseOne()?.dismissAfterSeconds)
    }

    // MARK: - margin is a JSON boolean only

    func test_aNumericMarginIsKeptAsANumberNotABoolean() {
        // `margin: 1` must not read as `true` through NSNumber bridging; T2 resolves it to the default.
        let parsed = parseOne(#""style": {"margin": 1}"#)
        let raw = parsed?.rawStyle["margin"] as? NSNumber
        XCTAssertNotNil(raw)
        XCTAssertNil(NottiInAppJSON.bool(raw))
        XCTAssertEqual(NottiInAppJSON.bool(parseOne(#""style": {"margin": false}"#)?.rawStyle["margin"]), false)
        XCTAssertNil(NottiInAppJSON.number(NSNumber(value: true)))
    }
}

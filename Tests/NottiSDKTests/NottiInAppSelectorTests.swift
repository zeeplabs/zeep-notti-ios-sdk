import XCTest
@testable import NottiSDK

/// IAM-07, IAM-08, IAM-09, IAM-11, IAM-12. Port of the selection cases of RN `NottiInAppSessionTests`
/// (0.8.0, `NottiInAppSession.swift:156-242,298-315`). Synthetic ids and names only.
final class NottiInAppSelectorTests: XCTestCase {

    private func message(_ id: String, _ trigger: NottiInAppTrigger, renderable: Bool = true) -> NottiInAppMessage {
        NottiInAppMessage(
            id: id, format: .center, title: "fixture", body: "", imageUrl: nil, imageAction: nil, rawStyle: [:],
            dismissAfterSeconds: nil, trigger: trigger, buttons: [], renderable: renderable
        )
    }

    private func sessionStart(_ id: String) -> NottiInAppMessage { message(id, .sessionStart) }
    private func event(_ id: String, _ name: String) -> NottiInAppMessage { message(id, .event(name)) }

    private func openSelector() -> NottiInAppSelector {
        var selector = NottiInAppSelector()
        selector.startSession(visibleId: nil)
        return selector
    }

    // MARK: - Session start (IAM-07)

    func test_onlyTheFirstSessionStartMessageIsReturnedAndTheSecondNeverIs() {
        var selector = openSelector()
        XCTAssertEqual(selector.load([sessionStart("a"), sessionStart("b")], visibleId: nil)?.id, "a")
        XCTAssertTrue(selector.held.isEmpty)
        XCTAssertNil(selector.track("session_start", isVisible: false))
        XCTAssertNil(selector.track("b", isVisible: false))
        XCTAssertNil(selector.load([sessionStart("a"), sessionStart("b")], visibleId: nil))
    }

    func test_nonRenderableMessagesAreNeitherShownNorHeld() {
        var selector = openSelector()
        let messages = [message("a", .sessionStart, renderable: false), message("b", .event("x"), renderable: false),
                        sessionStart("c")]
        XCTAssertEqual(selector.load(messages, visibleId: nil)?.id, "c")
        XCTAssertTrue(selector.held.isEmpty)
        XCTAssertNil(selector.track("x", isVisible: false))
    }

    // MARK: - Event match (IAM-08, IAM-09)

    func test_eventMessagesAreHeldInServerOrderAndNotReturnedByLoad() {
        var selector = openSelector()
        XCTAssertNil(selector.load([event("e1", "x"), event("e2", "y")], visibleId: nil))
        XCTAssertEqual(selector.held.map(\.id), ["e1", "e2"])
    }

    func test_sameNameReturnsTheOlderThenTheOtherThenNil() {
        var selector = openSelector()
        _ = selector.load([event("old", "checkout_done"), event("new", "checkout_done")], visibleId: nil)
        XCTAssertEqual(selector.track("checkout_done", isVisible: false)?.id, "old")
        XCTAssertEqual(selector.track("checkout_done", isVisible: false)?.id, "new")
        XCTAssertNil(selector.track("checkout_done", isVisible: false))
    }

    func test_theMatchIsExactCaseSensitiveAndUntrimmed() {
        var selector = openSelector()
        _ = selector.load([event("e1", "checkout_done")], visibleId: nil)
        XCTAssertNil(selector.track("Checkout_Done", isVisible: false))
        XCTAssertNil(selector.track(" checkout_done", isVisible: false))
        XCTAssertNil(selector.track("checkout_done ", isVisible: false))
        XCTAssertEqual(selector.track("checkout_done", isVisible: false)?.id, "e1")
    }

    func test_aDuplicateIdIsReturnedAtMostOncePerSession() {
        var selector = openSelector()
        _ = selector.load([event("a", "x"), event("a", "x")], visibleId: nil)
        XCTAssertEqual(selector.track("x", isVisible: false)?.id, "a")
        XCTAssertNil(selector.track("x", isVisible: false))
    }

    func test_trackWhileVisibleReturnsNilAndDoesNotConsumeTheMessage() {
        var selector = openSelector()
        _ = selector.load([event("e1", "x")], visibleId: nil)
        XCTAssertNil(selector.track("x", isVisible: true))
        XCTAssertEqual(selector.held.map(\.id), ["e1"])
        XCTAssertFalse(selector.shown.contains("e1"))
        XCTAssertEqual(selector.track("x", isVisible: false)?.id, "e1")
    }

    // MARK: - Early names (IAM-11)

    func test_namesNotedBeforeLoadAreReplayedInCallOrderOnceReturningAtMostOneMessage() {
        var selector = openSelector()
        selector.noteEarly("buy")
        selector.noteEarly("view")
        XCTAssertEqual(selector.earlyNames, ["buy", "view"])
        XCTAssertEqual(selector.load([event("v", "view"), event("b", "buy")], visibleId: nil)?.id, "b")
        XCTAssertTrue(selector.earlyNames.isEmpty)
        XCTAssertFalse(selector.shown.contains("v"))
        // Replayed once: the `view` message stays held for a later `track`.
        XCTAssertEqual(selector.track("view", isVisible: false)?.id, "v")
    }

    func test_aSessionStartMessageWinsOverAReplayedName() {
        var selector = openSelector()
        selector.noteEarly("buy")
        XCTAssertEqual(selector.load([event("b", "buy"), sessionStart("s")], visibleId: nil)?.id, "s")
        XCTAssertTrue(selector.earlyNames.isEmpty)
        XCTAssertEqual(selector.track("buy", isVisible: false)?.id, "b")
    }

    func test_trackBeforeLoadNotesTheNameEarly() {
        var selector = openSelector()
        XCTAssertNil(selector.track("buy", isVisible: false))
        XCTAssertNil(selector.track("buy", isVisible: true))
        XCTAssertEqual(selector.earlyNames, ["buy"])
        XCTAssertEqual(selector.load([event("b", "buy")], visibleId: nil)?.id, "b")
    }

    func test_aRepeatedEarlyNameIsKeptOnce() {
        var selector = openSelector()
        selector.noteEarly("buy")
        selector.noteEarly("view")
        selector.noteEarly("buy")
        XCTAssertEqual(selector.earlyNames, ["buy", "view"])
    }

    func test_thirtyThreeDistinctNamesKeepTheFirst32() {
        var selector = openSelector()
        for index in 0..<33 { selector.noteEarly("n\(index)") }
        XCTAssertEqual(selector.earlyNames.count, 32)
        XCTAssertEqual(selector.earlyNames.first, "n0")
        XCTAssertEqual(selector.earlyNames.last, "n31")
        XCTAssertFalse(selector.earlyNames.contains("n32"))
        XCTAssertNil(selector.load([event("late", "n32")], visibleId: nil))
    }

    // MARK: - Session lifecycle

    func test_startSessionClearsHeldAndShownAndKeepsTheEarlyNames() {
        var selector = openSelector()
        XCTAssertEqual(selector.load([sessionStart("s"), event("e1", "x")], visibleId: nil)?.id, "s")
        selector.noteEarly("buy")
        selector.startSession(visibleId: nil)
        XCTAssertTrue(selector.held.isEmpty)
        XCTAssertTrue(selector.shown.isEmpty)
        XCTAssertFalse(selector.fetchDone)
        XCTAssertEqual(selector.earlyNames, ["buy"])
        XCTAssertNil(selector.track("x", isVisible: false))
        XCTAssertEqual(selector.load([event("b", "buy"), sessionStart("s")], visibleId: nil)?.id, "s")
        XCTAssertEqual(selector.track("buy", isVisible: false)?.id, "b")
    }

    func test_startSessionAddsTheVisibleIdToShown() {
        var selector = NottiInAppSelector()
        selector.startSession(visibleId: "v")
        XCTAssertEqual(selector.shown, ["v"])
        XCTAssertNil(selector.load([sessionStart("v")], visibleId: nil))
        XCTAssertNil(selector.load([event("v", "x")], visibleId: nil))
        XCTAssertNil(selector.track("x", isVisible: false))
    }

    func test_endSessionWasOpenClearsTheEarlyNamesAndHeld() {
        var selector = openSelector()
        _ = selector.load([event("e1", "x")], visibleId: nil)
        selector.noteEarly("buy")
        selector.endSession(wasOpen: true)
        XCTAssertTrue(selector.earlyNames.isEmpty)
        XCTAssertTrue(selector.held.isEmpty)
        XCTAssertFalse(selector.fetchDone)
    }

    func test_endSessionWithNoSessionOpenKeepsTheEarlyNames() {
        var selector = NottiInAppSelector()
        selector.noteEarly("buy")
        selector.endSession(wasOpen: false)
        XCTAssertEqual(selector.earlyNames, ["buy"])
        selector.startSession(visibleId: nil)
        XCTAssertEqual(selector.load([event("b", "buy")], visibleId: nil)?.id, "b")
    }

    func test_resetClearsEverything() {
        var selector = openSelector()
        _ = selector.load([sessionStart("s"), event("e1", "x")], visibleId: nil)
        selector.startSession(visibleId: "v")
        selector.noteEarly("buy")
        selector.reset()
        XCTAssertTrue(selector.held.isEmpty)
        XCTAssertTrue(selector.shown.isEmpty)
        XCTAssertTrue(selector.earlyNames.isEmpty)
        XCTAssertFalse(selector.fetchDone)
    }

    // MARK: - Visible across sessions (IAM-12)

    func test_loadWithAVisibleIdSkipsThatIdAndReturnsNoSessionStartMessage() {
        var selector = openSelector()
        selector.noteEarly("x")
        let messages = [sessionStart("s"), event("v", "x"), event("e1", "x")]
        XCTAssertNil(selector.load(messages, visibleId: "v"))
        XCTAssertTrue(selector.shown.contains("v"))
        XCTAssertFalse(selector.shown.contains("s"))
        XCTAssertTrue(selector.earlyNames.isEmpty)
        // Event candidates are held as usual; the visible id is never picked.
        XCTAssertEqual(selector.track("x", isVisible: false)?.id, "e1")
        XCTAssertNil(selector.track("x", isVisible: false))
        XCTAssertNil(selector.track("session_start", isVisible: false))
    }
}

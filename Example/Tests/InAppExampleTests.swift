import XCTest
@testable import NottiExample

/// Wiring of the In-App calls (IAM-47): the "Track event" button reaches `trackEvent`, and the click listener is
/// added at Initialize and logs the action type only. The SDK's own In-App behavior is tested in `NottiSDKTests`.
@MainActor
final class InAppExampleTests: XCTestCase {
    private func model(configured: Bool = true) -> (ExampleModel, SpySDKClient) {
        let spy = SpySDKClient()
        let config = configured
            ? ExampleConfig(appId: "app-synthetic", clientKey: "key-synthetic", host: "h.example.invalid")
            : ExampleConfig(appId: "fixture", clientKey: "fixture", host: "")
        return (ExampleModel(config: config, sdk: spy), spy)
    }

    func test_trackEventSendsTheExampleEventName() {
        let (model, spy) = model()
        model.trackEvent()

        XCTAssertEqual(spy.calls, ["trackEvent"])
        XCTAssertEqual(spy.lastArgs["event"], "example_event")
        XCTAssertEqual(model.log.rows, ["trackEvent: ok"])
    }

    func test_initializeAddsTheClickListenerOnceBeforeTheSdkStarts() {
        let (model, spy) = model()
        XCTAssertEqual(spy.inAppListenerAdds, 0)
        XCTAssertNil(spy.inAppClickHandler)

        model.initialize()
        XCTAssertEqual(spy.inAppListenerAdds, 1)
        XCTAssertNotNil(spy.inAppClickHandler)

        model.initialize()
        XCTAssertEqual(spy.inAppListenerAdds, 1)
        XCTAssertEqual(spy.calls, ["initialize", "initialize"])
    }

    func test_clickLogsTheActionTypeOnly() {
        let (model, spy) = model()
        model.initialize()
        spy.inAppClickHandler?(.url)
        spy.inAppClickHandler?(.deeplink)
        spy.inAppClickHandler?(.noAction)

        XCTAssertEqual(Array(model.log.rows.suffix(3)), [
            "in-app click: action url",
            "in-app click: action deeplink",
            "in-app click: action none"
        ])
    }

    func test_unconfiguredNeitherTracksNorAddsTheListener() {
        let (model, spy) = model(configured: false)
        model.trackEvent()
        model.initialize()

        XCTAssertEqual(spy.calls, [])
        XCTAssertEqual(spy.inAppListenerAdds, 0)
        XCTAssertTrue(model.log.rows.allSatisfy { $0 == LogEvent.notConfigured.text })
    }

    func test_clickRowsCarryNoFreeText() {
        // The row is built from the action type alone: there is no case that could carry a link value or an id.
        XCTAssertEqual(InAppActionKind.allCases.map { LogEvent.inAppClick(action: $0).text }, [
            "in-app click: action url",
            "in-app click: action deeplink",
            "in-app click: action none"
        ])
    }
}

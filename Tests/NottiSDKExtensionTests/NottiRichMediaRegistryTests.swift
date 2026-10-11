import UserNotifications
import XCTest
@testable import NottiSDKExtension

/// The registry that correlates an expiry call with its job (NSE-11, D10).
final class NottiRichMediaRegistryTests: NottiRichMediaJobTestCase {
    private func makeJob(userInfo: [AnyHashable: Any]) -> NottiRichMediaJob {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        return NottiRichMediaJob(
            content: content, gate: NottiHandlerGate { _ in }, environment: makeEnvironment()
        )
    }

    func test_returnsOnlyTheJobWhoseUserInfoEquals() {
        let registry = NottiRichMediaRegistry()
        let first = makeJob(userInfo: ["k": "one"])
        let second = makeJob(userInfo: ["k": "two"])
        registry.add(first); registry.add(second)

        let found = registry.jobs(matching: ["k": "two"])

        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first === second)
    }

    func test_returnsNothingWhenNoUserInfoEquals() {
        let registry = NottiRichMediaRegistry()
        registry.add(makeJob(userInfo: ["k": "one"]))

        XCTAssertTrue(registry.jobs(matching: ["k": "other"]).isEmpty)
    }

    func test_keepsAtMostSixteenJobsAndDropsTheOldest() {
        let registry = NottiRichMediaRegistry()
        let jobs = (0..<20).map { makeJob(userInfo: ["n": $0]) }
        jobs.forEach(registry.add)

        XCTAssertTrue(registry.jobs(matching: ["n": 3]).isEmpty)
        XCTAssertEqual(registry.jobs(matching: ["n": 4]).count, 1)
        XCTAssertEqual(registry.jobs(matching: ["n": 19]).count, 1)
    }

    func test_stillReturnsAFinishedJob() {
        StubURLProtocol.register(.body(MediaSamples.png, mimeType: "image/png"), for: mediaURL)
        let registry = NottiRichMediaRegistry()
        let (job, recorder) = startJob()
        registry.add(job)
        waitForHandler(recorder)

        XCTAssertEqual(registry.jobs(matching: makeOriginalContent().userInfo).count, 1)
    }

    func test_matchesBySharedDeliveryIdWhenAnotherKeyDiffers() {
        let registry = NottiRichMediaRegistry()
        let job = makeJob(userInfo: ["delivery_id": "fixture-1", "extra": "original"])
        registry.add(job)

        let found = registry.jobs(matching: ["delivery_id": "fixture-1", "extra": "mutated by the host"])

        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first === job)
    }

    func test_differentDeliveryIdsNeverMatchEvenWhenEverythingElseIsEqual() {
        let registry = NottiRichMediaRegistry()
        registry.add(makeJob(userInfo: ["delivery_id": "fixture-1", "extra": "same"]))

        XCTAssertTrue(registry.jobs(matching: ["delivery_id": "fixture-2", "extra": "same"]).isEmpty)
    }

    func test_anEmptyDeliveryIdFallsBackToUserInfoEquality() {
        let registry = NottiRichMediaRegistry()
        registry.add(makeJob(userInfo: ["delivery_id": "", "extra": "original"]))

        XCTAssertTrue(registry.jobs(matching: ["delivery_id": "", "extra": "changed"]).isEmpty)
        XCTAssertEqual(registry.jobs(matching: ["delivery_id": "", "extra": "original"]).count, 1)
    }

    func test_aDeliveryIdOnOnlyOneSideFallsBackToUserInfoEquality() {
        let registry = NottiRichMediaRegistry()
        registry.add(makeJob(userInfo: ["delivery_id": "fixture-1", "extra": "same"]))

        XCTAssertTrue(registry.jobs(matching: ["extra": "same"]).isEmpty)
    }
}

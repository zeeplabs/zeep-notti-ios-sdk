import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiFacadeLogLevelTests: XCTestCase {

    private var facade: NottiFacade!
    private var runtime: NottiRuntime!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var savedLevel: NottiLogLevel = .error
    private let logs = LogSink()

    override func setUp() {
        super.setUp()
        suiteName = "NottiFacadeLogLevelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            startObservers: false
        )
        facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
        // Captured before any assignment, so the initial effective level is intact.
        savedLevel = NottiLogger.level
        NottiLogger.sink = { [logs] level, message in logs.append("\(level):\(message)") }
    }

    override func tearDown() {
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        runtime = nil
        facade = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let allLevels: [(NottiLogLevelObjC, NottiLogLevel)] = [
        (.none, .none), (.error, .error), (.warn, .warn), (.info, .info), (.debug, .debug), (.verbose, .verbose)
    ]

    /// API-14 AC 2 / CORE-13 (lesson L-010): read through the facade without
    /// setting anything first, not the `defaultLevel` constant.
    func test_theLevelSeenThroughTheFacadeBeforeAnySetIsError() {
        XCTAssertEqual(savedLevel, .error)
        XCTAssertEqual(facade.logLevel, .error)
    }

    func test_everyLevelRoundTripsAndLandsOnTheLogger() {
        for (publicLevel, coreLevel) in allLevels {
            facade.logLevel = publicLevel

            XCTAssertEqual(NottiLogger.level, coreLevel, "\(publicLevel)")
            XCTAssertEqual(facade.logLevel, publicLevel, "\(publicLevel)")
        }
    }

    func test_theMappingCoversEverySourceCaseWithDistinctRawValues() {
        XCTAssertEqual(allLevels.count, 6)
        XCTAssertEqual(Set(allLevels.map { $0.0.rawValue }).count, 6)
        for (publicLevel, coreLevel) in allLevels {
            XCTAssertEqual(NottiLogLevelObjC(coreLevel), publicLevel)
            XCTAssertEqual(publicLevel.coreLevel, coreLevel)
            XCTAssertEqual(publicLevel.rawValue, coreLevel.rawValue, "ObjC raw values match the core's order")
        }
    }

    func test_aMessageAboveTheSetLevelIsNotEmittedAndOneAtOrBelowIs() {
        facade.logLevel = .warn

        NottiLogger.log(.error, "error-line")
        NottiLogger.log(.warn, "warn-line")
        NottiLogger.log(.info, "info-line")
        NottiLogger.log(.verbose, "verbose-line")

        XCTAssertEqual(logs.messages, ["error:error-line", "warn:warn-line"])
    }

    func test_noneSilencesEverythingAndVerboseEmitsEverything() {
        facade.logLevel = .none
        NottiLogger.log(.error, "silenced")
        XCTAssertEqual(logs.messages, [])

        facade.logLevel = .verbose
        NottiLogger.log(.verbose, "chatty")
        XCTAssertEqual(logs.messages, ["verbose:chatty"])
    }
}

import ObjectiveC
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// Every test builds its own fake classes (unique names) and its own swizzler registry.
/// Nothing here touches `UIApplication` or `UNUserNotificationCenter`.
final class NottiMethodSwizzlerTests: XCTestCase {

    private typealias OriginalFunction = @convention(c) (AnyObject, Selector, Int) -> Int
    private static let encoding = "q@:q"
    private let selector = NSSelectorFromString("fixtureCall:")

    private var swizzler: NottiMethodSwizzler!
    private var calls: [String] = []
    private var logs: [(NottiLogLevel, String)] = []
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        swizzler = NottiMethodSwizzler()
        calls = []
        logs = []
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        NottiLogger.sink = { [weak self] level, message in self?.logs.append((level, message)) }
    }

    override func tearDown() {
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeClass(superclass: AnyClass = NSObject.self, implementing: Bool, tag: String) -> AnyClass {
        let name = "NottiFixture\(tag)\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let cls = objc_allocateClassPair(superclass, name, 0) else {
            XCTFail("could not allocate fixture class")
            return NSObject.self
        }
        if implementing {
            let block: @convention(block) (AnyObject, Int) -> Int = { [weak self] _, value in
                self?.calls.append("original:\(tag)")
                return value + 1
            }
            class_addMethod(cls, selector, imp_implementationWithBlock(block), Self.encoding)
        }
        objc_registerClassPair(cls)
        return cls
    }

    private func makeInstance(_ cls: AnyClass) -> AnyObject {
        (cls as? NSObject.Type)?.init() ?? NSObject()
    }

    private func responds(_ cls: AnyClass) -> Bool {
        class_getInstanceMethod(cls, selector) != nil
    }

    private func call(_ object: AnyObject, _ value: Int = 10) -> Int {
        let imp = object.method(for: selector)
        let function = unsafeBitCast(imp, to: OriginalFunction.self)
        return function(object, selector, value)
    }

    /// Swizzles with a block that records `label`, then chains to the previous IMP when present.
    @discardableResult
    private func swizzle(
        _ cls: AnyClass,
        label: String,
        using target: NottiMethodSwizzler? = nil,
        previousSeen: ((Bool) -> Void)? = nil
    ) -> Bool {
        (target ?? swizzler).swizzle(cls, selector, typeEncoding: Self.encoding) { [weak self] previous in
            previousSeen?(previous != nil)
            let block: @convention(block) (AnyObject, Int) -> Int = { object, value in
                self?.calls.append(label)
                guard let previous else { return -1 }
                return unsafeBitCast(previous, to: OriginalFunction.self)(object, NSSelectorFromString("fixtureCall:"), value)
            }
            return block
        }
    }

    // MARK: - Tests

    func test_implementedMethodRunsTheReplacementThenTheOriginalOnce() {
        let cls = makeClass(implementing: true, tag: "Impl")

        XCTAssertTrue(swizzle(cls, label: "sdk"))
        let result = call(makeInstance(cls))

        XCTAssertEqual(result, 11)
        XCTAssertEqual(calls, ["sdk", "original:Impl"])
    }

    func test_inheritedMethodSwizzlesTheSuperclassOnceAndASubclassCallIsObservedOnce() {
        let base = makeClass(implementing: true, tag: "Base")
        let child = makeClass(superclass: base, implementing: false, tag: "Child")

        XCTAssertTrue(swizzle(child, label: "sdk"))

        XCTAssertEqual(call(makeInstance(child)), 11)
        XCTAssertEqual(calls, ["sdk", "original:Base"])
        // The implementing class was the one swizzled: its own instances are observed too.
        calls = []
        XCTAssertEqual(call(makeInstance(base)), 11)
        XCTAssertEqual(calls, ["sdk", "original:Base"])
        XCTAssertTrue(swizzler.isSwizzled(base, selector))
    }

    func test_absentMethodGetsTheSdkImplementationWithANilPreviousImp() {
        let cls = makeClass(implementing: false, tag: "Absent")
        var previousWasPresent: Bool?

        XCTAssertFalse(responds(cls))
        XCTAssertTrue(swizzle(cls, label: "sdk", previousSeen: { previousWasPresent = $0 }))

        XCTAssertEqual(previousWasPresent, false)
        XCTAssertTrue(responds(cls))
        XCTAssertEqual(call(makeInstance(cls)), -1)
        XCTAssertEqual(calls, ["sdk"])
    }

    func test_installingTheSameClassAndSelectorTwiceIsANoOp() {
        let cls = makeClass(implementing: true, tag: "Twice")
        var factoryRuns = 0

        XCTAssertTrue(swizzle(cls, label: "sdk", previousSeen: { _ in factoryRuns += 1 }))
        XCTAssertTrue(swizzle(cls, label: "sdk", previousSeen: { _ in factoryRuns += 1 }))

        XCTAssertEqual(factoryRuns, 1)
        XCTAssertEqual(call(makeInstance(cls)), 11)
        XCTAssertEqual(calls, ["sdk", "original:Twice"])
    }

    func test_aSecondSwizzlerStackedOnTopCallsEveryOriginalOnce() {
        let cls = makeClass(implementing: true, tag: "Stack")
        let other = NottiMethodSwizzler()

        XCTAssertTrue(swizzle(cls, label: "sdk"))
        XCTAssertTrue(swizzle(cls, label: "other", using: other))

        XCTAssertEqual(call(makeInstance(cls)), 11)
        XCTAssertEqual(calls, ["other", "sdk", "original:Stack"])
    }

    func test_swizzlingASubclassOfASwizzledClassDoesNotAddASecondObservation() {
        let base = makeClass(implementing: true, tag: "Parent")
        let child = makeClass(superclass: base, implementing: false, tag: "Kid")

        XCTAssertTrue(swizzle(base, label: "sdk"))
        XCTAssertTrue(swizzle(child, label: "sdk"))

        XCTAssertEqual(call(makeInstance(child)), 11)
        XCTAssertEqual(calls, ["sdk", "original:Parent"])
    }

    func test_anAddedMethodIsReusedByASubclassSwizzledLater() {
        let base = makeClass(implementing: false, tag: "AddedBase")
        let child = makeClass(superclass: base, implementing: false, tag: "AddedChild")

        XCTAssertTrue(swizzle(base, label: "sdk"))
        XCTAssertTrue(swizzle(child, label: "sdk"))

        _ = call(makeInstance(child))
        XCTAssertEqual(calls, ["sdk"])
    }

    func test_unrelatedClassesAreSwizzledIndependently() {
        let first = makeClass(implementing: true, tag: "SiblingA")
        let second = makeClass(implementing: true, tag: "SiblingB")

        XCTAssertTrue(swizzle(first, label: "sdk-a"))
        XCTAssertTrue(swizzle(second, label: "sdk-b"))

        _ = call(makeInstance(second))
        XCTAssertEqual(calls, ["sdk-b", "original:SiblingB"])
    }

    func test_failureReturnsFalseAndLogsOneErrorWithoutValuesAndLeavesTheClassUnchanged() {
        let cls = makeClass(implementing: false, tag: "Fail")

        // An absent method with no type encoding cannot be added.
        let result = swizzler.swizzle(cls, selector, typeEncoding: "") { _ in
            let block: @convention(block) (AnyObject, Int) -> Int = { _, _ in 0 }
            return block
        }

        XCTAssertFalse(result)
        XCTAssertFalse(responds(cls))
        XCTAssertFalse(swizzler.isSwizzled(cls, selector))
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.0, .error)
        XCTAssertFalse(logs.first?.1.contains("Fail") ?? true, "log must not carry class-specific values")
    }
}

import Foundation
import ObjectiveC
#if canImport(NottiShared)
import NottiShared
#endif

/// Replaces one instance method and chains to the previous implementation, at most once per
/// (implementing class, selector) (DEL-07).
///
/// How it works:
/// - The class that implements the selector is found by walking from the given class up the
///   superclass chain and checking each class's *own* method list (`class_copyMethodList`).
///   `class_getInstanceMethod` is not used because it hides inheritance. The implementing
///   class is the one swizzled, so a subclass that merely inherits the method is observed once.
/// - When no class in the chain implements the selector, the SDK's implementation is added on
///   the given class and the previous implementation passed to `makeBlock` is `nil`.
/// - The replacement uses `class_replaceMethod` with `imp_implementationWithBlock`. The previous
///   IMP is handed to `makeBlock` so the block can call through to it. Another swizzler stacked
///   later captures this block as its "previous", so every original still runs once.
///
/// The registry lives on the instance: tests build their own and never touch process-global state.
/// Production uses a single instance owned by the installer.
///
/// Known limit: a subclass that overrides the method and calls `super` is a second implementing
/// class. If both are swizzled, the SDK observes the callback on both layers.
@available(iOSApplicationExtension, unavailable)
final class NottiMethodSwizzler {

    private struct Key: Hashable {
        let cls: ObjectIdentifier
        let selector: Selector
    }

    private let lock = NSLock()
    private var installed: Set<Key> = []

    init() {}

    /// Whether `selector` was already swizzled on `cls` or on the class that implements it.
    func isSwizzled(_ cls: AnyClass, _ selector: Selector) -> Bool {
        lock.withLock {
            let target: AnyClass = Self.implementingClass(of: selector, startingAt: cls) ?? cls
            return installed.contains(Key(cls: ObjectIdentifier(target), selector: selector))
        }
    }

    /// Swizzles `selector` for `cls` (see the type doc).
    ///
    /// - Parameters:
    ///   - typeEncoding: ObjC type encoding of the method. Used only when no class in the chain
    ///     implements the selector; an existing method keeps its own encoding.
    ///   - makeBlock: receives the previous IMP (`nil` when the method was absent) and returns the
    ///     replacement, which must be an `@convention(block)` closure matching the method signature.
    ///     Not called when the install is a no-op.
    /// - Returns: `true` when the selector is swizzled after the call (including a repeat install),
    ///   `false` when it could not be installed. A failure logs one `.error` line with no values and
    ///   leaves the class unchanged.
    @discardableResult
    func swizzle(
        _ cls: AnyClass,
        _ selector: Selector,
        typeEncoding: String,
        makeBlock: (IMP?) -> Any
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let owner: AnyClass? = Self.implementingClass(of: selector, startingAt: cls)
        let target: AnyClass = owner ?? cls
        let key = Key(cls: ObjectIdentifier(target), selector: selector)
        if installed.contains(key) { return true }

        let previous: IMP?
        let encoding: String
        if let owner, let method = Self.ownMethod(of: owner, selector) {
            previous = method_getImplementation(method)
            encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? typeEncoding
        } else {
            previous = nil
            encoding = typeEncoding
        }
        guard !encoding.isEmpty else {
            Self.logFailure(selector)
            return false
        }

        let imp = imp_implementationWithBlock(makeBlock(previous))
        _ = class_replaceMethod(target, selector, imp, encoding)

        // Verify the class now owns our implementation, otherwise leave nothing behind.
        guard let method = Self.ownMethod(of: target, selector), method_getImplementation(method) == imp else {
            imp_removeBlock(imp)
            Self.logFailure(selector)
            return false
        }
        installed.insert(key)
        return true
    }

    // MARK: - Runtime lookups

    /// The first class from `cls` up the superclass chain whose own method list has `selector`.
    private static func implementingClass(of selector: Selector, startingAt cls: AnyClass) -> AnyClass? {
        var current: AnyClass? = cls
        while let candidate = current {
            if ownMethod(of: candidate, selector) != nil { return candidate }
            current = class_getSuperclass(candidate)
        }
        return nil
    }

    private static func ownMethod(of cls: AnyClass, _ selector: Selector) -> Method? {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else { return nil }
        defer { free(list) }
        for index in 0..<Int(count) where method_getName(list[index]) == selector {
            return list[index]
        }
        return nil
    }

    private static func logFailure(_ selector: Selector) {
        NottiLogger.log(.error, "Notti: could not install delegate hook for \(NSStringFromSelector(selector))", category: "delegates")
    }
}

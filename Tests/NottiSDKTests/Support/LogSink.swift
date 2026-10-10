// Ported from react-native-notti 52e4b55 ios/Tests/NottiCoreTests.swift (AD-002).
// Changes: moved out of the RN test file unchanged; `@testable import NottiSDK`.

import Foundation
@testable import NottiSDK

/// Thread-safe log capture, mirroring `NottiCoreTest.kt`'s plain
/// `mutableListOf<String>()` (safe there because Kotlin's test only touches
/// it from callbacks that are themselves synchronized) — this SDK's
/// serialization test drives `NottiCore` from two real threads, so the
/// Swift equivalent needs its own lock.
final class LogSink {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(message)
    }

    var messages: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

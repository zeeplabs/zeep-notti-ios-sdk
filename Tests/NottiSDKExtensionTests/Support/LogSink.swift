// Adapted from Tests/NottiSDKTests/Support/LogSink.swift for the extension tests (test support).

import Foundation
@testable import NottiShared

/// Thread-safe capture of `NottiLogger` lines. `install()` points the logger sink here and
/// `uninstall()` restores the previous sink and level. Call both from `setUp` and `tearDown`.
final class LogSink {
    private let lock = NSLock()
    private var storage: [(level: NottiLogLevel, message: String)] = []
    private var savedLevel: NottiLogLevel = .error
    private var savedSink: ((NottiLogLevel, String) -> Void)?

    func append(_ level: NottiLogLevel, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append((level, message))
    }

    var lines: [(level: NottiLogLevel, message: String)] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var messages: [String] { lines.map(\.message) }

    func install(level: NottiLogLevel = .verbose) {
        savedLevel = NottiLogger.level
        savedSink = NottiLogger.sink
        NottiLogger.level = level
        NottiLogger.sink = { [weak self] level, message in self?.append(level, message) }
    }

    func uninstall() {
        NottiLogger.sink = savedSink
        NottiLogger.level = savedLevel
    }
}

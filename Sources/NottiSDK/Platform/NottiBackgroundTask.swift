// Ported from react-native-notti 52e4b55 ios/NottiImpl.swift:274-302 (`NottiImpl.beginBackgroundTask()`) (AD-002).
// Changes: `private static func beginBackgroundTask()` on `NottiImpl` -> internal `NottiBackgroundTask.begin()`;
// marked unavailable in app extensions (uses `UIApplication.shared`). Body unchanged.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if os(macOS)

    /// macOS (AD-025, design D6): there is no suspension to survive, only sudden and automatic termination, so
    /// the wrapper is a `ProcessInfo` activity that disables both while the session-end PATCH runs.
    /// `performExpiringActivity` is unavailable on macOS. There is no expiry handler: the returned closure is
    /// idempotent and is called when the queued work finishes (`handleAppDidEnterBackground`'s `defer`).
    @available(iOSApplicationExtension, unavailable)
    @available(macOSApplicationExtension, unavailable)
    enum NottiBackgroundTask {

        static func begin() -> () -> Void {
            begin(processInfo: .processInfo)
        }

        /// `processInfo` is injectable only so a test can observe begin and end.
        static func begin(processInfo: ProcessInfo) -> () -> Void {
            final class ActivityBox {
                let lock = NSLock()
                var token: NSObjectProtocol?
                var ended = false
                let processInfo: ProcessInfo
                init(processInfo: ProcessInfo) { self.processInfo = processInfo }
                func end() {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !ended else { return }
                    ended = true
                    if let token {
                        processInfo.endActivity(token)
                        self.token = nil
                    }
                }
            }
            let box = ActivityBox(processInfo: processInfo)
            box.lock.lock()
            box.token = processInfo.beginActivity(
                options: [.suddenTerminationDisabled, .automaticTerminationDisabled],
                reason: "app.notti.session-end"
            )
            box.lock.unlock()
            return { box.end() }
        }
    }

#else

@available(iOSApplicationExtension, unavailable)
enum NottiBackgroundTask {

    /// Begins a UIKit background task and returns an idempotent closure that
    /// ends it; the expiration handler ends it too, so the OS never kills the
    /// app for overrunning the task.
    static func begin() -> () -> Void {
        final class TaskBox {
            let lock = NSLock()
            var id: UIBackgroundTaskIdentifier = .invalid
            var ended = false
            func end() {
                lock.lock()
                defer { lock.unlock() }
                guard !ended else { return }
                ended = true
                if id != .invalid {
                    UIApplication.shared.endBackgroundTask(id)
                }
            }
        }
        let box = TaskBox()
        let id = UIApplication.shared.beginBackgroundTask(withName: "app.notti.session-end") { box.end() }
        box.lock.lock()
        box.id = id
        let alreadyEnded = box.ended
        box.lock.unlock()
        if alreadyEnded && id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
        return { box.end() }
    }
}

#endif

// Ported from react-native-notti 52e4b55 ios/NottiImpl.swift:274-302 (`NottiImpl.beginBackgroundTask()`) (AD-002).
// Changes: `private static func beginBackgroundTask()` on `NottiImpl` -> internal `NottiBackgroundTask.begin()`;
// marked unavailable in app extensions (uses `UIApplication.shared`). Body unchanged.

import Foundation
import UIKit

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

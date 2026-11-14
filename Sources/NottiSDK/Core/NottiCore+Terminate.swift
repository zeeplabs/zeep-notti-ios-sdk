// AD-025 (macos-support): session end when the user quits while the app is still active.
//
// On macOS an app that is quit while active gets no resign-active first (`NottiLifecycle.didEnterBackground`),
// so without this hook the open session would never be reported. The wait is bounded and never loops; the
// local session bookkeeping is persisted before the PATCH (`handleSessionEndOnQueue`), so a timeout loses at
// most the network report and the stored counters are sent with the next session.

import Foundation

#if os(macOS)

    extension NottiCore {

        /// D7, UNCONFIRMED decision: how long the quit may be delayed for the session-end report. Main is
        /// blocked for at most this long, and only when a session is open and a PATCH is pending. One line.
        static let terminateFlushTimeout: TimeInterval = 1.5

        /// Registers the quit hook; removed with the other lifecycle observers (`invalidate`, `deinit`).
        func observeAppTerminate() {
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NottiLifecycle.willTerminate,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self = self else { return }
                self.handleAppWillTerminate(atMs: self.nowMs())
            }
        }

        /// Ends the session as a resign-active would, then waits at most `flushTimeout` for the queued
        /// bookkeeping and PATCH. A second end (resign active, then terminate) is a no-op: no session start
        /// is stored anymore. `flushTimeout` is injectable so a test never waits the real constant.
        func handleAppWillTerminate(atMs: Int64, flushTimeout: TimeInterval = NottiCore.terminateFlushTimeout) {
            handleAppDidEnterBackground(atMs: atMs)
            waitForPendingWork(timeout: flushTimeout)
        }
    }

#else

    extension NottiCore {
        /// iOS never observes a quit (the OS suspends the app; `didEnterBackground` already ended the session).
        func observeAppTerminate() {}
    }

#endif

// macOS only (AD-025). The existing lifecycle tests post `UIApplication.didBecomeActiveNotification`,
// `didEnterBackgroundNotification` and `didFinishLaunchingNotification` to drive the core, the runtime and the
// installer. On macOS this shim gives those spellings the AppKit names `NottiLifecycle` maps them to, so every one
// of those tests runs on both platforms with no edited assertion. `NottiLifecycleTests` pins the seam to the real
// constants of each platform, so a wrong shim value fails there too.
#if !canImport(UIKit)
import AppKit

enum UIApplication {
    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    /// On macOS the "left the screen" event is resign active (unconfirmed decision C1).
    static let didEnterBackgroundNotification = NSApplication.didResignActiveNotification
    static let didFinishLaunchingNotification = NSApplication.didFinishLaunchingNotification
}
#endif

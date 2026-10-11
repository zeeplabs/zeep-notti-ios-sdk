import Foundation

/// Whether the SDK's delegate swizzling is installed and active (DEL-09).
///
/// Set by `NottiDelegateInstaller` after a successful install and read by the manual forwarding API, which
/// is ignored while this is true so an event is never processed twice. Thread-safe.
@available(iOSApplicationExtension, unavailable)
final class NottiSwizzlingState {

    /// The process-wide state, used by the production installer and the production facade.
    static let shared = NottiSwizzlingState()

    private let lock = NSLock()
    private var active = false

    init() {}

    var isActive: Bool {
        lock.withLock { active }
    }

    func setActive(_ value: Bool) {
        lock.withLock { active = value }
    }
}

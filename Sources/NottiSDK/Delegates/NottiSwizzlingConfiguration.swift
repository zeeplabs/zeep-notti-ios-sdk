import Foundation

/// Answers "is delegate swizzling on?" from the `NottiDisableSwizzling` Info.plist key (DEL-02).
///
/// Only a Boolean `true` turns swizzling off. A missing key or `false` leaves it on. Any
/// other type (string, number) is treated as on and sets `invalidValueWarning`, so the
/// installer can log one warning. The dictionary is injected: tests never read the real bundle.
@available(iOSApplicationExtension, unavailable)
struct NottiSwizzlingConfiguration {

    /// Info.plist key that disables swizzling. Part of the public integration contract.
    static let infoPlistKey = "NottiDisableSwizzling"

    let isEnabled: Bool
    let invalidValueWarning: Bool

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        guard let value = infoDictionary?[Self.infoPlistKey] else {
            isEnabled = true
            invalidValueWarning = false
            return
        }
        // `NSNumber` bridges to `Bool` for 0/1 too, so check the CoreFoundation type: only a real
        // Boolean counts. `<integer>1</integer>` is a number, not a Boolean.
        if let number = value as? NSNumber, CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            isEnabled = !number.boolValue
            invalidValueWarning = false
        } else {
            isEnabled = true
            invalidValueWarning = true
        }
    }
}

import Foundation

/// Access to this target's resource bundle. Wrapping `Bundle.module` avoids an
/// ambiguous `Bundle.module` in test targets that ship their own resources.
enum NottiSDKExtensionResources {
    static var bundle: Bundle { .module }
}

import Foundation

/// Access to this target's resources.
///
/// SPM generates `Bundle.module`; wrapping it also avoids an ambiguous
/// `Bundle.module` in test targets that ship their own resources. CocoaPods has
/// no `Bundle.module` and puts the resources in the `NottiSDK_Privacy` resource bundle.
enum NottiSDKResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        let host = Bundle(for: BundleToken.self)
        if let url = host.url(forResource: "NottiSDK_Privacy", withExtension: "bundle"),
           let resources = Bundle(url: url) {
            return resources
        }
        return host
        #endif
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif

import Foundation

/// The single source of truth for the SDK version (PKG-14) and identity.
///
/// `current` is sent to the backend as `sdk_version`. `scripts/check-version.sh`
/// fails CI when `NottiSDK.podspec` (or a release tag) disagrees with it.
package enum NottiSDKVersion {
    package static let current = "0.2.0"
    /// The wire platform of this build (AD-025): sent as `platform` on
    /// `POST /devices`. `ios` for the UIKit platforms, `macos` for a macOS build.
    /// Mac Catalyst builds the iOS path and reports `ios` (not supported).
    #if os(macOS)
        package static let platform = "macos"
    #else
        package static let platform = "ios"
    #endif
    /// Sent as `sdk_name` (AD-024). One of the backend's values (`zeep-notti`
    /// AD-044: `react-native`, `ios`, `android`, plus `macos` from AD-025); a
    /// wrapper overrides it. Equal to `platform`.
    package static let name = platform
}

import Foundation

/// The single source of truth for the SDK version (PKG-14) and identity.
///
/// `current` is sent to the backend as `sdk_version`. `scripts/check-version.sh`
/// fails CI when `NottiSDK.podspec` (or a release tag) disagrees with it.
package enum NottiSDKVersion {
    package static let current = "0.2.0"
    /// Sent as `sdk_name` (AD-024). One of the backend's values (`zeep-notti`
    /// AD-044: `react-native`, `ios`, `android`); a wrapper overrides it.
    package static let name = "ios"
}

import Foundation

/// The single source of truth for the SDK version (PKG-14).
///
/// Sent to the backend as `sdk_version`. `scripts/check-version.sh` fails CI when
/// `NottiSDK.podspec` (or a release tag) disagrees with this value.
package enum NottiSDKVersion {
    package static let current = "0.1.0"
}

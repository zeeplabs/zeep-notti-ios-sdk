// AD-025 (macos-support): the device OS and model reads, with no UIKit in the shared provider closure.
// The iOS bodies are the closures `NottiPlatformProviders.live()` had, moved here unchanged. The pure helpers
// (version formatting, the sysctl string read) compile and are tested on both platforms.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum NottiPlatformInfo {

    /// A `sysctlbyname`-shaped read, injectable so the failure paths are testable.
    typealias SysctlRead = (_ name: String, _ buffer: UnsafeMutableRawPointer?, _ size: UnsafeMutablePointer<Int>) -> Int32

    /// Whether this platform shows In-App Messages. The UIKit layer exists only where UIKit does; on macOS the
    /// In-App API compiles and is inert (design D8, UNCONFIRMED decision: the engine is never configured there).
    static var supportsInApp: Bool {
        #if canImport(UIKit)
            return true
        #else
            return false
        #endif
    }

    /// `"14.4"` or `"14.4.1"`: the patch is written only when it is not zero (the iOS `systemVersion` convention).
    static func osVersionString(major: Int, minor: Int, patch: Int) -> String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    /// The OS version sent as `device_os`.
    static func deviceOS() -> String? {
        #if canImport(UIKit)
            return UIDevice.current.systemVersion
        #else
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return osVersionString(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
        #endif
    }

    /// The hardware identifier sent as `device_model` (`iPhone15,2`, `Mac14,9`), or nil when unreadable. Never a
    /// serial number, hardware UUID, user name or host name.
    static func deviceModel() -> String? {
        #if canImport(UIKit)
            // Moved verbatim from `NottiPlatformProviders.live()` (`uname().machine`).
            var systemInfo = utsname()
            uname(&systemInfo)
            let mirror = Mirror(reflecting: systemInfo.machine)
            let bytes = mirror.children.map { $0.value as? Int8 ?? 0 }
            let model = String(bytes: bytes.map { UInt8(bitPattern: $0) }, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters)
            return model?.isEmpty == false ? model : nil
        #else
            // D10 (UNCONFIRMED): `uname().machine` is `arm64` on macOS, `hw.model` is the identifier (`Mac14,9`).
            return sysctlString("hw.model")
        #endif
    }

    /// Reads a string `sysctl`. Nil on any failure, an implausible size or an empty value.
    static func sysctlString(_ name: String, read: SysctlRead = defaultSysctlRead) -> String? {
        var size = 0
        guard read(name, nil, &size) == 0, size > 1, size <= 256 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard read(name, &buffer, &size) == 0 else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        let value = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
        return value?.isEmpty == false ? value : nil
    }

    static let defaultSysctlRead: SysctlRead = { name, buffer, size in
        sysctlbyname(name, buffer, size, nil, 0)
    }
}

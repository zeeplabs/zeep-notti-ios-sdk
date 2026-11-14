import XCTest
@testable import NottiSDK

/// AD-025: the pure parts of `NottiPlatformInfo` (version formatting, the sysctl string read) run on both
/// platforms. Nothing here reads a real serial number, hardware UUID or host name.
final class NottiPlatformInfoTests: XCTestCase {

    func test_osVersionString_dropsAZeroPatch() {
        XCTAssertEqual(NottiPlatformInfo.osVersionString(major: 14, minor: 0, patch: 0), "14.0")
        XCTAssertEqual(NottiPlatformInfo.osVersionString(major: 15, minor: 0, patch: 0), "15.0")
        XCTAssertEqual(NottiPlatformInfo.osVersionString(major: 14, minor: 4, patch: 0), "14.4")
    }

    func test_osVersionString_keepsANonZeroPatch() {
        XCTAssertEqual(NottiPlatformInfo.osVersionString(major: 14, minor: 4, patch: 1), "14.4.1")
        XCTAssertEqual(NottiPlatformInfo.osVersionString(major: 12, minor: 0, patch: 1), "12.0.1")
    }

    func test_deviceOS_isNonEmptyAndLooksLikeAVersion() throws {
        let value = try XCTUnwrap(NottiPlatformInfo.deviceOS())
        XCTAssertNotNil(value.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression), value)
    }

    func test_deviceModel_isNilOrANonEmptyPrintableIdentifier() {
        guard let value = NottiPlatformInfo.deviceModel() else { return }
        XCTAssertFalse(value.isEmpty)
        XCTAssertEqual(value, value.trimmingCharacters(in: .controlCharacters))
    }

    func test_supportsInApp_matchesThePlatform() {
        #if canImport(UIKit)
            XCTAssertTrue(NottiPlatformInfo.supportsInApp)
        #else
            XCTAssertFalse(NottiPlatformInfo.supportsInApp)
        #endif
    }

    // MARK: sysctlString

    private func reader(value: [CChar], sizeStatus: Int32 = 0, readStatus: Int32 = 0) -> NottiPlatformInfo.SysctlRead {
        { _, buffer, size in
            guard let buffer else {
                size.pointee = value.count
                return sizeStatus
            }
            let count = min(size.pointee, value.count)
            if count > 0 {
                value.withUnsafeBufferPointer { buffer.copyMemory(from: $0.baseAddress!, byteCount: count) }
            }
            return readStatus
        }
    }

    func test_sysctlString_readsAModelIdentifier() {
        let model = Array("Mac14,9".utf8CString)
        XCTAssertEqual(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: model)), "Mac14,9")
    }

    func test_sysctlString_isNilWhenTheSizeQueryFails() {
        let model = Array("Mac14,9".utf8CString)
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: model, sizeStatus: -1)))
    }

    func test_sysctlString_isNilWhenTheValueReadFails() {
        let model = Array("Mac14,9".utf8CString)
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: model, readStatus: -1)))
    }

    func test_sysctlString_isNilForAnEmptyValue() {
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: [0])))
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: [])))
    }

    func test_sysctlString_isNilForAnImplausibleSize() {
        let huge = [CChar](repeating: 65, count: 1_000)
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: huge)))
    }

    func test_sysctlString_isNilWhenOnlyControlCharacters() {
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model", read: reader(value: [0x01, 0x02, 0])))
    }
}

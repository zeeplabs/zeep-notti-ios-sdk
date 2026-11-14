#if os(macOS)
import XCTest
@testable import NottiSDKExtension

/// AD-025, MAC-04, MAC-19: the Notification Service Extension code links no AppKit or UIKit. `nm` and `otool` run
/// over the built Mach-O that holds `NottiNotificationServiceExtension` (the extension and `NottiShared` code are
/// linked into it; these tests import neither AppKit nor UIKit), so a stray `import AppKit` that is used, or a
/// framework autolinked for it, fails here as well as in `scripts/check-extension-safety.sh`.
final class NottiExtensionLinkTests: XCTestCase {

    private static let banned = ["AppKit", "UIKit", "NSApplication", "NSWorkspace", "UIApplication"]

    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func builtProduct() throws -> String {
        let url = try XCTUnwrap(Bundle(for: NottiNotificationServiceExtension.self).executableURL)
        return url.path
    }

    func test_theBuiltProductDependsOnNoAppKitOrUIKitFramework() throws {
        let product = try builtProduct()
        let libraries = try run("/usr/bin/otool", ["-L", product])

        XCTAssertTrue(libraries.contains("Foundation"), "otool produced a real listing")
        for name in Self.banned {
            XCTAssertFalse(libraries.contains(name), "\(name) is linked into the extension product")
        }
    }

    func test_theBuiltProductReferencesNoAppKitOrUIKitSymbol() throws {
        let product = try builtProduct()
        let symbols = try run("/usr/bin/nm", ["-u", product])

        XCTAssertTrue(symbols.contains("NSObject"), "nm produced a real listing")
        for name in Self.banned {
            XCTAssertFalse(symbols.contains(name), "an undefined \(name) symbol is referenced by the extension product")
        }
    }
}
#endif

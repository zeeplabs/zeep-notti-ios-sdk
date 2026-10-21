import XCTest

/// Proves facts about the built product, not about the SDK's logic (EXR-18, EXR-19). Runs hosted in the
/// example app, so `Bundle.main` is the app and `PlugIns/NotificationService.appex` is its extension.
///
/// SPM leg. Resource bundle names are `<package>_<target>.bundle` and are asserted as literals on purpose:
/// a rename would silently break `NottiSDKResources` lookups on a host that copies the bundle by name.
final class ProductIntegrationTests: XCTestCase {
    private let appBundleName = "NottiSDK_NottiSDK.bundle"
    private let extensionBundleName = "NottiSDK_NottiSDKExtension.bundle"

    private var appexURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("PlugIns/NotificationService.appex", isDirectory: true)
    }

    private func manifest(at bundleURL: URL) throws -> [String: Any] {
        let url = bundleURL.appendingPathComponent("PrivacyInfo.xcprivacy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent) in \(bundleURL.lastPathComponent)")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    // MARK: Launch hook (EXR-19)

    /// `+load` ran once and found `NottiDelegateInstaller`. Read through the Objective-C runtime so the same
    /// assertion works under SPM and CocoaPods without importing the bootstrap module.
    func test_launchHookRanOnceAndInstalledOnce() throws {
        let hook = try XCTUnwrap(NSClassFromString("NottiBootstrap") as? NSObject.Type, "NottiBootstrap is not linked into the app")
        XCTAssertEqual((hook.value(forKey: "loadCount") as? NSNumber)?.intValue, 1)
        XCTAssertEqual((hook.value(forKey: "installCount") as? NSNumber)?.intValue, 1)
    }

    func test_extensionBinaryDoesNotLinkTheLaunchHook() throws {
        let files = try FileManager.default.contentsOfDirectory(at: appexURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "dylib" || $0.lastPathComponent == "NotificationService" }
        XCTAssertFalse(files.isEmpty, "no extension binary found in \(appexURL.lastPathComponent)")
        let needles = ["NottiBootstrap", "NottiDelegateInstaller", "NottiRuntime"].map { Data($0.utf8) }
        for file in files {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            for needle in needles {
                XCTAssertNil(data.range(of: needle), "\(file.lastPathComponent) contains app-only symbol \(String(decoding: needle, as: UTF8.self))")
            }
        }
    }

    // MARK: Privacy bundles (EXR-18)

    func test_appProductHoldsTheSdkPrivacyBundle() throws {
        let bundleURL = Bundle.main.bundleURL.appendingPathComponent(appBundleName, isDirectory: true)
        let manifest = try manifest(at: bundleURL)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertTrue(types.contains("NSPrivacyCollectedDataTypeDeviceID"), "shipped manifest lacks DeviceID")
    }

    func test_extensionHoldsItsOwnPrivacyBundle() throws {
        let bundleURL = appexURL.appendingPathComponent(extensionBundleName, isDirectory: true)
        let manifest = try manifest(at: bundleURL)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertTrue(apis.isEmpty, "the extension must declare no required-reason API")
    }

    func test_theTwoProductsDoNotShareABundle() {
        let appHasExtensionBundle = FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL.appendingPathComponent(extensionBundleName).path)
        let appexHasAppBundle = FileManager.default.fileExists(
            atPath: appexURL.appendingPathComponent(appBundleName).path)
        XCTAssertFalse(appHasExtensionBundle, "the app must not carry the extension's bundle")
        XCTAssertFalse(appexHasAppBundle, "the extension must not carry the app's bundle")
    }
}

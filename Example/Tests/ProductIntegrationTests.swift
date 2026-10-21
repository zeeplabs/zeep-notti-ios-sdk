import XCTest

/// Proves facts about the built product, not about the SDK's logic (EXR-18, EXR-19). Runs hosted in the
/// example app, so `Bundle.main` is the app and `PlugIns/NotificationService.appex` is its extension.
/// The same file runs in every leg: SPM, and CocoaPods static frameworks, static libraries and dynamic
/// frameworks (`NOTTI_PODS` is set by `project-pods.yml`).
///
/// Resource bundle names are asserted as literals on purpose: `NottiSDKResources` looks them up by name,
/// so a rename would silently break the lookup on a host.
final class ProductIntegrationTests: XCTestCase {
    #if NOTTI_PODS
    private let appBundleName = "NottiSDK_Privacy.bundle"
    private let extensionBundleName = "NottiSDKExtension_Privacy.bundle"
    #else
    private let appBundleName = "NottiSDK_NottiSDK.bundle"
    private let extensionBundleName = "NottiSDK_NottiSDKExtension.bundle"
    #endif

    private var appexURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("PlugIns/NotificationService.appex", isDirectory: true)
    }

    /// CocoaPods dynamic frameworks embed `NottiSDKExtension.framework` once, in the app's `Frameworks/`; the
    /// extension reaches it through `@executable_path/../../Frameworks`. Nil when the extension code is linked
    /// into the appex (SPM, static frameworks, static libraries).
    private var extensionFrameworkInApp: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Frameworks/NottiSDKExtension.framework", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The app's files, without its extension and without the shared extension framework.
    private func appOwnFiles() -> [URL] {
        let shared = extensionFrameworkInApp?.path
        return files(under: Bundle.main.bundleURL, skippingPlugIns: true).filter { file in
            guard let shared else { return true }
            return !file.path.hasPrefix(shared + "/")
        }
    }

    /// Every file under `root`, skipping the app's own `PlugIns` when `skippingPlugIns` is set.
    private func files(under root: URL, skippingPlugIns: Bool = false) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if skippingPlugIns, url.lastPathComponent == "PlugIns", url.deletingLastPathComponent() == root {
                walker.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { found.append(url) }
        }
        return found
    }

    /// The resource bundle directory called `name` that contains one of `candidates`.
    private func bundle(named name: String, in candidates: [URL]) -> URL? {
        for file in candidates {
            var url = file.deletingLastPathComponent()
            while url.pathComponents.count > 3 {
                if url.lastPathComponent == name { return url }
                url = url.deletingLastPathComponent()
            }
        }
        return nil
    }

    private func manifest(in bundleURL: URL) throws -> [String: Any] {
        let url = bundleURL.appendingPathComponent("PrivacyInfo.xcprivacy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing PrivacyInfo.xcprivacy in \(bundleURL.lastPathComponent)")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        return [[0xCF, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA]].contains(Array(head))
    }

    // MARK: Launch hook (EXR-19)

    /// `+load` ran once and found `NottiDelegateInstaller`. Read through the Objective-C runtime so the same
    /// assertion works under SPM and CocoaPods without importing the bootstrap module.
    func test_launchHookRanOnceAndInstalledOnce() throws {
        let hook = try XCTUnwrap(NSClassFromString("NottiBootstrap") as? NSObject.Type, "NottiBootstrap is not linked into the app")
        XCTAssertEqual((hook.value(forKey: "loadCount") as? NSNumber)?.intValue, 1)
        XCTAssertEqual((hook.value(forKey: "installCount") as? NSNumber)?.intValue, 1)
    }

    /// No Mach-O file of the extension (its executable, its debug dylib, its frameworks, and the shared extension
    /// framework when CocoaPods embeds it in the app) carries an app-only symbol.
    func test_extensionBinariesDoNotLinkAppOnlyCode() throws {
        let shared = extensionFrameworkInApp.map { files(under: $0) } ?? []
        let binaries = (files(under: appexURL) + shared).filter(isMachO)
        XCTAssertFalse(binaries.isEmpty, "no Mach-O file found in \(appexURL.lastPathComponent)")
        let needles = ["NottiBootstrap", "NottiDelegateInstaller", "NottiRuntime"].map { Data($0.utf8) }
        for file in binaries {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            for needle in needles {
                XCTAssertNil(data.range(of: needle), "\(file.lastPathComponent) contains app-only symbol \(String(decoding: needle, as: UTF8.self))")
            }
        }
    }

    // MARK: Privacy bundles (EXR-18)

    func test_appProductHoldsTheSdkPrivacyBundle() throws {
        let bundleURL = try XCTUnwrap(
            bundle(named: appBundleName, in: appOwnFiles()),
            "\(appBundleName) not found in the app product")
        let manifest = try manifest(in: bundleURL)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertTrue(types.contains("NSPrivacyCollectedDataTypeDeviceID"), "shipped manifest lacks DeviceID")
    }

    func test_extensionHoldsItsOwnPrivacyBundle() throws {
        let extensionFiles = files(under: appexURL) + (extensionFrameworkInApp.map { files(under: $0) } ?? [])
        let bundleURL = try XCTUnwrap(
            bundle(named: extensionBundleName, in: extensionFiles),
            "\(extensionBundleName) not found in the extension or in its shared framework")
        let manifest = try manifest(in: bundleURL)
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertTrue(apis.isEmpty, "the extension must declare no required-reason API")
    }

    func test_theTwoProductsDoNotShareABundle() {
        XCTAssertNil(bundle(named: extensionBundleName, in: appOwnFiles()),
                     "the app's own code must not carry the extension's bundle")
        XCTAssertNil(bundle(named: appBundleName, in: files(under: appexURL)),
                     "the extension must not carry the app's bundle")
    }

    /// When the extension framework lives in the app, the extension binary must search the app's `Frameworks/`,
    /// or the extension fails to load on a device.
    func test_extensionCanReachASharedFrameworkInTheApp() throws {
        guard extensionFrameworkInApp != nil else { return }
        let rpath = Data("@executable_path/../../Frameworks".utf8)
        let binaries = files(under: appexURL).filter(isMachO)
        XCTAssertTrue(
            try binaries.contains { try Data(contentsOf: $0, options: .mappedIfSafe).range(of: rpath) != nil },
            "no extension binary carries the @executable_path/../../Frameworks rpath")
    }
}

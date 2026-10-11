// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NottiSDK",
    platforms: [.iOS(.v15)],
    products: [
        // App target product. Never link it into a Notification Service Extension.
        .library(name: "NottiSDK", targets: ["NottiSDK"]),
        // Notification Service Extension product. Must never depend on `NottiSDK`.
        .library(name: "NottiSDKExtension", targets: ["NottiSDKExtension"]),
    ],
    targets: [
        // Internal, extension-safe code shared by both products. Not a product.
        // Declarations use `package` access (AD-006).
        .target(name: "NottiShared"),
        // Objective-C launch hook (`+load` -> `NottiDelegateInstaller`). A dependency of `NottiSDK` only: the
        // extension product and `NottiShared` must never reach it (`scripts/check-package-graph.sh`).
        .target(name: "NottiSDKBootstrap"),
        .target(
            name: "NottiSDK",
            dependencies: ["NottiShared", "NottiSDKBootstrap"],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "NottiSDKExtension",
            dependencies: ["NottiShared"],
            resources: [.process("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(name: "NottiSharedTests", dependencies: ["NottiShared"]),
        .testTarget(
            name: "NottiSDKTests",
            dependencies: ["NottiSDK", "NottiShared", "NottiSDKBootstrap"],
            // RN 0.6.0 continuity fixture (core-port CORE-11).
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "NottiSDKExtensionTests", dependencies: ["NottiSDKExtension", "NottiShared"]),
        // Objective-C compile check (public-api API-13): fails if the `@objc` surface stops compiling.
        .testTarget(name: "NottiSDKObjCTests", dependencies: ["NottiSDK"]),
        // Objective-C compile check of the extension entry points (nse-rich-media NSE-16). Adds no product.
        .testTarget(name: "NottiSDKExtensionObjCTests", dependencies: ["NottiSDKExtension"]),
    ],
    swiftLanguageVersions: [.v5]
)

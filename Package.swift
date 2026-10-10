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
        .target(name: "NottiSDK", dependencies: ["NottiShared"]),
        .target(name: "NottiSDKExtension", dependencies: ["NottiShared"]),
        .testTarget(name: "NottiSharedTests", dependencies: ["NottiShared"]),
        .testTarget(name: "NottiSDKTests", dependencies: ["NottiSDK", "NottiShared"]),
        .testTarget(name: "NottiSDKExtensionTests", dependencies: ["NottiSDKExtension", "NottiShared"]),
    ],
    swiftLanguageVersions: [.v5]
)

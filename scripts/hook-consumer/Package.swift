// swift-tools-version:5.9
import PackageDescription

// Scratch consumer for `scripts/check-hook-linked.sh` (DEL-01): an executable that depends on the SDK package
// the way an app does, and mentions nothing about the ObjC launch hook. If the hook is linked, `+load` ran
// before `main`. Not shipped, not a product of the SDK package.
let package = Package(
    name: "HookConsumer",
    platforms: [.iOS(.v15)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [.product(name: "NottiSDK", package: "zeep-notti-ios-sdk")]
        ),
    ]
)

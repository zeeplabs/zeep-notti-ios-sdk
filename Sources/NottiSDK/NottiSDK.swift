import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

// Placeholder until `public-api` adds the `Notti` facade.
enum NottiSDKModule {
    static var version: String { NottiSDKVersion.current }
}

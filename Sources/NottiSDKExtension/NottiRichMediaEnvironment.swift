import Foundation

/// Everything a test needs to replace in one rich media download.
struct NottiRichMediaEnvironment {
    /// Builds the configuration of the job's own `URLSession`.
    var makeConfiguration: () -> URLSessionConfiguration
    var limits: NottiRichMediaLimits
    /// Folder that receives the downloaded file. Created on demand.
    var directory: URL
    /// Recent jobs, for correlating an expiry call with its download.
    var registry = NottiRichMediaRegistry()

    /// One registry for the process: `didReceive` and the expiry call are separate static calls.
    private static let liveRegistry = NottiRichMediaRegistry()

    static var live: NottiRichMediaEnvironment {
        NottiRichMediaEnvironment(
            makeConfiguration: {
                // Ephemeral: the extension container keeps no media cache or cookies on disk (D8).
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.waitsForConnectivity = false
                return configuration
            },
            limits: .default,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("notti-media", isDirectory: true),
            registry: liveRegistry
        )
    }
}

import Foundation

/// Reads the three Info.plist keys fed by `Example.xcconfig` (EXR-05).
///
/// A build without `Example.local.xcconfig` uses the sample values, so the app must
/// treat empty, `fixture` and unsubstituted `$(...)` values as "not configured" and
/// never call `Notti.initialize` with them. The client key is a credential: this type
/// has no description that prints it.
struct ExampleConfig: Equatable, CustomStringConvertible {
    let appId: String
    let clientKey: String
    let host: String

    init(appId: String, clientKey: String, host: String) {
        self.appId = Self.clean(appId)
        self.clientKey = Self.clean(clientKey)
        self.host = Self.clean(host)
    }

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            appId: info["NottiAppId"] as? String ?? "",
            clientKey: info["NottiClientKey"] as? String ?? "",
            host: info["NottiHost"] as? String ?? ""
        )
    }

    /// True only when both credentials hold a real value.
    var isConfigured: Bool {
        Self.isReal(appId) && Self.isReal(clientKey)
    }

    /// `https://<host>` for a bare host, or nil to keep the SDK default (AD-009).
    /// `NOTTI_HOST` is a bare host because `//` starts a comment in an xcconfig.
    var baseUrl: String? {
        guard !host.isEmpty, !host.contains("$(") else { return nil }
        return "https://\(host)"
    }

    var description: String {
        "ExampleConfig(configured: \(isConfigured), customHost: \(baseUrl != nil))"
    }

    private static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isReal(_ value: String) -> Bool {
        !value.isEmpty && value.lowercased() != "fixture" && !value.contains("$(")
    }
}

import Foundation

// MARK: - Wrapper SDK entry point (AD-024)

@available(iOSApplicationExtension, unavailable)
extension Notti {

    /// For wrapper SDKs built on this one (`react-native-notti`), not for apps. Same as
    /// `initialize(appId:clientKey:options:)`, but the backend receives the wrapper's identity:
    /// `sdkName` as `sdk_name` (a backend value such as `react-native`) and `sdkVersion` as
    /// `sdk_version`, instead of `ios` and this SDK's version. An empty value omits the field.
    /// Calling it again with a different `sdkName` or `sdkVersion` restarts the SDK, like a
    /// different app id.
    ///
    /// Visible only with `@_spi(Wrapper) import NottiSDK`, and outside the semantic-versioning
    /// promise: it may change in any release.
    @_spi(Wrapper) public static func initialize(
        appId: String,
        clientKey: String,
        options: Options = Options(),
        sdkName: String,
        sdkVersion: String
    ) {
        NottiFacade.shared.initialize(
            appId: appId,
            clientKey: clientKey,
            baseUrl: options.baseUrl,
            opensInAppURLs: options.opensInAppURLs,
            sdkName: sdkName,
            sdkVersion: sdkVersion
        )
    }
}

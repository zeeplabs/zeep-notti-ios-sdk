import Foundation

/// Owns every SDK call of the example, one method per public member, and logs through `ExampleLog`.
/// While `ExampleConfig.isConfigured` is false no method reaches the SDK (EXR-05). Typed email and
/// phone go to the SDK and are never echoed or logged (EXR-03).
@MainActor
final class ExampleModel: ObservableObject {
    @Published private(set) var deviceId: String?
    @Published private(set) var permission = "unknown"
    @Published private(set) var isInitialized = false
    @Published private(set) var isListening = false
    @Published private(set) var logLevel: ExampleLogLevel = .error

    let config: ExampleConfig
    let log: ExampleLog
    let manualForwardingEnabled: Bool
    private let sdk: ExampleSDKClient
    private var removers: [() -> Void] = []

    init(config: ExampleConfig, sdk: ExampleSDKClient, log: ExampleLog? = nil, manualForwardingEnabled: Bool = false) {
        self.config = config
        self.sdk = sdk
        self.log = log ?? ExampleLog()
        self.manualForwardingEnabled = manualForwardingEnabled
    }

    static func live() -> ExampleModel {
        ExampleModel(
            config: ExampleConfig(),
            sdk: LiveSDKClient(),
            manualForwardingEnabled: ManualForwarding().isEnabled
        )
    }

    var isConfigured: Bool { config.isConfigured }

    // MARK: Setup

    func initialize() {
        run(.initialize) {
            sdk.initialize(appId: config.appId, clientKey: config.clientKey, baseUrl: config.baseUrl)
            isInitialized = true
            deviceId = sdk.deviceId()
        }
    }

    func refreshDeviceId() {
        guard isConfigured else { return }
        deviceId = sdk.deviceId()
    }

    func setLogLevel(_ level: ExampleLogLevel) {
        run(.setLogLevel) {
            sdk.setLogLevel(level)
            logLevel = sdk.currentLogLevel()
        }
    }

    // MARK: Identity

    func login(_ externalUserId: String) {
        let id = externalUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.login, skip: id.isEmpty) { sdk.login(id) }
    }

    func logout() { run(.logout) { sdk.logout() } }

    func setEmail(_ email: String) {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.setEmail, skip: value.isEmpty) { sdk.setEmail(value) }
    }

    func clearEmail() { run(.clearEmail) { sdk.clearEmail() } }

    func setPhone(_ phone: String) {
        let value = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.setPhone, skip: value.isEmpty) { sdk.setPhone(value) }
    }

    func clearPhone() { run(.clearPhone) { sdk.clearPhone() } }

    func setSubscription(_ enabled: Bool) { run(.setSubscription) { sdk.setSubscription(enabled) } }

    func setLocationSharing(_ enabled: Bool) { run(.setLocationSharing) { sdk.setLocationSharingEnabled(enabled) } }

    // MARK: Tags

    func addTag(key: String, value: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.addTag, skip: key.isEmpty) { sdk.addTag(key, value: value) }
    }

    /// `k1=v1, k2=v2`. A pair without `=` or with an empty key is ignored.
    func addTags(_ text: String) {
        let tags = Self.parseTags(text)
        run(.addTags, skip: tags.isEmpty) { sdk.addTags(tags) }
    }

    func removeTag(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        run(.removeTag, skip: key.isEmpty) { sdk.removeTag(key) }
    }

    /// Comma-separated keys.
    func removeTags(_ text: String) {
        let keys = Self.parseKeys(text)
        run(.removeTags, skip: keys.isEmpty) { sdk.removeTags(keys) }
    }

    // MARK: Notifications

    func requestPermission() async {
        guard isConfigured else { log.record(.notConfigured); return }
        let granted = await sdk.requestPermission()
        applyPermission(granted)
        log.record(.call(.requestPermission, .ok))
    }

    func requestPermissionWithCompletion() {
        guard isConfigured else { log.record(.notConfigured); return }
        sdk.requestPermission { [weak self] granted in
            Task { @MainActor in
                self?.applyPermission(granted)
                self?.log.record(.call(.requestPermission, .ok))
            }
        }
    }

    func startListening() {
        run(.addListeners, skip: isListening) {
            removers = [
                sdk.addReceivedListener { [weak self] keys in self?.log.record(.payload(.received, keys: keys)) },
                sdk.addClickedListener { [weak self] keys in self?.log.record(.payload(.clicked, keys: keys)) },
                sdk.addDeviceIdChangedListener { [weak self] id in self?.deviceId = id }
            ]
            isListening = true
        }
    }

    func stopListening() {
        run(.removeListeners, skip: !isListening) {
            removers.forEach { $0() }
            removers = []
            isListening = false
        }
    }

    func takeInitialClick() {
        run(.takeInitialClick) {
            if let keys = sdk.takeInitialClick() { log.record(.payload(.clicked, keys: keys)) }
        }
    }

    // MARK: Internals

    /// Unconfigured: log "not configured" and stop. Skipped: log it without calling the SDK.
    private func run(_ call: ExampleCall, skip: Bool = false, _ body: () -> Void) {
        guard isConfigured else { log.record(.notConfigured); return }
        guard !skip else { log.record(.call(call, .skipped)); return }
        body()
        log.record(.call(call, .ok))
    }

    private func applyPermission(_ granted: Bool) {
        permission = granted ? "granted" : "denied"
        log.record(.permission(granted: granted))
    }

    static func parseTags(_ text: String) -> [String: String] {
        var tags: [String: String] = [:]
        for pair in text.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            tags[key] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tags
    }

    static func parseKeys(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

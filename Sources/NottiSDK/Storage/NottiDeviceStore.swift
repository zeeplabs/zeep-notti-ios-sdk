// Ported from react-native-notti 52e4b55 ios/NottiDeviceStore.swift (AD-002).
// Changes: `public` -> internal.
// Lint rules the RN code breaks are disabled for this file only (AD-007).
// swiftlint:disable identifier_name trailing_comma

import Foundation

/// Persisted device state mirroring the Notti `Device` row this install owns
/// (design.md `DeviceState`). Backed by `UserDefaults` since it's a handful
/// of scalar fields plus a small tag map — no query needs. Mirrors
/// `NottiDeviceStore.kt` field-for-field so both platforms stay provably in
/// sync (design.md's Risks & Concerns mitigation).
struct DeviceState {
    let deviceId: String?
    let lastToken: String?
    let tags: [String: String]
    let externalUserId: String?
    let subscribed: Bool
    // --- Segment telemetry (T6) ---
    let appVersion: String?
    let firstSessionAtMs: Int64?
    let lastSessionAtMs: Int64?
    let sessionCount: Int
    let sessionTimeMs: Int64
    let sessionStartedAtMs: Int64?
    let locationSharingEnabled: Bool
    // --- Device profile fields (device-profile-fields) ---
    let lastSyncedDeviceOs: String?
    let lastSyncedDeviceModel: String?
    let lastSyncedSdkVersion: String?
    let lastSyncedTimezoneId: String?
    let lastSyncedLanguage: String?
    let lastSyncedPermissionStatus: String?
    let lastUnsubscribedAtMs: Int64?
    let email: String?
    let phone: String?
    let lastSyncedEmail: String?
    let lastSyncedPhone: String?

    init(
        deviceId: String?,
        lastToken: String?,
        tags: [String: String],
        externalUserId: String?,
        subscribed: Bool,
        appVersion: String? = nil,
        firstSessionAtMs: Int64? = nil,
        lastSessionAtMs: Int64? = nil,
        sessionCount: Int = 0,
        sessionTimeMs: Int64 = 0,
        sessionStartedAtMs: Int64? = nil,
        locationSharingEnabled: Bool = false,
        lastSyncedDeviceOs: String? = nil,
        lastSyncedDeviceModel: String? = nil,
        lastSyncedSdkVersion: String? = nil,
        lastSyncedTimezoneId: String? = nil,
        lastSyncedLanguage: String? = nil,
        lastSyncedPermissionStatus: String? = nil,
        lastUnsubscribedAtMs: Int64? = nil,
        email: String? = nil,
        phone: String? = nil,
        lastSyncedEmail: String? = nil,
        lastSyncedPhone: String? = nil
    ) {
        self.deviceId = deviceId
        self.lastToken = lastToken
        self.tags = tags
        self.externalUserId = externalUserId
        self.subscribed = subscribed
        self.appVersion = appVersion
        self.firstSessionAtMs = firstSessionAtMs
        self.lastSessionAtMs = lastSessionAtMs
        self.sessionCount = sessionCount
        self.sessionTimeMs = sessionTimeMs
        self.sessionStartedAtMs = sessionStartedAtMs
        self.locationSharingEnabled = locationSharingEnabled
        self.lastSyncedDeviceOs = lastSyncedDeviceOs
        self.lastSyncedDeviceModel = lastSyncedDeviceModel
        self.lastSyncedSdkVersion = lastSyncedSdkVersion
        self.lastSyncedTimezoneId = lastSyncedTimezoneId
        self.lastSyncedLanguage = lastSyncedLanguage
        self.lastSyncedPermissionStatus = lastSyncedPermissionStatus
        self.lastUnsubscribedAtMs = lastUnsubscribedAtMs
        self.email = email
        self.phone = phone
        self.lastSyncedEmail = lastSyncedEmail
        self.lastSyncedPhone = lastSyncedPhone
    }
}

class NottiDeviceStore {

    private static let keyDeviceId = "notti_device_id"
    private static let keyLastToken = "notti_last_token"
    private static let keyExternalUserId = "notti_external_user_id"
    private static let keySubscribed = "notti_subscribed"
    private static let keyTags = "notti_tags"
    private static let keyAppVersion = "notti_app_version"
    private static let keyFirstSessionAtMs = "notti_first_session_at_ms"
    private static let keyLastSessionAtMs = "notti_last_session_at_ms"
    private static let keySessionCount = "notti_session_count"
    private static let keySessionTimeMs = "notti_session_time_ms"
    private static let keySessionStartedAtMs = "notti_session_started_at_ms"
    private static let keyLocationSharingEnabled = "notti_location_sharing_enabled"
    private static let keySessionLastSeenAtMs = "notti_session_last_seen_at_ms"
    private static let keyPendingCountryClear = "notti_pending_country_clear"
    private static let keyLastSyncedCountry = "notti_last_synced_country"
    // --- Device profile field keys (device-profile-fields) ---
    private static let keyLastSyncedDeviceOs = "notti_last_synced_device_os"
    private static let keyLastSyncedDeviceModel = "notti_last_synced_device_model"
    private static let keyLastSyncedSdkVersion = "notti_last_synced_sdk_version"
    private static let keyLastSyncedTimezoneId = "notti_last_synced_timezone_id"
    private static let keyLastSyncedLanguage = "notti_last_synced_language"
    private static let keyLastSyncedPermissionStatus = "notti_last_synced_permission_status"
    private static let keyLastUnsubscribedAtMs = "notti_last_unsubscribed_at_ms"
    private static let keyPendingUnsubscribeAtMs = "notti_pending_unsubscribe_at_ms"
    private static let keyPendingPermissionUnsubscribeAtMs = "notti_pending_permission_unsubscribe_at_ms"
    private static let keyEmail = "notti_email"
    private static let keyPhone = "notti_phone"
    private static let keyLastSyncedEmail = "notti_last_synced_email"
    private static let keyLastSyncedPhone = "notti_last_synced_phone"
    private static let keyProfileFieldAckMigrated = "notti_profile_field_ack_migrated"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Pure merge of the current tag map against an add map and/or a remove
    /// key list, as issued by a single tag-mutation call (spec P3-AC8).
    /// Removes are applied before adds, so a key present in both `add` and
    /// `remove` within the same call ends up added (add wins on overlap) —
    /// mirrors `NottiDeviceStore.kt`'s `mergeTags`.
    static func mergeTags(
        _ current: [String: String],
        add: [String: String]? = nil,
        remove: [String]? = nil
    ) -> [String: String] {
        var result = current
        remove?.forEach { result.removeValue(forKey: $0) }
        add?.forEach { key, value in result[key] = value }
        return result
    }

    func getDeviceId() -> String? {
        defaults.string(forKey: Self.keyDeviceId)
    }

    func setDeviceId(_ deviceId: String?) {
        defaults.set(deviceId, forKey: Self.keyDeviceId)
    }

    func getLastToken() -> String? {
        defaults.string(forKey: Self.keyLastToken)
    }

    func setLastToken(_ token: String?) {
        defaults.set(token, forKey: Self.keyLastToken)
    }

    func getExternalUserId() -> String? {
        defaults.string(forKey: Self.keyExternalUserId)
    }

    func setExternalUserId(_ externalUserId: String?) {
        defaults.set(externalUserId, forKey: Self.keyExternalUserId)
    }

    func getSubscribed() -> Bool {
        defaults.bool(forKey: Self.keySubscribed)
    }

    /// Tri-state read of `subscribed`: nil when the key was never written (no
    /// subscription PATCH acknowledged yet). `getSubscribed()` collapses that
    /// to `false`, which hid the unknown state from the DPF-14 transition check
    /// - the backend registers devices subscribed by default.
    func getSubscribedIfKnown() -> Bool? {
        (defaults.object(forKey: Self.keySubscribed) as? NSNumber)?.boolValue
    }

    func setSubscribed(_ subscribed: Bool) {
        defaults.set(subscribed, forKey: Self.keySubscribed)
    }

    func getTags() -> [String: String] {
        // A7 (found in pre-release review): `as? [String: String]` is an
        // all-or-nothing cast on the whole dictionary - one non-string value
        // (which should never happen given `setTags`' own input type, but this
        // reads persisted `UserDefaults` state that could in principle have been
        // written by a future/older SDK version) silently wiped the entire local
        // tag cache. Per-key tolerance instead, matching every other tag-parsing
        // path in the SDK (`NottiApiClient.swift`'s `parseDeviceResponse`).
        (defaults.dictionary(forKey: Self.keyTags) ?? [:]).compactMapValues { $0 as? String }
    }

    func setTags(_ tags: [String: String]) {
        defaults.set(tags, forKey: Self.keyTags)
    }

    // MARK: - Segment telemetry fields (T6)

    func getAppVersion() -> String? {
        defaults.string(forKey: Self.keyAppVersion)
    }

    func setAppVersion(_ appVersion: String?) {
        defaults.set(appVersion, forKey: Self.keyAppVersion)
    }

    func getFirstSessionAtMs() -> Int64? {
        (defaults.object(forKey: Self.keyFirstSessionAtMs) as? NSNumber)?.int64Value
    }

    func setFirstSessionAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keyFirstSessionAtMs)
    }

    func getLastSessionAtMs() -> Int64? {
        (defaults.object(forKey: Self.keyLastSessionAtMs) as? NSNumber)?.int64Value
    }

    func setLastSessionAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keyLastSessionAtMs)
    }

    func getSessionCount() -> Int {
        defaults.integer(forKey: Self.keySessionCount)
    }

    func setSessionCount(_ count: Int) {
        defaults.set(count, forKey: Self.keySessionCount)
    }

    func getSessionTimeMs() -> Int64 {
        (defaults.object(forKey: Self.keySessionTimeMs) as? NSNumber)?.int64Value ?? 0
    }

    func setSessionTimeMs(_ ms: Int64) {
        defaults.set(NSNumber(value: ms), forKey: Self.keySessionTimeMs)
    }

    func getSessionStartedAtMs() -> Int64? {
        (defaults.object(forKey: Self.keySessionStartedAtMs) as? NSNumber)?.int64Value
    }

    func setSessionStartedAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keySessionStartedAtMs)
    }

    func getLocationSharingEnabled() -> Bool {
        defaults.bool(forKey: Self.keyLocationSharingEnabled)
    }

    func setLocationSharingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.keyLocationSharingEnabled)
    }

    /// Last known foreground timestamp of the open session (heartbeat). Used
    /// to close an orphaned session (unclean kill) at its real end instead of
    /// `now - startedAt`, which counted all the time the app was dead as
    /// foreground (SEGTEL-08 "last known foreground timestamp").
    func getSessionLastSeenAtMs() -> Int64? {
        (defaults.object(forKey: Self.keySessionLastSeenAtMs) as? NSNumber)?.int64Value
    }

    func setSessionLastSeenAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keySessionLastSeenAtMs)
    }

    /// LGPD: set on location opt-out, cleared ONLY when the backend
    /// acknowledged the `{country: null}` PATCH with a 2xx. Persisted so a
    /// clear issued before `initialize`, offline, or against a 5xx survives a
    /// process death and is re-sent on the next registration/foreground/flush.
    func getPendingCountryClear() -> Bool {
        defaults.bool(forKey: Self.keyPendingCountryClear)
    }

    func setPendingCountryClear(_ pending: Bool) {
        defaults.set(pending, forKey: Self.keyPendingCountryClear)
    }

    /// The last country value the backend acknowledged (2xx). Drives the
    /// diff (no PATCH when unchanged) and tells the opt-out path whether there
    /// is anything server-side to clear.
    func getLastSyncedCountry() -> String? {
        defaults.string(forKey: Self.keyLastSyncedCountry)
    }

    func setLastSyncedCountry(_ country: String?) {
        defaults.set(country, forKey: Self.keyLastSyncedCountry)
    }

    func getState() -> DeviceState {
        DeviceState(
            deviceId: getDeviceId(),
            lastToken: getLastToken(),
            tags: getTags(),
            externalUserId: getExternalUserId(),
            subscribed: getSubscribed(),
            appVersion: getAppVersion(),
            firstSessionAtMs: getFirstSessionAtMs(),
            lastSessionAtMs: getLastSessionAtMs(),
            sessionCount: getSessionCount(),
            sessionTimeMs: getSessionTimeMs(),
            sessionStartedAtMs: getSessionStartedAtMs(),
            locationSharingEnabled: getLocationSharingEnabled(),
            lastSyncedDeviceOs: getLastSyncedDeviceOs(),
            lastSyncedDeviceModel: getLastSyncedDeviceModel(),
            lastSyncedSdkVersion: getLastSyncedSdkVersion(),
            lastSyncedTimezoneId: getLastSyncedTimezoneId(),
            lastSyncedLanguage: getLastSyncedLanguage(),
            lastSyncedPermissionStatus: getLastSyncedPermissionStatus(),
            lastUnsubscribedAtMs: getLastUnsubscribedAtMs(),
            email: getEmail(),
            phone: getPhone(),
            lastSyncedEmail: getLastSyncedEmail(),
            lastSyncedPhone: getLastSyncedPhone()
        )
    }

    // MARK: - Device profile field accessors (device-profile-fields)

    func getLastSyncedDeviceOs() -> String? {
        defaults.string(forKey: Self.keyLastSyncedDeviceOs)
    }

    /// One-shot upgrade step for the echo-based profile-field ack (0.6.0). SDK
    /// <= 0.5.0 marked the six read-once fields synced on any 2xx, even when the
    /// backend ignored them; with an unchanged value the diff would then never
    /// re-send them. Clearing their last-synced values once makes the next
    /// registration re-send each (at most six PATCHes, once per install) and ack
    /// it against the echo. A fresh install has nothing to clear.
    func migrateProfileFieldAckIfNeeded() {
        guard !defaults.bool(forKey: Self.keyProfileFieldAckMigrated) else { return }
        for key in [
            Self.keyAppVersion, Self.keyLastSyncedDeviceOs, Self.keyLastSyncedDeviceModel,
            Self.keyLastSyncedSdkVersion, Self.keyLastSyncedTimezoneId, Self.keyLastSyncedLanguage,
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Self.keyProfileFieldAckMigrated)
    }

    /// Forgets every server-acked profile value and the synced permission status.
    /// Called when registration answers with a device id different from the stored
    /// one: the server row is new (deleted and re-created, or a sandbox reset), so
    /// nothing this device "already synced" exists there. Without it the diff would
    /// never re-send the fields and the row would stay empty. Held email/phone are
    /// not touched; they re-sync on every registration.
    /// Ported from react-native-notti 9c5af1d (AD-018).
    func clearProfileFieldAcks() {
        for key in [
            Self.keyAppVersion, Self.keyLastSyncedDeviceOs, Self.keyLastSyncedDeviceModel,
            Self.keyLastSyncedSdkVersion, Self.keyLastSyncedTimezoneId, Self.keyLastSyncedLanguage,
            Self.keyLastSyncedPermissionStatus
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    func setLastSyncedDeviceOs(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedDeviceOs)
    }

    func getLastSyncedDeviceModel() -> String? {
        defaults.string(forKey: Self.keyLastSyncedDeviceModel)
    }

    func setLastSyncedDeviceModel(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedDeviceModel)
    }

    func getLastSyncedSdkVersion() -> String? {
        defaults.string(forKey: Self.keyLastSyncedSdkVersion)
    }

    func setLastSyncedSdkVersion(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedSdkVersion)
    }

    func getLastSyncedTimezoneId() -> String? {
        defaults.string(forKey: Self.keyLastSyncedTimezoneId)
    }

    func setLastSyncedTimezoneId(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedTimezoneId)
    }

    func getLastSyncedLanguage() -> String? {
        defaults.string(forKey: Self.keyLastSyncedLanguage)
    }

    func setLastSyncedLanguage(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedLanguage)
    }

    func getLastSyncedPermissionStatus() -> String? {
        defaults.string(forKey: Self.keyLastSyncedPermissionStatus)
    }

    func setLastSyncedPermissionStatus(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedPermissionStatus)
    }

    func getLastUnsubscribedAtMs() -> Int64? {
        (defaults.object(forKey: Self.keyLastUnsubscribedAtMs) as? NSNumber)?.int64Value
    }

    func setLastUnsubscribedAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keyLastUnsubscribedAtMs)
    }

    /// Stamp of an app-driven (`setSubscription(false)`) unsubscribe the
    /// backend has not acknowledged yet, nil otherwise. A retry re-sends this
    /// persisted value instead of a fresh `now` (DPF-14 records the detection
    /// time). Mirrors Android's `pendingUnsubscribeAtMs`.
    func getPendingUnsubscribeAtMs() -> Int64? {
        (defaults.object(forKey: Self.keyPendingUnsubscribeAtMs) as? NSNumber)?.int64Value
    }

    func setPendingUnsubscribeAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keyPendingUnsubscribeAtMs)
    }

    /// Same as `getPendingUnsubscribeAtMs`, for the permission-driven
    /// (granted -> denied) path.
    func getPendingPermissionUnsubscribeAtMs() -> Int64? {
        (defaults.object(forKey: Self.keyPendingPermissionUnsubscribeAtMs) as? NSNumber)?.int64Value
    }

    func setPendingPermissionUnsubscribeAtMs(_ ms: Int64?) {
        defaults.set(ms.map(NSNumber.init(value:)), forKey: Self.keyPendingPermissionUnsubscribeAtMs)
    }

    func getEmail() -> String? {
        defaults.string(forKey: Self.keyEmail)
    }

    func setEmail(_ value: String?) {
        defaults.set(value, forKey: Self.keyEmail)
    }

    func getPhone() -> String? {
        defaults.string(forKey: Self.keyPhone)
    }

    func setPhone(_ value: String?) {
        defaults.set(value, forKey: Self.keyPhone)
    }

    /// The last email value the backend acknowledged (2xx), nil when a clear
    /// was acknowledged or nothing was ever synced. Distinguishes "held nil and
    /// already cleared server-side" from "held nil but the clear never landed",
    /// so a failed/pre-init clear is re-sent at the next registration (DPF-18).
    func getLastSyncedEmail() -> String? {
        defaults.string(forKey: Self.keyLastSyncedEmail)
    }

    func setLastSyncedEmail(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedEmail)
    }

    /// Phone counterpart of `getLastSyncedEmail`.
    func getLastSyncedPhone() -> String? {
        defaults.string(forKey: Self.keyLastSyncedPhone)
    }

    func setLastSyncedPhone(_ value: String?) {
        defaults.set(value, forKey: Self.keyLastSyncedPhone)
    }
}

// swiftlint:enable identifier_name trailing_comma

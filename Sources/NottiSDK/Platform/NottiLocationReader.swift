// Ported from react-native-notti 52e4b55 ios/NottiImpl.swift:389-462 (`NottiLocationReader`) (AD-002).
// Changes: `private final class` -> internal `final class` (it now lives in its own file);
// marked unavailable in app extensions (`CLLocationManager`, AGENTS.md extension-safety rule). Body unchanged.

import CoreLocation
import Foundation

/// Location reads for segment telemetry P3.
///
/// Threading (final review E): `CLLocationManager` must be created on a
/// thread with a live run loop - it delivers its delegate callbacks on the
/// creating thread's run loop - and the old lazy creation happened on
/// `NottiCore`'s work queue (a GCD thread without one). The manager is now
/// created on the main thread (inline if `init` already runs there, else via
/// `main.async`, never `main.sync`: no deadlock with a main thread that waits
/// on module construction), and every touch of it stays on main:
/// - `hasPermission()` (synchronous, called from the work queue) reads a
///   lock-guarded cache, seeded on main right after creation and refreshed by
///   `locationManagerDidChangeAuthorization` (e.g. permission changed in
///   Settings while backgrounded). `NottiImpl.init` creates this reader
///   before `NottiCore` enqueues its `appStateProvider` main block, so the
///   seed lands before the cold-start session reads it (main is FIFO).
/// - `readCountry` hops to main to read `location` and start the geocode;
///   `NottiCore` hops the callback back onto its work queue.
/// One shared `CLGeocoder`, never asked to geocode in parallel (Apple
/// rate-limits reverse geocoding; `NottiCore` additionally throttles reads).
/// The SDK never requests permission (SEGTEL-14), only reads it.
@available(iOSApplicationExtension, unavailable)
final class NottiLocationReader: NSObject, CLLocationManagerDelegate {
    private let lock = NSLock()
    private var cachedPermission = false
    /// Main-thread-only.
    private var manager: CLLocationManager?
    /// Main-thread-only.
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        if Thread.isMainThread {
            setUpManager()
        } else {
            DispatchQueue.main.async { self.setUpManager() }
        }
    }

    /// Main thread only.
    private func setUpManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        updatePermission(manager.authorizationStatus)
    }

    private func updatePermission(_ status: CLAuthorizationStatus) {
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        lock.lock()
        cachedPermission = granted
        lock.unlock()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePermission(manager.authorizationStatus)
    }

    func hasPermission() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedPermission
    }

    func readCountry(_ callback: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard let location = self.manager?.location, !self.geocoder.isGeocoding else {
                callback(nil)
                return
            }
            self.geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                callback(placemarks?.first?.isoCountryCode)
            }
        }
    }
}

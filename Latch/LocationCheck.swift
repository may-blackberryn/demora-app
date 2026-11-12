//
//  LocationCheck.swift
//  The app's only CoreLocation code (docs/conditional-sessions-redesign.md
//  §5.5, C8, C9; C15 step 4). Host app only, never an extension.
//
//  - "While Using" only: `requestWhenInUseAuthorization`, and only after the
//    user tapped "Allow location" on an in-sheet card that opened from Check
//    in or "Set to where I am now". Never at launch, never again after a
//    denial (iOS wouldn't ask again anyway), never "Always".
//  - One fix per read: `requestLocation()` with a 15 s timeout, stopped as
//    soon as it resolves or the sheet goes away. No updates, no monitoring,
//    no regions, no visits, no background modes, no geocoder.
//  - The fix lives only in memory: it is handed back to the caller and turned
//    into ✓/✗/? results (or a place's rounded centre) right away. Nothing here
//    saves, prints or logs a location.
//  Trust rules are pure and tested (`LocationTrust`, `ConditionEvaluator`).
//

import CoreLocation

@MainActor
final class LocationCheck: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// `NSLocationTemporaryUsageDescriptionDictionary` key in Latch/Info.plist.
    static let precisePurposeKey = "CheckIn"

    private let manager = CLLocationManager()
    private var permissionWaiter: CheckedContinuation<Void, Never>?
    private var fixWaiter: CheckedContinuation<LocationReadOutcome, Never>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var permission: LocationPermission {
        switch manager.authorizationStatus {
        case .notDetermined: return .notAsked
        case .restricted: return .restricted
        case .authorizedWhenInUse, .authorizedAlways:
            return .allowed(precise: manager.accuracyAuthorization == .fullAccuracy)
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    /// Shows iOS's "While Using" prompt if Demora was never asked, and waits
    /// for the answer. Call only from the user's tap on "Allow location".
    func requestPermission() async {
        guard manager.authorizationStatus == .notDetermined, permissionWaiter == nil else { return }
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            permissionWaiter = waiter
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One fix, at most 15 s. With Approximate Location, iOS is asked once
    /// for precise location for this check (a place can't be told from an
    /// approximate fix); declined → the fix is marked not precise.
    func readOnce(wantsPrecise: Bool) async -> LocationReadOutcome {
        cancel()
        guard case .allowed(let precise) = permission else { return .failed(.denied) }
        if wantsPrecise && !precise {
            _ = try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.precisePurposeKey)
            guard case .allowed = permission else { return .failed(.denied) }
        }
        return await withCheckedContinuation { (waiter: CheckedContinuation<LocationReadOutcome, Never>) in
            fixWaiter = waiter
            manager.requestLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(LocationTrust.timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failed(.timedOut))
            }
        }
    }

    /// Stops a read in flight (the sheet closed or a newer check started).
    func cancel() {
        finish(.failed(.cancelled))
    }

    private func finish(_ outcome: LocationReadOutcome) {
        timeout?.cancel()
        timeout = nil
        guard let waiter = fixWaiter else { return }
        fixWaiter = nil
        // Cancels the outstanding `requestLocation()`; nothing keeps running.
        manager.stopUpdatingLocation()
        waiter.resume(returning: outcome)
    }

    private func finishSample(_ sample: LocationSample) {
        finish(.sample(sample, precise: manager.accuracyAuthorization == .fullAccuracy))
    }

    // MARK: CLLocationManagerDelegate (delivered on the main thread, which made the manager)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let decided = manager.authorizationStatus != .notDetermined
        Task { @MainActor in
            // The callback iOS sends when the manager is made says "not
            // determined": only an answer ends the wait.
            guard decided, let waiter = self.permissionWaiter else { return }
            self.permissionWaiter = nil
            waiter.resume()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let source = last.sourceInformation
        let sample = LocationSample(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude,
                                    horizontalAccuracy: last.horizontalAccuracy, timestamp: last.timestamp,
                                    isSimulated: source?.isSimulatedBySoftware ?? false,
                                    isFromAccessory: source?.isProducedByAccessory ?? false)
        Task { @MainActor in self.finishSample(sample) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finish(.failed(denied ? .denied : .noFix)) }
    }
}

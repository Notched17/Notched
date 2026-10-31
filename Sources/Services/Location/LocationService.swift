// SPDX-License-Identifier: GPL-3.0-or-later

import CoreLocation

/// One approximate location, when asked. A protocol so tests don't need macOS.
@MainActor
protocol DeviceLocationProvider: AnyObject {
    /// Nil if macOS says no or can't tell. Never asks for permission itself.
    func approximateLocation() async -> WeatherLocation?
}

/// CoreLocation, used for a single fix (`requestLocation`) at low accuracy
/// (about 3 km), never continuous updates. The weather module asks at most once
/// a day (`WeatherLocationPlan`), so Location is idle the rest of the time.
@MainActor
final class CoreLocationProvider: NSObject, DeviceLocationProvider {
    private struct Fix: Sendable {
        var latitude: Double
        var longitude: Double
    }

    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<Fix?, Never>?

    func approximateLocation() async -> WeatherLocation? {
        // One request at a time.
        guard continuation == nil else { return nil }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.manager = manager
        let fix: Fix? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
        self.manager = nil
        guard let fix else { return nil }
        let name = await placeName(latitude: fix.latitude, longitude: fix.longitude)
        return WeatherLocation(name: name ?? "Current location", latitude: fix.latitude, longitude: fix.longitude, source: .device)
    }

    private func finish(_ fix: Fix?) {
        continuation?.resume(returning: fix)
        continuation = nil
    }

    /// The town's name, for the label only. Fails quietly offline.
    private func placeName(latitude: Double, longitude: Double) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        return placemarks?.first?.locality
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map { Fix(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        Task { @MainActor in self.finish(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

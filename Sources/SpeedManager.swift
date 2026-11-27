import Foundation
import CoreLocation

// GPS 速度（手机放车把上即可，不依赖车辆蓝牙）
final class SpeedManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedKmh: Double = 0
    @Published var gpsEnabled: Bool = false

    private let lm = CLLocationManager()

    func start() {
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            gpsEnabled = true
            manager.startUpdatingLocation()
        default:
            gpsEnabled = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let spd = max(0, loc.speed) // m/s，无效时为负数
        DispatchQueue.main.async {
            self.speedKmh = spd >= 0 ? spd * 3.6 : 0
        }
    }
}

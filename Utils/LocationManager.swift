import Foundation
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChanged: ((Bool) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestAuthorization() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else {
            onAuthorizationChanged?(isAuthorized)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        onAuthorizationChanged?(isAuthorized)
    }
    
    var isAuthorized: Bool {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorized:
            return true
        default:
            return false
        }
    }
}


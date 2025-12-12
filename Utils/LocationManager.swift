import Foundation
import CoreLocation
import AppKit // Нужно для NSWorkspace

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    // Публикуемые свойства для Combine
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var errorMessage: String? = nil
    
    // Кложур для обратной совместимости
    var onAuthorizationChanged: ((Bool) -> Void)?
    
    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }
    
    // Первичный запрос прав
    func requestAuthorization() {
        // Если статус уже .denied, повторный вызов этого метода системой игнорируется.
        // Поэтому мы будем проверять статус на уровне UI.
        manager.requestAlwaysAuthorization()
    }
    
    // Принудительное обновление статуса (вызываем при разворачивании приложения)
    func refreshAuthorizationStatus() {
        // Читаем текущий статус напрямую из менеджера
        let status = manager.authorizationStatus
        // Обновляем Published свойство (это триггернет UI)
        DispatchQueue.main.async {
            self.authorizationStatus = status
            // Если права появились, убираем ошибку
            if self.isAuthorized {
                self.errorMessage = nil
            }
        }
    }
    
    // Открытие системных настроек
    func openSystemSettings() {
        // Ссылка на настройки Приватности -> Геолокация
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Этот метод вызывается системой автоматически при изменении прав
        refreshAuthorizationStatus()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Устаревший метод, но для надежности оставим
        refreshAuthorizationStatus()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            if let clError = error as? CLError, clError.code == .locationUnknown {
                return
            }
            self?.errorMessage = "Location Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    var isAuthorized: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }
}

import SwiftUI

@main
struct WifiAnalyzerApp: App {
    // ViewModel создается здесь и живет все время работы приложения
    @StateObject private var viewModel = AnalyzerViewModel()
    
    // Свойство для отслеживания состояния приложения (активно/фон)
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainTableView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                // Слушаем изменения состояния окна
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // Приложение стало активным
                        // Просим менеджер обновить статус прав
                        viewModel.locationManager.refreshAuthorizationStatus()
                        
                        // Если права уже есть, запускаем сканирование/обновление
                        if viewModel.isLocationAuthorized {
                            viewModel.refresh()
                        }
                    }
                }
        }
    }
}

//  WifiAnalyzerApp.swift
import SwiftUI

@main
struct WifiAnalyzerApp: App {
    // ViewModel создается здесь и живет все время работы приложения
    @StateObject private var viewModel = AnalyzerViewModel()
    @StateObject private var uiState = AppUIState()
    
    // Свойство для отслеживания состояния приложения (активно/фон)
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainTableView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(uiState)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // ИСПРАВЛЕНО: Вызываем публичный метод ViewModel
                        viewModel.checkLocationAuthorization()
                        
                        // Если права уже есть, запускаем сканирование
                        if viewModel.isLocationAuthorized {
                            viewModel.refresh()
                        }
                    }
                }
        }
        .commands {
            WiFACommands(viewModel: viewModel, uiState: uiState)
        }
    }
}

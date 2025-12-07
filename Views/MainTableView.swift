import SwiftUI

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var showingColumnMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок с кнопками
            HStack {
                Button("Обновить") { viewModel.refresh() }
                Menu {
                    Button("1 секунда") { viewModel.updateRefreshInterval(to: 1) }
                    Button("2 секунды") { viewModel.updateRefreshInterval(to: 2) }
                    Button("5 секунд") { viewModel.updateRefreshInterval(to: 5) }
                    Button("10 секунд") { viewModel.updateRefreshInterval(to: 10) }
                } label: {
                    Text("Интервал: \(Int(viewModel.refreshInterval)) с")
                }
                Button("Настройки столбцов") { showingColumnMenu.toggle() }
                Spacer()
                if !viewModel.isLocationAuthorized {
                    Button("Запросить Location Services") {
                        Task { @MainActor in
                            viewModel.locationManager.requestAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            
            // Сообщение об ошибке
            if let err = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(err)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Скрыть") {
                        viewModel.errorMessage = nil
                    }
                }
                .padding(8)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Таблица с AppKit
            WiFiTableView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 500)
        }
        .padding()
        .sheet(isPresented: $showingColumnMenu) {
            ColumnSettingsView(viewModel: viewModel)
        }
    }
}

struct ColumnSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройка столбцов")
                .font(.headline)
                .padding()
            
            List {
                ForEach(viewModel.columnDefinitions.sorted { $0.order < $1.order }) { col in
                    Toggle(isOn: Binding(
                        get: { col.isVisible },
                        set: { _ in viewModel.toggleColumn(col.id) }
                    )) {
                        Text(col.title)
                    }
                }
            }
            
            HStack {
                Button("Сбросить по умолчанию") {
                    viewModel.resetColumnsToDefault()
                }
                Spacer()
                Button("Готово") { dismiss() }
            }
            .padding()
        }
        .frame(width: 350, height: 600)
    }
}

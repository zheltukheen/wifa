//
//  MainTableView.swift
//

import SwiftUI
import Charts
import AppKit

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    // UI State
    @State private var showingColumnMenu = false
    @State private var showInspector = true
    @State private var customIntervalText = ""
    @State private var showingCustomIntervalAlert = false
    
    // Resizable Panels State
    @State private var inspectorBaseWidth: CGFloat = 300
    @State private var inspectorDragOffset: CGFloat = 0
    @State private var bottomPanelBaseHeight: CGFloat = 250
    @State private var bottomPanelDragOffset: CGFloat = 0
    @State private var selectedBottomTab: Int = 0
    
    // Размеры панелей с ограничениями
    var currentInspectorWidth: CGFloat {
        max(250, min(500, inspectorBaseWidth - inspectorDragOffset))
    }
    
    var currentBottomPanelHeight: CGFloat {
        max(150, min(600, bottomPanelBaseHeight - bottomPanelDragOffset))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. TOOLBAR
            ToolbarView(
                viewModel: viewModel,
                showInspector: $showInspector,
                showingColumnMenu: $showingColumnMenu,
                customIntervalText: $customIntervalText,
                showingCustomIntervalAlert: $showingCustomIntervalAlert
            )
            
            // 2. CONTENT AREA
            GeometryReader { geo in
                VStack(spacing: 0) {
                    
                    // A. TOP SECTION: Table + Inspector
                    HStack(spacing: 0) {
                        
                        // Table Area
                        VStack(spacing: 0) {
                            if let err = viewModel.errorMessage {
                                ErrorBanner(message: err, onClose: { viewModel.errorMessage = nil })
                            }
                            
                            WiFiTableView(viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // Inspector Area
                        if showInspector {
                            // Вертикальный разделитель (Resizer)
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                                .overlay(
                                    Rectangle().fill(Color.clear).frame(width: 9)
                                        .contentShape(Rectangle())
                                        .onHover { inside in
                                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in self.inspectorDragOffset = value.translation.width }
                                        .onEnded { _ in
                                            self.inspectorBaseWidth = self.currentInspectorWidth
                                            self.inspectorDragOffset = 0
                                        }
                                )
                                .zIndex(10)
                            
                            NetworkInspectorView(viewModel: viewModel)
                                .frame(width: currentInspectorWidth)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .transition(.move(edge: .trailing))
                        }
                    }
                    
                    // B. BOTTOM SECTION: Tabs + Charts
                    
                    // Горизонтальный разделитель (Resizer)
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .overlay(
                            Rectangle().fill(Color.clear).frame(height: 9)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeUp.push() } else { NSCursor.pop() }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Тянем вверх -> увеличиваем высоту (инверсия Y)
                                    self.bottomPanelDragOffset = value.translation.height
                                }
                                .onEnded { _ in
                                    self.bottomPanelBaseHeight = self.currentBottomPanelHeight
                                    self.bottomPanelDragOffset = 0
                                }
                        )
                        .zIndex(20)
                    
                    // Bottom Container
                    VStack(spacing: 0) {
                        
                        // --- НОВОЕ МЕНЮ РЕЖИМОВ (Центрировано) ---
                        BottomPanelTabs(selectedTab: $selectedBottomTab)
                        
                        Divider()
                        
                        // Chart Content
                        ZStack {
                            Color(nsColor: .controlBackgroundColor).edgesIgnoringSafeArea(.all)
                            
                            if selectedBottomTab == 0 {
                                SpectrumView(viewModel: viewModel)
                            } else {
                                SignalHistoryView(viewModel: viewModel)
                            }
                        }
                        .clipped()
                    }
                    .frame(height: currentBottomPanelHeight)
                }
            }
        }
        .sheet(isPresented: $showingColumnMenu) {
            ColumnSettingsView(viewModel: viewModel)
        }
        .alert("Custom Interval", isPresented: $showingCustomIntervalAlert) {
            TextField("Seconds", text: $customIntervalText)
            Button("OK") {
                if let val = Double(customIntervalText), val > 0 {
                    viewModel.updateRefreshInterval(to: val)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter refresh interval in seconds:")
        }
        .onAppear {
            if !viewModel.isLocationAuthorized {
                viewModel.requestLocationAuthorization()
            }
        }
    }
}

// MARK: - New Bottom Tabs Component
struct BottomPanelTabs: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 1. ВЫРАВНИВАНИЕ ПО ЦЕНТРУ: Spacer слева
            Spacer()
            
            // Кнопка Спектр
            TabButton(
                title: "Спектр",
                icon: "waveform.path.ecg",
                isSelected: selectedTab == 0,
                action: { selectedTab = 0 }
            )
            
            // Разделитель между кнопками
            Divider().frame(height: 16)
            
            // Кнопка История
            TabButton(
                title: "История",
                icon: "clock.arrow.circlepath",
                isSelected: selectedTab == 1,
                action: { selectedTab = 1 }
            )
            
            // 1. ВЫРАВНИВАНИЕ ПО ЦЕНТРУ: Spacer справа
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Material.bar)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Toolbar Component (Unified Settings)
struct ToolbarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Binding var showInspector: Bool
    @Binding var showingColumnMenu: Bool
    @Binding var customIntervalText: String
    @Binding var showingCustomIntervalAlert: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            
            // 1. Refresh Button (Left)
            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Now")
            .buttonStyle(.borderless)
            .frame(width: 30, height: 24)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            // 2. Filters (Band)
            HStack(spacing: 0) {
                Toggle("2.4", isOn: $viewModel.filterBand24)
                Divider().frame(height: 12).padding(.horizontal, 6)
                Toggle("5", isOn: $viewModel.filterBand5)
                Divider().frame(height: 12).padding(.horizontal, 6)
                Toggle("6", isOn: $viewModel.filterBand6)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            
            // 3. Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 100, maxWidth: 200)
            }
            .padding(5)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            Spacer()
            
            // 4. Right Controls (Settings & Tools)
            HStack(spacing: 16) {
                
                // --- UNIFIED SETTINGS MENU (Объединенное меню) ---
                Menu {
                    // Секция 1: Интервал сканирования
                    Section {
                        Picker("Scan Interval:", selection: Binding(
                            get: { viewModel.refreshInterval },
                            set: { viewModel.updateRefreshInterval(to: $0) }
                        )) {
                            Text("1s").tag(1.0)
                            Text("3s").tag(3.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                            Text("30s").tag(30.0)
                        }
                        
                        // Кнопка Custom внутри меню
                        Button("Custom Interval...") {
                            customIntervalText = String(Int(viewModel.refreshInterval))
                            showingCustomIntervalAlert = true
                        }
                    } header: {
                        Text("Monitoring")
                    }
                    
                    Divider()
                    
                    // Секция 2: Фильтр сигнала (Перенесено сюда)
                    Section {
                        // Slider внутри меню
                        Text("Min Signal: \(Int(viewModel.minSignalThreshold)) dBm")
                        Slider(value: $viewModel.minSignalThreshold, in: -100...(-30)) {
                            Text("Threshold")
                        }
                    } header: {
                        Text("Filters")
                    }
                    
                    Divider()
                    
                    // Секция 3: Прочие настройки
                    Section {
                        Picker("Remove inactive after:", selection: $viewModel.removeAfterInterval) {
                            ForEach(NetworkRemovalInterval.allCases) { Text($0.title).tag($0) }
                        }
                        
                        Picker("Signal Unit:", selection: $viewModel.signalDisplayMode) {
                            ForEach(SignalDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } header: {
                        Text("Display")
                    }
                    
                } label: {
                    // Иконка Шестеренки
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .help("Settings & Monitoring Control")
                
                // Column Settings
                Button(action: { showingColumnMenu.toggle() }) {
                    Image(systemName: "tablecells")
                }
                .buttonStyle(.borderless)
                .help("Columns")
                
                // Export
                Button(action: { viewModel.exportCSV() }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export CSV")
                
                // Inspector Toggle
                Button(action: { withAnimation(.spring(response: 0.3)) { showInspector.toggle() } }) {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(showInspector ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector")
                
                // Location Alert
                if !viewModel.isLocationAuthorized {
                    Button(action: {
                        viewModel.openSystemLocationSettings()
                    }) {
                        Image(systemName: "location.slash.fill")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Location Access Required")
                }
            }
        }
        .padding(10)
        .background(Material.bar)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }
}

// MARK: - Subviews (Остались без изменений)

struct ErrorBanner: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.callout).foregroundColor(.primary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
    }
}

struct ColumnSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Column Settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Material.regular)
            
            Divider()
            
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Filter columns...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(10)
            
            List {
                ForEach(filteredColumns) { col in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .frame(width: 20)
                        
                        Toggle(isOn: Binding(
                            get: { col.isVisible },
                            set: { _ in viewModel.toggleColumn(col.id) }
                        )) {
                            Text(col.title).font(.body)
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 2)
                }
                .onMove(perform: moveColumns)
            }
            .listStyle(.inset)
            
            Divider()
            
            HStack {
                Button(action: {
                    withAnimation { viewModel.resetColumnsToDefault() }
                }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                
                Spacer()
                Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(Material.bar)
        }
        .frame(width: 350, height: 500)
    }
    
    private var filteredColumns: [ColumnDefinition] {
        let sorted = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func moveColumns(from source: IndexSet, to destination: Int) {
        var sortedColumns = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        sortedColumns.move(fromOffsets: source, toOffset: destination)
        
        for (index, col) in sortedColumns.enumerated() {
            if let originalIndex = viewModel.columnDefinitions.firstIndex(where: { $0.id == col.id }) {
                viewModel.columnDefinitions[originalIndex].order = index
            }
        }
        viewModel.saveColumnSettings()
    }
}

struct NetworkInspectorView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Network Details").font(.headline)
                Spacer()
            }
            .padding()
            .background(Material.bar)
            
            Divider()
            
            ScrollView {
                if let network = viewModel.selectedNetwork {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(network.ssid.isEmpty ? "<Hidden>" : network.ssid)
                                    .font(.title2).bold()
                                    .foregroundColor(network.bssid == viewModel.currentConnectedBSSID ? .accentColor : .primary)
                                    .lineLimit(2)
                                
                                HStack {
                                    Text(network.bssid)
                                        .font(.caption).monospaced()
                                        .padding(4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textSelection(.enabled)
                                    
                                    if network.bssid == viewModel.currentConnectedBSSID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .help("Currently Connected")
                                    }
                                }
                            }
                            Spacer()
                            SignalBadge(
                                rssi: network.signal,
                                label: viewModel.formatSignal(network.signal),
                                unit: viewModel.signalDisplayMode == .dbm ? "dBm" : ""
                            )
                        }
                        
                        Divider()
                        
                        // Specs
                        GroupBox("Technical Specs") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                DetailRow(label: "Channel", value: "\(network.channel)")
                                DetailRow(label: "Band", value: network.band)
                                DetailRow(label: "Width", value: network.channelWidth)
                                DetailRow(label: "Generation", value: network.generation)
                                DetailRow(label: "Max Rate", value: "\(Int(network.maxRate)) Mbps")
                                DetailRow(label: "Vendor", value: network.vendor)
                                DetailRow(label: "Mode", value: network.mode)
                                
                                DetailRow(label: "Streams", value: network.streams.map { "\($0)" } ?? "-")
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Security
                        GroupBox("Security & Advanced") {
                            VStack(alignment: .leading, spacing: 8) {
                                DetailRow(label: "Protocol", value: network.security)
                                DetailRow(label: "Protection Mode", value: network.protectionMode ?? "Unknown")
                                DetailRow(label: "WPS", value: network.wps ?? "N/A")
                                DetailRow(label: "Fast Transition (802.11r)", value: network.fastTransition == true ? "Yes" : "No")
                                if let cc = network.countryCode {
                                    DetailRow(label: "Country Code", value: cc)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        
                        // Timestamps
                        GroupBox("Activity") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                DetailRow(label: "First Seen", value: formatDate(network.firstSeen))
                                DetailRow(label: "Last Seen", value: formatDate(network.lastSeen))
                                DetailRow(label: "Seen Ago", value: "\(network.seen) sec")
                            }
                        }
                        
                    }
                    .padding()
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("Select a network to view details")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Helper Views

struct SignalBadge: View {
    let rssi: Int
    let label: String
    let unit: String
    
    var color: Color {
        if rssi > -50 { return .green }
        else if rssi > -70 { return .yellow }
        else { return .red }
    }
    
    var body: some View {
        VStack {
            Text(label)
                .font(.title3).bold()
                .foregroundColor(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

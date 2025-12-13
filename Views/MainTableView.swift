//
//  MainTableView.swift
//

import SwiftUI
import AppKit

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    // UI State
    @State private var showInspector = true
    @State private var customIntervalText = ""
    @State private var showingCustomIntervalAlert = false
    
    // Resizable Panels State
    @State private var inspectorBaseWidth: CGFloat = 300
    @State private var inspectorDragOffset: CGFloat = 0
    
    // Высота нижней панели (увеличена по умолчанию)
    @State private var bottomPanelBaseHeight: CGFloat = 350
    @State private var bottomPanelDragOffset: CGFloat = 0
    @State private var selectedBottomTab: Int = 0
    
    // Вычисляемые размеры с ограничениями (min/max)
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
                customIntervalText: $customIntervalText,
                showingCustomIntervalAlert: $showingCustomIntervalAlert
            )
            
            // 2. CONTENT AREA
            // GeometryReader используется один раз для контекста
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
                        
                        // Меню вкладок (Спектр / История) - Центрированное
                        BottomPanelTabs(selectedTab: $selectedBottomTab)
                        
                        Divider()
                        
                        // Контент графиков
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
        // Алерт для ввода кастомного интервала
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
        // Запрос прав при появлении
        .onAppear {
            if !viewModel.isLocationAuthorized {
                viewModel.requestLocationAuthorization()
            }
        }
    }
}

// MARK: - Components

/// Нижняя панель с вкладками, выровненными по центру
struct BottomPanelTabs: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Spacer слева для центрирования
            Spacer()
            
            TabButton(
                title: "Спектр",
                icon: "waveform.path.ecg",
                isSelected: selectedTab == 0,
                action: { selectedTab = 0 }
            )
            
            Divider().frame(height: 16)
            
            TabButton(
                title: "История",
                icon: "clock.arrow.circlepath",
                isSelected: selectedTab == 1,
                action: { selectedTab = 1 }
            )
            
            // Spacer справа для центрирования
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

/// Тулбар с унифицированными кнопками настроек
struct ToolbarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Binding var showInspector: Bool
    @Binding var customIntervalText: String
    @Binding var showingCustomIntervalAlert: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            
            // 1. LEFT CONTROLS (Refresh & Settings)
            HStack(spacing: 10) {
                // A. Кнопка Обновить
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Now")
                .buttonStyle(.borderless)
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                // B. Меню Настроек (Шестеренка) - унифицированный стиль
                Menu {
                    // Секция 1: Мониторинг
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
                        Button("Custom Interval...") {
                            customIntervalText = String(Int(viewModel.refreshInterval))
                            showingCustomIntervalAlert = true
                        }
                    } header: { Text("Monitoring") }
                    
                    Divider()
                    
                    // Секция 2: Фильтры (слайдер сигнала)
                    Section {
                        Text("Min Signal: \(Int(viewModel.minSignalThreshold)) dBm")
                        Slider(value: $viewModel.minSignalThreshold, in: -100...(-30)) {
                            Text("Threshold")
                        }
                    } header: { Text("Filters") }
                    
                    Divider()
                    
                    // Секция 3: Отображение
                    Section {
                        Picker("Remove inactive after:", selection: $viewModel.removeAfterInterval) {
                            ForEach(NetworkRemovalInterval.allCases) { Text($0.title).tag($0) }
                        }
                        
                        Picker("Signal Unit:", selection: $viewModel.signalDisplayMode) {
                            ForEach(SignalDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } header: { Text("Display") }
                    
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .help("Settings & Monitoring Control")
            }
            
            // 2. Band Filters
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
            
            // 4. Right Controls
            HStack(spacing: 16) {
                
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

// MARK: - Subviews

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
                                
                                // Безопасное разворачивание
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

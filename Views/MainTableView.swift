import SwiftUI
import Charts

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    @State private var showingColumnMenu = false
    @State private var showInspector = true
    @State private var customIntervalText = ""
    @State private var showingCustomIntervalAlert = false
    
    @State private var inspectorBaseWidth: CGFloat = 320
    @State private var inspectorDragOffset: CGFloat = 0
    @State private var bottomPanelBaseHeight: CGFloat = 280
    @State private var bottomPanelDragOffset: CGFloat = 0
    @State private var selectedBottomTab: Int = 0
    
    var currentInspectorWidth: CGFloat {
        max(250, min(600, inspectorBaseWidth - inspectorDragOffset))
    }
    
    var currentBottomPanelHeight: CGFloat {
        max(150, min(600, bottomPanelBaseHeight - bottomPanelDragOffset))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 1. TOOLBAR
            toolbarView
            
            // 2. MAIN CONTENT (VStack для разделения Таблицы+Инспектора и Нижней Панели)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    
                    // A. Верхняя секция: Таблица (слева) + Инспектор (справа)
                    HStack(spacing: 0) {
                        
                        // Таблица (занимает все свободное место)
                        VStack(spacing: 0) {
                            if let err = viewModel.errorMessage {
                                ErrorBanner(message: err, onClose: { viewModel.errorMessage = nil })
                            }
                            WiFiTableView(viewModel: viewModel)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Инспектор (фиксированная ширина, справа)
                        if showInspector {
                            // Разделитель Инспектора
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                                .overlay(
                                    Rectangle().fill(Color.clear).frame(width: 9).contentShape(Rectangle())
                                        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
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
                    // Верхняя секция занимает все место минус высота нижней панели
                    
                    // B. Нижняя секция: Графики (на всю ширину)
                    
                    // Разделитель Нижней Панели
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .overlay(
                            Rectangle().fill(Color.clear).frame(height: 9).contentShape(Rectangle())
                                .onHover { inside in if inside { NSCursor.resizeUp.push() } else { NSCursor.pop() } }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Тянем вверх -> высота увеличивается (инверсия Y)
                                    self.bottomPanelDragOffset = value.translation.height
                                }
                                .onEnded { _ in
                                    self.bottomPanelBaseHeight = self.currentBottomPanelHeight
                                    self.bottomPanelDragOffset = 0
                                }
                        )
                        .zIndex(20)
                    
                    // Контент Панели
                    ZStack {
                        Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
                        if selectedBottomTab == 0 {
                            SpectrumView(viewModel: viewModel)
                        } else {
                            SignalHistoryView(viewModel: viewModel)
                        }
                    }
                    .frame(height: currentBottomPanelHeight)
                    .clipped()
                }
            }
        }
        // АВТО-ЗАПРОС ПРАВ ПРИ ЗАПУСКЕ
        .onAppear {
            if viewModel.locationManager.authorizationStatus == .notDetermined {
                viewModel.locationManager.requestAuthorization()
            }
        }
        .sheet(isPresented: $showingColumnMenu) {
            ColumnSettingsView(viewModel: viewModel)
        }
        .alert("Настройка интервала", isPresented: $showingCustomIntervalAlert) {
            TextField("Сек", text: $customIntervalText)
            Button("OK") {
                if let val = Double(customIntervalText), val > 0 { viewModel.updateRefreshInterval(to: val) }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Введите время обновления в секундах:")
        }
    }
    
    // Вынес тулбар отдельно
    var toolbarView: some View {
        HStack(spacing: 12) {
            // Scan Controls
            HStack(spacing: 0) {
                Button(action: { viewModel.refresh() }) { Image(systemName: "arrow.clockwise").frame(height: 18) }
                    .help("Обновить").buttonStyle(.borderless).padding(.horizontal, 8)
                Divider().frame(height: 16)
                Menu {
                    Picker("Interval", selection: Binding(
                        get: { viewModel.refreshInterval },
                        set: { viewModel.updateRefreshInterval(to: $0) }
                    )) {
                        Text("1s").tag(1.0); Text("2s").tag(2.0); Text("5s").tag(5.0); Text("10s").tag(10.0); Text("30s").tag(30.0)
                    }
                    Divider()
                    Button("Custom...") { customIntervalText = String(Int(viewModel.refreshInterval)); showingCustomIntervalAlert = true }
                } label: {
                    HStack(spacing: 2) { Image(systemName: "timer"); Text("\(Int(viewModel.refreshInterval))s").font(.caption).monospacedDigit() }
                }.menuStyle(.borderlessButton).frame(width: 65)
            }
            .padding(4).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            // Filters
            HStack(spacing: 0) {
                Toggle("2.4", isOn: $viewModel.filterBand24); Divider().frame(height: 12).padding(.horizontal, 4)
                Toggle("5", isOn: $viewModel.filterBand5); Divider().frame(height: 12).padding(.horizontal, 4)
                Toggle("6", isOn: $viewModel.filterBand6)
            }
            .toggleStyle(.button).controlSize(.small)
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Поиск...", text: $viewModel.searchText).textFieldStyle(.plain).frame(minWidth: 100, maxWidth: 200)
            }
            .padding(5).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
            
            // Signal Filter
            Menu {
                Text("Скрыть сигналы слабее:")
                Slider(value: $viewModel.minSignalThreshold, in: -100...(-30)) { Text("Min RSSI") }.frame(width: 150)
                Text("\(Int(viewModel.minSignalThreshold)) dBm").font(.caption)
            } label: { Image(systemName: "speaker.wave.1.fill") }
            .menuStyle(.borderlessButton).help("Фильтр по уровню сигнала")
            
            Spacer()
            
            // Settings
            Menu {
                Picker("Удалять старые сети:", selection: $viewModel.removeAfterInterval) {
                    ForEach(NetworkRemovalInterval.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Picker("Единицы сигнала:", selection: $viewModel.signalDisplayMode) {
                    ForEach(SignalDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Image(systemName: "gearshape").foregroundColor(.primary) }
            .menuStyle(.borderlessButton)
            
            // Bottom Tabs
            Picker("", selection: $selectedBottomTab) {
                Image(systemName: "waveform.path.ecg").tag(0).help("Спектр")
                Image(systemName: "clock.arrow.circlepath").tag(1).help("История")
            }
            .pickerStyle(.segmented).frame(width: 80)
            
            // Controls
            Group {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInspector.toggle() } }) {
                    Image(systemName: "sidebar.right").foregroundColor(showInspector ? .accentColor : .primary)
                }
                Button(action: { showingColumnMenu.toggle() }) { Image(systemName: "tablecells") }
                Button(action: { viewModel.exportCSV() }) { Image(systemName: "square.and.arrow.up") }
                
                if !viewModel.isLocationAuthorized {
                    Button(action: {
                        if viewModel.locationManager.authorizationStatus == .notDetermined {
                            viewModel.locationManager.requestAuthorization()
                        } else {
                            viewModel.locationManager.openSystemSettings()
                        }
                    }) {
                        Image(systemName: "location.slash.fill").foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Требуется доступ к геолокации")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(10).background(Material.bar)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
    }
}

// ... Subviews остаются теми же ...
struct ErrorBanner: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.callout).foregroundColor(.primary)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
        .padding(8).background(Color.yellow.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
    }
}

struct ColumnSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Настройка столбцов").font(.headline); Spacer(); Button("Готово") { dismiss() }.buttonStyle(.borderedProminent) }
                .padding().background(Material.regular)
            Divider()
            HStack { Image(systemName: "magnifyingglass").foregroundColor(.secondary); TextField("Поиск...", text: $searchText).textFieldStyle(.plain) }
                .padding(8).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8).padding(10)
            List {
                ForEach(filteredColumns) { col in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 20)
                        Toggle(isOn: Binding(get: { col.isVisible }, set: { _ in viewModel.toggleColumn(col.id) })) { Text(col.title).font(.body) }.toggleStyle(.switch)
                    }
                    .padding(.vertical, 2)
                }.onMove(perform: moveColumns)
            }.listStyle(.inset)
            Divider()
            HStack {
                Button(action: { withAnimation { viewModel.resetColumnsToDefault() } }) { Label("Сбросить", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).foregroundColor(.red)
                Spacer()
                Text("Перетащите для изменения порядка").font(.caption).foregroundStyle(.secondary)
            }.padding().background(Material.bar)
        }.frame(width: 400, height: 600)
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
            if let originalIndex = viewModel.columnDefinitions.firstIndex(where: { $0.id == col.id }) { viewModel.columnDefinitions[originalIndex].order = index }
        }
        viewModel.saveColumnSettings(); viewModel.objectWillChange.send()
    }
}

struct NetworkInspectorView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Inspector").font(.headline); Spacer() }.padding().background(Material.bar); Divider()
            ScrollView {
                if let network = viewModel.selectedNetwork {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(network.ssid.isEmpty ? "<Hidden>" : network.ssid).font(.title2).bold()
                                    .foregroundColor(network.bssid == viewModel.currentConnectedBSSID ? .accentColor : .primary).lineLimit(2)
                                HStack {
                                    Text(network.bssid).font(.caption).monospaced().padding(4).background(Color.gray.opacity(0.1)).cornerRadius(4).textSelection(.enabled)
                                    if network.bssid == viewModel.currentConnectedBSSID { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).help("Connected") }
                                }
                            }
                            Spacer()
                            SignalBadge(rssi: network.signal, label: viewModel.formatSignal(network.signal), unit: viewModel.signalDisplayMode == .dbm ? "dBm" : "")
                        }
                        GroupBox("Technical Details") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                DetailRow(label: "Channel", value: "\(network.channel)"); DetailRow(label: "Band", value: network.band)
                                DetailRow(label: "Width", value: network.channelWidth); DetailRow(label: "Generation", value: network.generation)
                                DetailRow(label: "Max Rate", value: "\(Int(network.maxRate)) Mbps"); DetailRow(label: "Vendor", value: network.vendor)
                            }
                        }
                        GroupBox("Security") {
                            VStack(alignment: .leading, spacing: 8) {
                                DetailRow(label: "Protocol", value: network.security); DetailRow(label: "WPS", value: network.wps ?? "No")
                                if let cc = network.countryCode { DetailRow(label: "Country Code", value: cc) }
                            }
                        }
                    }.padding()
                } else {
                    VStack(spacing: 16) { Spacer(); Image(systemName: "wifi.circle").font(.system(size: 64)).foregroundColor(.secondary.opacity(0.2)); Text("Select a network").foregroundColor(.secondary); Spacer() }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct SignalBadge: View {
    let rssi: Int; let label: String; let unit: String
    var color: Color { if rssi > -50 { return .green } else if rssi > -70 { return .yellow } else { return .red } }
    var body: some View { VStack { Text(label).font(.title3).bold().foregroundColor(color); if !unit.isEmpty { Text(unit).font(.caption2).foregroundColor(.secondary) } }.padding(8).background(color.opacity(0.1)).cornerRadius(8) }
}

struct DetailRow: View {
    let label: String; let value: String
    var body: some View { VStack(alignment: .leading) { Text(label).font(.caption).foregroundColor(.secondary); Text(value).font(.subheadline) } }
}

//  WiFiTableView.swift

import SwiftUI
import AppKit

// MARK: - 1. Custom Cell Class (Выделение UI ячейки)
/// Выносим логику создания UI и констрейнтов из Coordinator.
/// Это повышает производительность, так как констрейнты создаются 1 раз при инициализации.
final class WiFiTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WiFiTextCell")
    
    private let textFieldLabel: NSTextField = {
        let tf = NSTextField()
        tf.isEditable = false
        tf.isBordered = false
        tf.drawsBackground = false
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        // Добавляем textField
        addSubview(textFieldLabel)
        self.textField = textFieldLabel
        
        // Static Constraints (Создаются один раз)
        NSLayoutConstraint.activate([
            textFieldLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textFieldLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            textFieldLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])
    }
    
    func configure(text: String, isConnected: Bool) {
        textFieldLabel.stringValue = text
        textFieldLabel.toolTip = text
        
        if isConnected {
            textFieldLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            textFieldLabel.textColor = NSColor.systemBlue
        } else {
            textFieldLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textFieldLabel.textColor = NSColor.labelColor
        }
    }
}

// MARK: - 2. Typed Identifiers (Modern AppKit)
extension NSUserInterfaceItemIdentifier {
    static let bssid = NSUserInterfaceItemIdentifier("bssid")
    // Остальные создаются динамически из ID колонок, но базу можно типизировать
}

struct WiFiTableView: NSViewRepresentable {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing // Важно для ручного ресайза
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        
        tableView.headerView = NSTableHeaderView()
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        
        // Меню
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Копировать SSID", action: #selector(Coordinator.copySSID), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Копировать BSSID", action: #selector(Coordinator.copyBSSID), keyEquivalent: ""))
        tableView.menu = menu
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        context.coordinator.tableView = tableView
        
        // Наблюдатели за изменениями пользователем (Reorder / Resize)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnDidMove(_:)),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        // --- 3. Умное обновление колонок (Diffing) ---
        // Сравниваем конфигурацию без генерации длинной строки-сигнатуры.
        
        let targetDefinitions = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        let targetVisibleDefinitions = targetDefinitions.filter { $0.isVisible }
        
        // Флаг для блокировки обратных нотификаций во время программного изменения
        context.coordinator.isProgrammaticUpdate = true
        
        // A. Синхронизация списка колонок (Add / Remove)
        let currentColumnIdentifiers = Set(tableView.tableColumns.map { $0.identifier.rawValue })
        let targetIdentifiers = Set(targetVisibleDefinitions.map { $0.id })
        
        // Remove: Убираем колонки, которых нет в target (или стали скрытыми)
        let toRemove = currentColumnIdentifiers.subtracting(targetIdentifiers)
        for id in toRemove {
            if let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) {
                tableView.removeTableColumn(col)
            }
        }
        
        // Add/Update: Добавляем новые или обновляем существующие
        for def in targetVisibleDefinitions {
            let id = NSUserInterfaceItemIdentifier(def.id)
            let column: NSTableColumn
            
            if let existing = tableView.tableColumn(withIdentifier: id) {
                column = existing
            } else {
                column = NSTableColumn(identifier: id)
                column.minWidth = 50
                // Добавляем в конец, порядок исправим ниже
                tableView.addTableColumn(column)
            }
            
            // Обновляем свойства (только если изменились, чтобы не дергать UI)
            if column.title != def.title { column.title = def.title }
            if abs(column.width - def.width) > 1.0 { column.width = def.width }
            
            // Сортировка дескриптора
            if column.sortDescriptorPrototype?.key != def.id {
                column.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
            }
        }
        
        // B. Синхронизация порядка (Reorder)
        // Проходим по целевому списку и перемещаем колонки на нужные позиции
        let currentColumns = tableView.tableColumns
        for (targetIndex, def) in targetVisibleDefinitions.enumerated() {
            let id = NSUserInterfaceItemIdentifier(def.id)
            // Ищем текущий индекс этой колонки в таблице
            if let currentIndex = currentColumns.firstIndex(where: { $0.identifier == id }) {
                if currentIndex != targetIndex {
                    tableView.moveColumn(currentIndex, toColumn: targetIndex)
                }
            }
        }
        
        context.coordinator.isProgrammaticUpdate = false
        
        // Обновление индикатора сортировки
        if let sortKey = viewModel.currentSortKey {
            let descriptor = NSSortDescriptor(key: sortKey, ascending: viewModel.isSortAscending)
            if tableView.sortDescriptors.first != descriptor {
                tableView.sortDescriptors = [descriptor]
            }
        }
        
        // Перезагрузка данных (Сигнал, новые сети)
        // reloadData сбрасывает выделение, поэтому восстанавливаем его ниже
        tableView.reloadData()
        
        // --- 4. Безопасная синхронизация выделения (Safe Selection Sync) ---
        restoreSelection(in: tableView, coordinator: context.coordinator)
    }
    
    /// Восстановление выделения по BSSID (Улучшение UX)
    private func restoreSelection(in tableView: NSTableView, coordinator: Coordinator) {
        guard let selectedBSSID = viewModel.selectedBSSID else {
            if tableView.selectedRow >= 0 {
                coordinator.isUpdatingSelection = true
                tableView.deselectAll(nil)
                coordinator.isUpdatingSelection = false
            }
            return
        }
        
        // Находим индекс строки для сохраненного BSSID
        if let index = viewModel.networks.firstIndex(where: { $0.bssid == selectedBSSID }) {
            if tableView.selectedRow != index {
                coordinator.isUpdatingSelection = true // Блокируем цикл обновлений
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                tableView.scrollRowToVisible(index) // Скроллим к выбранному
                coordinator.isUpdatingSelection = false
            }
        } else {
            // Сеть исчезла (фильтр или выход из зоны), снимаем выделение
            if tableView.selectedRow >= 0 {
                coordinator.isUpdatingSelection = true
                tableView.deselectAll(nil)
                coordinator.isUpdatingSelection = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: WiFiTableView
        weak var tableView: NSTableView?
        
        // Флаги для разрыва циклов обновлений
        var isProgrammaticUpdate = false
        var isUpdatingSelection = false
        
        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
        }()
        
        init(_ parent: WiFiTableView) {
            self.parent = parent
        }
        
        // MARK: DataSource
        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.viewModel.networks.count
        }
        
        // MARK: View For Column (Правильный Reuse)
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, row < parent.viewModel.networks.count else { return nil }
            
            let network = parent.viewModel.networks[row]
            let colId = column.identifier.rawValue
            
            // 1. Получаем типизированную ячейку через Identifier
            var cellView = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView
            
            // 2. Если нет в пуле реюза, создаем новую (логика init внутри класса ячейки)
            if cellView == nil {
                cellView = WiFiTableCellView()
                cellView?.identifier = WiFiTableCellView.identifier
            }
            
            // 3. Конфигурируем (данные + стиль)
            let text = getText(for: colId, network: network)
            let isConnected = (network.bssid == parent.viewModel.currentConnectedBSSID)
            
            cellView?.configure(text: text, isConnected: isConnected)
            
            return cellView
        }
        
        // MARK: - Selection Handling
         func tableViewSelectionDidChange(_ notification: Notification) {
             guard !isUpdatingSelection, let tableView = notification.object as? NSTableView else { return }
             
             let row = tableView.selectedRow
             
             // ВАЖНО: Выносим обновление ViewModel из цикла отрисовки
             DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 
                 if row >= 0, row < self.parent.viewModel.networks.count {
                     let net = self.parent.viewModel.networks[row]
                     // Проверка на изменение, чтобы не спамить обновлениями
                     if self.parent.viewModel.selectedBSSID != net.bssid {
                         self.parent.viewModel.selectedBSSID = net.bssid
                     }
                 } else {
                     if self.parent.viewModel.selectedBSSID != nil {
                         self.parent.viewModel.selectedBSSID = nil
                     }
                 }
             }
         }
        
        // MARK: Sorting
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sd = tableView.sortDescriptors.first, let key = sd.key else { return }
            parent.viewModel.sort(by: key, ascending: sd.ascending)
            // reloadData вызовется в updateNSView при обновлении state viewModel
        }
        
        // MARK: - Column Sync
                @objc func columnDidMove(_ notification: Notification) {
                    guard !isProgrammaticUpdate, let tableView = notification.object as? NSTableView else { return }
                    
                    // Собираем данные синхронно
                    let newOrderMap = tableView.tableColumns.enumerated().map { (offset, col) in
                        (id: col.identifier.rawValue, index: offset)
                    }
                    
                    // Обновляем ViewModel асинхронно
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        for item in newOrderMap {
                            if let idx = self.parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == item.id }) {
                                self.parent.viewModel.columnDefinitions[idx].order = item.index
                            }
                        }
                        self.parent.viewModel.saveColumnSettings()
                    }
                }
                
                @objc func columnDidResize(_ notification: Notification) {
                    guard !isProgrammaticUpdate, let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
                    
                    let id = col.identifier.rawValue
                    let width = col.width
                    
                    // Обновляем ViewModel асинхронно
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if let idx = self.parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                            self.parent.viewModel.columnDefinitions[idx].width = width
                            self.parent.viewModel.saveColumnSettings()
                        }
                    }
                }
        
        // MARK: Helpers & Menu
        @objc func copySSID() {
            copyToClipboard(keyPath: \.ssid)
        }
        
        @objc func copyBSSID() {
            copyToClipboard(keyPath: \.bssid)
        }
        
        private func copyToClipboard(keyPath: KeyPath<NetworkModel, String>) {
            guard let row = tableView?.clickedRow, row >= 0 else { return }
            let net = parent.viewModel.networks[row]
            let string = net[keyPath: keyPath]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
        
        private func getText(for identifier: String, network: NetworkModel) -> String {
            switch identifier {
            case "bssid": return network.bssid
            case "ssid": return network.ssid.isEmpty ? "<Hidden>" : network.ssid
            case "signal": return parent.viewModel.formatSignal(network.signal)
            case "channel": return "\(network.channel)"
            case "band": return network.band
            case "security": return network.security
            case "vendor": return network.vendor
            case "width": return network.channelWidth
            case "maxRate": return String(format: "%.0f", network.maxRate)
            case "mode": return network.mode
            case "generation": return network.generation
            case "firstSeen": return network.firstSeen.map { Coordinator.dateFormatter.string(from: $0) } ?? "-"
            case "lastSeen": return network.lastSeen.map { Coordinator.dateFormatter.string(from: $0) } ?? "-"
            case "wps": return network.wps ?? "-"
            default: return "-"
            }
        }
    }
}

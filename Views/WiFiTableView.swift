import SwiftUI
import AppKit

struct WiFiTableView: NSViewRepresentable {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        
        // Настройка заголовка
        tableView.headerView = NSTableHeaderView()
        
        // Включаем выбор
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        
        // Меню
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Копировать SSID", action: #selector(Coordinator.copySSID), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Копировать BSSID", action: #selector(Coordinator.copyBSSID), keyEquivalent: ""))
        tableView.menu = menu
        
        // Создаем колонки
        let sortedColumns = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        sortedColumns.forEach { colDef in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colDef.id))
            column.title = colDef.title
            column.isEditable = false
            column.width = CGFloat(colDef.width)
            column.isHidden = !colDef.isVisible
            column.minWidth = 60
            column.maxWidth = 1000
            column.sortDescriptorPrototype = NSSortDescriptor(key: colDef.id, ascending: true)
            tableView.addTableColumn(column)
        }
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        context.coordinator.tableView = tableView
        context.coordinator.parent = self
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.columnDidMove(_:)),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        // Сохраняем позицию скролла
        let clipView = nsView.contentView
        let oldOrigin = clipView.bounds.origin
        
        let target = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        // В сигнатуру добавляем кол-во сетей, чтобы перезагружать при добавлении/удалении
        let signature = target.map { "\($0.id)|\($0.isVisible ? 1 : 0)|\(Int($0.width))|\($0.order)" }.joined(separator: ",") + "|\(viewModel.currentSortKey ?? "")|\(viewModel.isSortAscending)|\(viewModel.signalDisplayMode.rawValue)|\(viewModel.networks.count)"
        
        // --- Логика обновления структуры колонок ---
        if context.coordinator.lastAppliedColumnsSignature != signature {
            context.coordinator.isProgrammaticColumnChange = true
            
            // 1. Удаление лишних
            let targetIDs = Set(target.map { $0.id })
            for column in tableView.tableColumns {
                if !targetIDs.contains(column.identifier.rawValue) {
                    tableView.removeTableColumn(column)
                }
            }
            
            // 2. Добавление/Обновление
            for def in target {
                let id = NSUserInterfaceItemIdentifier(def.id)
                if let col = tableView.tableColumn(withIdentifier: id) {
                    if col.isHidden != !def.isVisible { col.isHidden = !def.isVisible }
                    if abs(col.width - def.width) > 1.0 { col.width = def.width }
                    col.title = def.title
                    col.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
                } else {
                    let col = NSTableColumn(identifier: id)
                    col.title = def.title
                    col.width = def.width
                    col.isHidden = !def.isVisible
                    col.minWidth = 50
                    col.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
                    tableView.addTableColumn(col)
                }
            }
            
            // 3. Порядок
            for (targetIndex, def) in target.enumerated() {
                let id = NSUserInterfaceItemIdentifier(def.id)
                if let currentIndex = tableView.tableColumns.firstIndex(where: { $0.identifier == id }) {
                    if currentIndex != targetIndex {
                        tableView.moveColumn(currentIndex, toColumn: targetIndex)
                    }
                }
            }
            
            context.coordinator.isProgrammaticColumnChange = false
            context.coordinator.lastAppliedColumnsSignature = signature
            
            // Перезагрузка данных (при смене структуры)
            tableView.reloadData()
            context.coordinator.updateSortIndicators()
        } else {
            // Если структура не менялась, просто обновляем ячейки
            // Note: reloadData() необходим для обновления значений (сигнала),
            // но он сбрасывает выделение, которое мы восстановим ниже.
            tableView.reloadData()
        }
        
        // --- СИНХРОНИЗАЦИЯ ВЫДЕЛЕНИЯ (В обе стороны) ---
        // Это должно выполняться ВСЕГДА после reloadData
        
        if let selectedBSSID = viewModel.selectedBSSID {
            // Если во ViewModel есть выбор, синхронизируем таблицу
            if let index = viewModel.networks.firstIndex(where: { $0.bssid == selectedBSSID }) {
                if tableView.selectedRow != index {
                    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    tableView.scrollRowToVisible(index) // Опционально: скролл к выбранному
                }
            } else {
                // Сеть пропала из списка (удалили) -> снимаем выделение
                if tableView.selectedRow >= 0 {
                    tableView.deselectAll(nil)
                }
            }
        } else {
            // Если во ViewModel пусто, снимаем выделение в таблице
            if tableView.selectedRow >= 0 {
                tableView.deselectAll(nil)
            }
        }
        
        // Восстановление скролла (если не скроллили к выбору)
        if clipView.bounds.origin != oldOrigin {
            // clipView.scroll(to: oldOrigin) // Можно раскомментировать, если scrollRowToVisible мешает
            // nsView.reflectScrolledClipView(clipView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: WiFiTableView
        weak var tableView: NSTableView?
        var isProgrammaticColumnChange = false
        var lastAppliedColumnsSignature: String?
        
        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
        }()
        
        init(_ parent: WiFiTableView) {
            self.parent = parent
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.viewModel.networks.count
        }
        
        // MARK: - View For Cell (Исправлено выравнивание)
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, row < parent.viewModel.networks.count else { return nil }
            let network = parent.viewModel.networks[row]
            let id = column.identifier.rawValue
            
            let isConnected = (network.bssid == parent.viewModel.currentConnectedBSSID)
            let cellIdentifier = NSUserInterfaceItemIdentifier(id)
            
            // 1. Создаем или переиспользуем NSTableCellView (контейнер)
            var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = cellIdentifier
                
                // 2. Создаем NSTextField
                let textField = NSTextField()
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.identifier = NSUserInterfaceItemIdentifier("TextCell")
                textField.translatesAutoresizingMaskIntoConstraints = false
                
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                // 3. Добавляем Constraints для центрирования по вертикали
                NSLayoutConstraint.activate([
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2)
                ])
            }
            
            // 4. Наполняем данными
            if let textField = cellView?.textField {
                textField.stringValue = getText(for: id, network: network)
                textField.toolTip = textField.stringValue
                
                if isConnected {
                    textField.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    textField.textColor = NSColor.systemBlue
                } else {
                    textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    textField.textColor = NSColor.labelColor
                }
            }
            
            return cellView
        }
        
        // MARK: - Selection Handling
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            
            // Обновляем ViewModel асинхронно, чтобы не блокировать UI
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if row >= 0, row < self.parent.viewModel.networks.count {
                    let net = self.parent.viewModel.networks[row]
                    // Только если реально изменилось
                    if self.parent.viewModel.selectedBSSID != net.bssid {
                        self.parent.viewModel.selectedBSSID = net.bssid
                    }
                } else {
                    // Если сняли выделение (cmd+click)
                    if self.parent.viewModel.selectedBSSID != nil {
                        self.parent.viewModel.selectedBSSID = nil
                    }
                }
            }
        }
        
        @objc func copySSID() {
            guard let row = tableView?.clickedRow, row >= 0 else { return }
            let net = parent.viewModel.networks[row]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(net.ssid, forType: .string)
        }
        
        @objc func copyBSSID() {
            guard let row = tableView?.clickedRow, row >= 0 else { return }
            let net = parent.viewModel.networks[row]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(net.bssid, forType: .string)
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
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sd = tableView.sortDescriptors.first, let key = sd.key else { return }
            parent.viewModel.sort(by: key, ascending: sd.ascending)
            tableView.reloadData()
        }
        
        @MainActor func updateSortIndicators() {
            guard let tableView = tableView, let key = parent.viewModel.currentSortKey else { return }
            let descriptor = NSSortDescriptor(key: key, ascending: parent.viewModel.isSortAscending)
            if tableView.sortDescriptors.first?.key != key || tableView.sortDescriptors.first?.ascending != parent.viewModel.isSortAscending {
                tableView.sortDescriptors = [descriptor]
            }
        }
        
        @objc func columnDidMove(_ notification: Notification) {
            guard !isProgrammaticColumnChange, let tableView = notification.object as? NSTableView else { return }
            let newOrder = tableView.tableColumns.enumerated().map { ($0.element.identifier.rawValue, $0.offset) }
            Task { @MainActor in
                for (id, idx) in newOrder {
                    if let modelIdx = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                        parent.viewModel.columnDefinitions[modelIdx].order = idx
                    }
                }
                parent.viewModel.saveColumnSettings()
                self.forceUpdateSignature()
            }
        }
        
        func tableViewColumnDidResize(_ notification: Notification) {
            guard !isProgrammaticColumnChange, let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
            let id = col.identifier.rawValue
            let width = col.width
            Task { @MainActor in
                if let idx = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                    parent.viewModel.columnDefinitions[idx].width = width
                    parent.viewModel.saveColumnSettings()
                    self.forceUpdateSignature()
                }
            }
        }
        
        @MainActor private func forceUpdateSignature() {
            let target = parent.viewModel.columnDefinitions.sorted { $0.order < $1.order }
            self.lastAppliedColumnsSignature = target.map { "\($0.id)|\($0.isVisible ? 1 : 0)|\(Int($0.width))|\($0.order)" }.joined(separator: ",") + "|\(parent.viewModel.currentSortKey ?? "")|\(parent.viewModel.isSortAscending)|\(parent.viewModel.signalDisplayMode.rawValue)|\(parent.viewModel.networks.count)"
        }
    }
}

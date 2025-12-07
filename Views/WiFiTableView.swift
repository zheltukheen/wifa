import SwiftUI
import AppKit

struct WiFiTableView: NSViewRepresentable {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // Скрываем скроллбары, показываем только при реальном скролле
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.headerView = NSTableHeaderView()
        
        // Настройка столбцов в правильном порядке
        let sortedColumns = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        sortedColumns.forEach { colDef in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colDef.id))
            column.title = colDef.title
            column.isEditable = false
            column.width = colDef.width
            column.isHidden = !colDef.isVisible
            column.minWidth = 50
            column.maxWidth = 500
            // Включаем сортировку по клику на заголовок
            column.sortDescriptorPrototype = NSSortDescriptor(key: colDef.id, ascending: true)
            tableView.addTableColumn(column)
        }
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.parent = self
        
        // Отслеживаем изменения порядка столбцов
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
        
        // Сохраняем текущую позицию скролла, чтобы не перебрасывало в начало
        let clipView = nsView.contentView
        let oldOrigin = clipView.bounds.origin
        
        // Подготовим целевую конфигурацию столбцов
        let target = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        let signature = target.map { "\($0.id)|\($0.isVisible ? 1 : 0)|\(Int($0.width))|\($0.order)" }.joined(separator: ",")
        
        // Если конфигурация не поменялась — просто обновим данные и выйдем
        if context.coordinator.lastAppliedColumnsSignature == signature {
            tableView.reloadData()
            context.coordinator.updateSortIndicators()
            clipView.scroll(to: oldOrigin)
            nsView.reflectScrolledClipView(clipView)
            return
        }
        
        // Иначе — диффим столбцы, не пересоздавая их целиком
        context.coordinator.isProgrammaticColumnChange = true
        defer {
            context.coordinator.isProgrammaticColumnChange = false
            context.coordinator.lastAppliedColumnsSignature = signature
        }
        
        // 1) Удаляем лишние столбцы
        let targetIDs = Set(target.map { $0.id })
        for column in tableView.tableColumns where !targetIDs.contains(column.identifier.rawValue) {
            tableView.removeTableColumn(column)
        }
        
        // 2) Добавляем недостающие столбцы и обновляем свойства существующих
        for def in target {
            if let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == def.id }) {
                // Обновляем свойства
                col.title = def.title
                col.isHidden = !def.isVisible
                if abs(col.width - def.width) > 0.5 { col.width = def.width }
                col.minWidth = 50
                col.maxWidth = 500
                col.isEditable = false
                col.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
            } else {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(def.id))
                col.title = def.title
                col.isEditable = false
                col.width = def.width
                col.isHidden = !def.isVisible
                col.minWidth = 50
                col.maxWidth = 500
                col.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
                tableView.addTableColumn(col)
            }
        }
        
        // 3) Приводим порядок столбцов к целевому через moveColumn
        for (targetIndex, def) in target.enumerated() {
            if let currentIndex = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == def.id }),
               currentIndex != targetIndex {
                tableView.moveColumn(currentIndex, toColumn: targetIndex)
            }
        }
        
        tableView.reloadData()
        context.coordinator.updateSortIndicators()
        
        // Восстанавливаем позицию скролла (горизонтальную и вертикальную)
        clipView.scroll(to: oldOrigin)
        nsView.reflectScrolledClipView(clipView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: WiFiTableView
        var tableView: NSTableView?
        var scrollView: NSScrollView?
        
        // Флаг, чтобы игнорировать уведомления о перемещении столбцов во время программных изменений
        var isProgrammaticColumnChange = false
        // Сигнатура последней применённой конфигурации столбцов, чтобы избежать лишних перерисовок
        var lastAppliedColumnsSignature: String?
        
        init(_ parent: WiFiTableView) {
            self.parent = parent
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.viewModel.networks.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn,
                  row < parent.viewModel.networks.count else { return nil }
            
            let network = parent.viewModel.networks[row]
            let identifier = column.identifier.rawValue
            
            let textField = NSTextField()
            textField.isEditable = false
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.drawsBackground = false
            
            switch identifier {
            case "bssid":
                textField.stringValue = network.bssid.isEmpty ? "-" : network.bssid
            case "band":
                textField.stringValue = network.band
            case "channel":
                textField.stringValue = network.channel == 0 ? "-" : "\(network.channel)"
            case "channelWidth":
                textField.stringValue = network.channelWidth
            case "generation":
                textField.stringValue = network.generation
            case "maxRate":
                textField.stringValue = String(format: "%.0f", network.maxRate)
            case "mode":
                textField.stringValue = network.mode
            case "ssid":
                textField.stringValue = network.ssid.isEmpty ? "-" : network.ssid
            case "security":
                textField.stringValue = network.security
            case "seen":
                textField.stringValue = "\(network.seen)"
            case "signal":
                textField.stringValue = "\(network.signal)"
            case "vendor":
                textField.stringValue = network.vendor
            case "basicRates":
                if let rates = network.basicRates, !rates.isEmpty {
                    textField.stringValue = rates.map { String(format: "%.0f", $0) }.joined(separator: ", ")
                } else {
                    textField.stringValue = "-"
                }
            case "beaconInterval":
                textField.stringValue = network.beaconInterval.map { "\($0)" } ?? "-"
            case "centerFrequency":
                textField.stringValue = network.centerFrequency.map { "\($0)" } ?? "-"
            case "channelUtilization":
                textField.stringValue = network.channelUtilization.map { "\($0)" } ?? "-"
            case "countryCode":
                textField.stringValue = network.countryCode ?? "-"
            case "deviceName":
                textField.stringValue = network.deviceName ?? "-"
            case "fastTransition":
                textField.stringValue = network.fastTransition.map { $0 ? "Yes" : "No" } ?? "-"
            case "firstSeen":
                if let date = network.firstSeen {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    textField.stringValue = formatter.string(from: date)
                } else {
                    textField.stringValue = "-"
                }
            case "lastSeen":
                if let date = network.lastSeen {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    textField.stringValue = formatter.string(from: date)
                } else {
                    textField.stringValue = "-"
                }
            case "minRate":
                textField.stringValue = network.minRate.map { String(format: "%.0f", $0) } ?? "-"
            case "noise":
                textField.stringValue = network.noise.map { "\($0)" } ?? "-"
            case "protectionMode":
                textField.stringValue = network.protectionMode ?? "-"
            case "snr":
                textField.stringValue = network.snr.map { "\($0)" } ?? "-"
            case "stations":
                textField.stringValue = network.stations.map { "\($0)" } ?? "-"
            case "streams":
                textField.stringValue = network.streams.map { "\($0)" } ?? "-"
            case "type":
                textField.stringValue = network.type ?? "-"
            case "wps":
                textField.stringValue = network.wps ?? "-"
            default:
                textField.stringValue = "-"
            }
            
            return textField
        }
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key else { return }
            parent.viewModel.sort(by: key, ascending: sortDescriptor.ascending)
            tableView.reloadData()
        }
        
        /// Обновляет индикатор направления сортировки на активном столбце
        @MainActor
        func updateSortIndicators() {
            guard let tableView = tableView else { return }
            // Сбрасываем индикаторы на всех столбцах
            for column in tableView.tableColumns {
                tableView.setIndicatorImage(nil, in: column)
            }
            guard let key = parent.viewModel.currentSortKey else { return }
            guard let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == key }) else { return }
            let imageName = parent.viewModel.isSortAscending ? NSImage.touchBarGoUpTemplateName : NSImage.touchBarGoDownTemplateName
            if let image = NSImage(named: NSImage.Name(imageName)) {
                tableView.setIndicatorImage(image, in: column)
            }
            // Синхронизируем sortDescriptors NSTableView с текущим состоянием ViewModel (только при изменении)
            let descriptor = NSSortDescriptor(key: key, ascending: parent.viewModel.isSortAscending)
            if tableView.sortDescriptors.first?.key != key || tableView.sortDescriptors.first?.ascending != parent.viewModel.isSortAscending {
                tableView.sortDescriptors = [descriptor]
            }
        }
        
        @objc func columnDidMove(_ notification: Notification) {
            guard !isProgrammaticColumnChange,
                  let tableView = notification.object as? NSTableView else { return }
            
            // Сохраняем новый порядок столбцов
            let newOrder = tableView.tableColumns.enumerated().map { index, column in
                (column.identifier.rawValue, index)
            }
            
            Task { @MainActor in
                for (id, newIndex) in newOrder {
                    if let colIndex = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                        parent.viewModel.columnDefinitions[colIndex].order = newIndex
                    }
                }
                parent.viewModel.saveColumnSettings()
                // Обновляем сигнатуру на основании актуальной модели
                let target = parent.viewModel.columnDefinitions.sorted { $0.order < $1.order }
                self.lastAppliedColumnsSignature = target.map { "\($0.id)|\($0.isVisible ? 1 : 0)|\(Int($0.width))|\($0.order)" }.joined(separator: ",")
            }
        }
    }
}


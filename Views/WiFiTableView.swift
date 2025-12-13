//
//  WiFiTableView.swift
//

import SwiftUI
import AppKit

// MARK: - Custom Cell Class
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
        addSubview(textFieldLabel)
        self.textField = textFieldLabel
        
        // Оптимизированные констрейнты
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

extension NSUserInterfaceItemIdentifier {
    static let bssid = NSUserInterfaceItemIdentifier("bssid")
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
        
        // 3. УБИРАЕМ РАЗДЕЛИТЕЛИ
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        
        // Включаем чередование цветов
        tableView.usesAlternatingRowBackgroundColors = true
        
        // Убираем сетку (вертикальные и горизонтальные линии)
        tableView.gridStyleMask = []
        
        // Убираем межклеточные отступы для сплошного вида
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        
        tableView.headerView = NSTableHeaderView()
        
        // Контекстные меню
        let headerMenu = NSMenu()
        headerMenu.delegate = context.coordinator
        tableView.headerView?.menu = headerMenu
        
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        
        let rowMenu = NSMenu()
        rowMenu.addItem(NSMenuItem(title: "Копировать SSID", action: #selector(Coordinator.copySSID), keyEquivalent: "c"))
        rowMenu.addItem(NSMenuItem(title: "Копировать BSSID", action: #selector(Coordinator.copyBSSID), keyEquivalent: ""))
        tableView.menu = rowMenu
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        context.coordinator.tableView = tableView
        
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
        
        let targetDefinitions = viewModel.columnDefinitions.sorted { $0.order < $1.order }
        let targetVisibleDefinitions = targetDefinitions.filter { $0.isVisible }
        
        context.coordinator.isProgrammaticUpdate = true
        
        let currentColumnIdentifiers = Set(tableView.tableColumns.map { $0.identifier.rawValue })
        let targetIdentifiers = Set(targetVisibleDefinitions.map { $0.id })
        
        // Remove
        let toRemove = currentColumnIdentifiers.subtracting(targetIdentifiers)
        for id in toRemove {
            if let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) {
                tableView.removeTableColumn(col)
            }
        }
        
        // Add/Update
        for def in targetVisibleDefinitions {
            let id = NSUserInterfaceItemIdentifier(def.id)
            let column: NSTableColumn
            
            if let existing = tableView.tableColumn(withIdentifier: id) {
                column = existing
            } else {
                column = NSTableColumn(identifier: id)
                column.minWidth = 50
                tableView.addTableColumn(column)
            }
            
            if column.title != def.title { column.title = def.title }
            if abs(column.width - def.width) > 1.0 { column.width = def.width }
            
            if column.sortDescriptorPrototype?.key != def.id {
                column.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
            }
        }
        
        // Reorder
        let currentColumns = tableView.tableColumns
        for (targetIndex, def) in targetVisibleDefinitions.enumerated() {
            let id = NSUserInterfaceItemIdentifier(def.id)
            if let currentIndex = currentColumns.firstIndex(where: { $0.identifier == id }) {
                if currentIndex != targetIndex {
                    tableView.moveColumn(currentIndex, toColumn: targetIndex)
                }
            }
        }
        
        context.coordinator.isProgrammaticUpdate = false
        
        if let sortKey = viewModel.currentSortKey {
            let descriptor = NSSortDescriptor(key: sortKey, ascending: viewModel.isSortAscending)
            if tableView.sortDescriptors.first != descriptor {
                tableView.sortDescriptors = [descriptor]
            }
        }
        
        tableView.reloadData()
        restoreSelection(in: tableView, coordinator: context.coordinator)
    }
    
    private func restoreSelection(in tableView: NSTableView, coordinator: Coordinator) {
        guard let selectedBSSID = viewModel.selectedBSSID else {
            if tableView.selectedRow >= 0 {
                coordinator.isUpdatingSelection = true
                tableView.deselectAll(nil)
                coordinator.isUpdatingSelection = false
            }
            return
        }
        
        if let index = viewModel.networks.firstIndex(where: { $0.bssid == selectedBSSID }) {
            if tableView.selectedRow != index {
                coordinator.isUpdatingSelection = true
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                tableView.scrollRowToVisible(index)
                coordinator.isUpdatingSelection = false
            }
        } else {
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
    
    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: WiFiTableView
        weak var tableView: NSTableView?
        
        var isProgrammaticUpdate = false
        var isUpdatingSelection = false
        
        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
        }()
        
        init(_ parent: WiFiTableView) {
            self.parent = parent
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.viewModel.networks.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn,
                  row >= 0,
                  row < parent.viewModel.networks.count else { return nil }
            
            let network = parent.viewModel.networks[row]
            let colId = column.identifier.rawValue
            
            var cellView = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView
            
            if cellView == nil {
                cellView = WiFiTableCellView()
                cellView?.identifier = WiFiTableCellView.identifier
            }
            
            let text = getText(for: colId, network: network)
            let isConnected = (network.bssid == parent.viewModel.currentConnectedBSSID)
            
            cellView?.configure(text: text, isConnected: isConnected)
            return cellView
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if row >= 0, row < self.parent.viewModel.networks.count {
                    let net = self.parent.viewModel.networks[row]
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
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sd = tableView.sortDescriptors.first, let key = sd.key else { return }
            parent.viewModel.sort(by: key, ascending: sd.ascending)
        }
        
        @objc func columnDidMove(_ notification: Notification) {
            guard !isProgrammaticUpdate, let tableView = notification.object as? NSTableView else { return }
            let newOrderMap = tableView.tableColumns.enumerated().map { (offset, col) in
                (id: col.identifier.rawValue, index: offset)
            }
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
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let idx = self.parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                    self.parent.viewModel.columnDefinitions[idx].width = width
                    self.parent.viewModel.saveColumnSettings()
                }
            }
        }
        
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let titleItem = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            
            let definitions = parent.viewModel.columnDefinitions.sorted { $0.title < $1.title }
            for def in definitions {
                let item = NSMenuItem(title: def.title, action: #selector(toggleColumnFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = def.id
                item.state = def.isVisible ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
            let resetItem = NSMenuItem(title: "Reset Columns", action: #selector(resetColumns), keyEquivalent: "")
            resetItem.target = self
            menu.addItem(resetItem)
        }
        
        @objc func toggleColumnFromMenu(_ sender: NSMenuItem) {
            guard let colId = sender.representedObject as? String else { return }
            parent.viewModel.toggleColumn(colId)
        }
        
        @objc func resetColumns() {
            parent.viewModel.resetColumnsToDefault()
        }
        
        @objc func copySSID() { copyToClipboard(keyPath: \.ssid) }
        @objc func copyBSSID() { copyToClipboard(keyPath: \.bssid) }
        
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

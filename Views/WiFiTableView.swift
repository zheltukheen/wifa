//
//  WiFiTableView.swift
//

import SwiftUI
import AppKit

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
        
        let targetDefinitions = viewModel.columnDefinitions.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.order < $1.order
        }
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
            
            if column.title != def.displayTitle { column.title = def.displayTitle }
            if abs(column.width - def.width) > 1.0 { column.width = def.width }
            if let headerCell = column.headerCell as? PaddedHeaderCell {
                if headerCell.stringValue != def.displayTitle { headerCell.stringValue = def.displayTitle }
                if headerCell.alignment != def.alignment.nsTextAlignment { headerCell.alignment = def.alignment.nsTextAlignment }
                headerCell.lineBreakMode = .byTruncatingTail
            } else {
                let headerCell = PaddedHeaderCell(textCell: def.displayTitle)
                headerCell.alignment = def.alignment.nsTextAlignment
                headerCell.lineBreakMode = .byTruncatingTail
                column.headerCell = headerCell
            }
            
            if column.sortDescriptorPrototype?.key != def.id {
                column.sortDescriptorPrototype = NSSortDescriptor(key: def.id, ascending: true)
            }
        }
        
        // Reorder
        for (targetIndex, def) in targetVisibleDefinitions.enumerated() {
            let id = NSUserInterfaceItemIdentifier(def.id)
            if let currentIndex = tableView.tableColumns.firstIndex(where: { $0.identifier == id }) {
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
        guard let selectedId = viewModel.selectedNetworkId else {
            if tableView.selectedRow >= 0 {
                coordinator.isUpdatingSelection = true
                tableView.deselectAll(nil)
                coordinator.isUpdatingSelection = false
            }
            return
        }
        
        if let index = viewModel.networks.firstIndex(where: { $0.id == selectedId }) {
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
            
            let text = parent.viewModel.textForColumn(id: colId, net: network)
            let isConnected = (network.bssid == parent.viewModel.currentConnectedBSSID)
            let alignment = parent.viewModel.columnDefinitions.first(where: { $0.id == colId })?.alignment.nsTextAlignment ?? .left
            
            cellView?.configure(
                text: text,
                isConnected: isConnected,
                alignment: alignment,
                highlightConnected: parent.viewModel.highlightConnectedNetworks
            )
            return cellView
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if row >= 0, row < self.parent.viewModel.networks.count {
                    let net = self.parent.viewModel.networks[row]
                    if self.parent.viewModel.selectedNetworkId != net.id {
                        self.parent.viewModel.selectedNetworkId = net.id
                    }
                } else {
                    if self.parent.viewModel.selectedNetworkId != nil {
                        self.parent.viewModel.selectedNetworkId = nil
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
            let clickedId = currentClickedColumnId()
            let clickedDef = clickedId.flatMap { id in
                parent.viewModel.columnDefinitions.first(where: { $0.id == id })
            }

            let autoSizeItem = NSMenuItem(title: "Auto Size Column", action: #selector(autoSizeColumn(_:)), keyEquivalent: "")
            autoSizeItem.target = self
            autoSizeItem.isEnabled = clickedId != nil
            autoSizeItem.representedObject = clickedId
            menu.addItem(autoSizeItem)

            let autoSizeAllItem = NSMenuItem(title: "Auto Size All Columns", action: #selector(autoSizeAllColumns(_:)), keyEquivalent: "")
            autoSizeAllItem.target = self
            menu.addItem(autoSizeAllItem)

            menu.addItem(NSMenuItem.separator())

            let textOnlyItem = NSMenuItem(title: "Show Text Only All Columns", action: #selector(toggleTextOnly(_:)), keyEquivalent: "")
            textOnlyItem.target = self
            textOnlyItem.state = parent.viewModel.highlightConnectedNetworks ? .off : .on
            menu.addItem(textOnlyItem)

            let alignMenu = NSMenuItem(title: "Align Text", action: nil, keyEquivalent: "")
            let alignSubmenu = NSMenu()
            let alignments: [(String, ColumnAlignment)] = [("Left", .left), ("Center", .center), ("Right", .right)]
            for (title, alignment) in alignments {
                let item = NSMenuItem(title: title, action: #selector(setAllColumnsAlignment(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["alignment": alignment.rawValue] as [String: Any]
                let allAlignments = parent.viewModel.columnDefinitions.map { $0.alignment }
                let uniqueAlignments = Set(allAlignments)
                if uniqueAlignments.count == 1, uniqueAlignments.first == alignment {
                    item.state = .on
                } else if uniqueAlignments.count > 1 {
                    item.state = .mixed
                } else {
                    item.state = .off
                }
                alignSubmenu.addItem(item)
            }
            alignMenu.submenu = alignSubmenu
            menu.addItem(alignMenu)

            menu.addItem(NSMenuItem.separator())

            let pinItem = NSMenuItem(title: "Pin Column", action: #selector(togglePinColumn(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.isEnabled = clickedId != nil
            pinItem.representedObject = clickedId
            pinItem.state = (clickedDef?.isPinned == true) ? .on : .off
            menu.addItem(pinItem)

            menu.addItem(NSMenuItem.separator())

            let hideItem = NSMenuItem(title: "Hide Column", action: #selector(hideColumn(_:)), keyEquivalent: "")
            hideItem.target = self
            hideItem.isEnabled = clickedId != nil
            hideItem.representedObject = clickedId
            menu.addItem(hideItem)

            let renameItem = NSMenuItem(title: "Rename Column", action: #selector(renameColumn(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.isEnabled = clickedId != nil
            renameItem.representedObject = clickedId
            menu.addItem(renameItem)

            menu.addItem(NSMenuItem.separator())

            let titleItem = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)

            let definitions = parent.viewModel.columnDefinitions.sorted { $0.displayTitle < $1.displayTitle }
            for def in definitions {
                let item = NSMenuItem(title: def.displayTitle, action: #selector(toggleColumnFromMenu(_:)), keyEquivalent: "")
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

        @objc func autoSizeColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            autoSizeColumns(ids: [id])
        }

        @objc func autoSizeAllColumns(_ sender: NSMenuItem) {
            let ids = parent.viewModel.columnDefinitions.filter { $0.isVisible }.map { $0.id }
            autoSizeColumns(ids: ids)
        }

        private func autoSizeColumns(ids: [String]) {
            guard let tableView = tableView else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for id in ids {
                    guard let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) else { continue }
                    let width = self.calculateBestWidth(for: id, header: column.title)
                    column.width = width
                    if let idx = self.parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                        self.parent.viewModel.columnDefinitions[idx].width = width
                    }
                }
                self.parent.viewModel.saveColumnSettings()
                self.parent.viewModel.objectWillChange.send()
            }
        }

        private func calculateBestWidth(for id: String, header: String) -> CGFloat {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            var maxWidth = (header as NSString).size(withAttributes: [.font: boldFont]).width
            for net in parent.viewModel.networks {
                let text = parent.viewModel.textForColumn(id: id, net: net)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                if width > maxWidth { maxWidth = width }
            }
            return min(maxWidth + 16, 500)
        }

        @objc func toggleTextOnly(_ sender: NSMenuItem) {
            parent.viewModel.highlightConnectedNetworks.toggle()
        }

        @objc func setAllColumnsAlignment(_ sender: NSMenuItem) {
            guard
                let payload = sender.representedObject as? [String: Any],
                let rawAlignment = payload["alignment"] as? Int,
                let alignment = ColumnAlignment(rawValue: rawAlignment)
            else { return }

            for idx in parent.viewModel.columnDefinitions.indices {
                parent.viewModel.columnDefinitions[idx].alignment = alignment
            }
            parent.viewModel.saveColumnSettings()
            parent.viewModel.objectWillChange.send()
            tableView?.reloadData()
        }

        @objc func togglePinColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            if let idx = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                parent.viewModel.columnDefinitions[idx].isPinned.toggle()
                parent.viewModel.saveColumnSettings()
                parent.viewModel.objectWillChange.send()
            }
        }

        @objc func hideColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            if let idx = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) {
                parent.viewModel.columnDefinitions[idx].isVisible = false
                parent.viewModel.saveColumnSettings()
                parent.viewModel.objectWillChange.send()
            }
        }

        @objc func renameColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            guard let idx = parent.viewModel.columnDefinitions.firstIndex(where: { $0.id == id }) else { return }
            let current = parent.viewModel.columnDefinitions[idx].customTitle ?? parent.viewModel.columnDefinitions[idx].title

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Rename Column"
                alert.informativeText = "Enter a new column name:"
                let input = NSTextField(string: current)
                input.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
                alert.accessoryView = input
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.parent.viewModel.columnDefinitions[idx].customTitle = text.isEmpty ? nil : text
                    self.parent.viewModel.saveColumnSettings()
                    self.parent.viewModel.objectWillChange.send()
                }
            }
        }

        private func currentClickedColumnId() -> String? {
            guard let tableView = tableView else { return nil }
            var index = tableView.clickedColumn
            if index < 0, let headerView = tableView.headerView, let event = NSApp.currentEvent {
                let locationInHeader = headerView.convert(event.locationInWindow, from: nil)
                index = headerView.column(at: locationInHeader)
            }
            guard index >= 0, index < tableView.tableColumns.count else { return nil }
            return tableView.tableColumns[index].identifier.rawValue
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
        
    }
}

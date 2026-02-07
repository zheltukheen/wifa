import SwiftUI
import AppKit

struct RawDataView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var expandedRows: Set<String> = []

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .edgesIgnoringSafeArea(.all)

            if let network = viewModel.selectedNetwork {
                RawDataTableView(elements: network.informationElements, expandedIds: $expandedRows)
                    .onChange(of: viewModel.selectedNetworkId) { _ in
                        expandedRows.removeAll()
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Select a network to view raw data")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.selectedNetworkId) { _ in
            expandedRows.removeAll()
        }
    }
}

struct RawDataTableView: NSViewRepresentable {
    let elements: [InformationElement]
    @Binding var expandedIds: Set<String>

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 22

        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("id"))
        idColumn.title = "ID"
        idColumn.width = 60
        idColumn.headerCell = PaddedHeaderCell(textCell: "ID")
        idColumn.headerCell.alignment = .left

        let lengthColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("length"))
        lengthColumn.title = "Length"
        lengthColumn.width = 70
        lengthColumn.headerCell = PaddedHeaderCell(textCell: "Length")
        lengthColumn.headerCell.alignment = .right

        let elementColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("element"))
        elementColumn.title = "Information Element"
        elementColumn.width = 260
        elementColumn.headerCell = PaddedHeaderCell(textCell: "Information Element")
        elementColumn.headerCell.alignment = .left

        let detailsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        detailsColumn.title = "Details"
        detailsColumn.width = 600
        detailsColumn.headerCell = PaddedHeaderCell(textCell: "Details")
        detailsColumn.headerCell.alignment = .left

        tableView.addTableColumn(idColumn)
        tableView.addTableColumn(lengthColumn)
        tableView.addTableColumn(elementColumn)
        tableView.addTableColumn(detailsColumn)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        tableView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: RawDataTableView
        weak var tableView: NSTableView?

        init(_ parent: RawDataTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowItems().count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn,
                  row >= 0,
                  row < rowItems().count else { return nil }

            let item = rowItems()[row]
            let id = column.identifier.rawValue

            switch id {
            case "id":
                let cell = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView ?? {
                    let view = WiFiTableCellView()
                    view.identifier = WiFiTableCellView.identifier
                    return view
                }()
                let text = item.isDetail ? "" : item.element.displayId
                cell.configure(text: text, isConnected: false, alignment: .left, highlightConnected: false, style: item.isDetail ? .secondary : .standard)
                return cell
            case "length":
                let cell = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView ?? {
                    let view = WiFiTableCellView()
                    view.identifier = WiFiTableCellView.identifier
                    return view
                }()
                let text: String
                if item.isDetail {
                    text = ""
                } else {
                    let suffix = item.element.length == 1 ? "byte" : "bytes"
                    text = "\(item.element.length) \(suffix)"
                }
                cell.configure(text: text, isConnected: false, alignment: .right, highlightConnected: false, style: item.isDetail ? .secondary : .standard)
                return cell
            case "element":
                if item.isDetail {
                    let cell = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView ?? {
                        let view = WiFiTableCellView()
                        view.identifier = WiFiTableCellView.identifier
                        return view
                    }()
                    let text = "   \(item.detailLabel ?? "")"
                    cell.configure(text: text, isConnected: false, alignment: .left, highlightConnected: false, style: .secondary)
                    return cell
                } else {
                    let cell = tableView.makeView(withIdentifier: DisclosureTableCellView.identifier, owner: self) as? DisclosureTableCellView ?? {
                        let view = DisclosureTableCellView()
                        view.identifier = DisclosureTableCellView.identifier
                        return view
                    }()
                    let isExpanded = parent.expandedIds.contains(item.element.id)
                    cell.configure(title: item.element.name, isExpanded: isExpanded) { [weak self] in
                        self?.toggleRow(row)
                    }
                    return cell
                }
            case "details":
                let cell = tableView.makeView(withIdentifier: WiFiTableCellView.identifier, owner: self) as? WiFiTableCellView ?? {
                    let view = WiFiTableCellView()
                    view.identifier = WiFiTableCellView.identifier
                    return view
                }()
                let text = item.isDetail ? (item.detailValue ?? "") : item.element.summary
                cell.configure(text: text, isConnected: false, alignment: .left, highlightConnected: false, style: item.isDetail ? .secondary : .standard)
                return cell
            default:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            tableView.rowHeight
        }

        private func toggleRow(_ row: Int) {
            let items = rowItems()
            guard row >= 0, row < items.count else { return }
            let element = items[row].element
            if parent.expandedIds.contains(element.id) {
                parent.expandedIds.remove(element.id)
            } else {
                parent.expandedIds.insert(element.id)
            }
            guard let tableView = tableView else { return }
            tableView.reloadData()
        }

        private struct RowItem {
            let element: InformationElement
            let detailLabel: String?
            let detailValue: String?

            var isDetail: Bool { detailLabel != nil }
        }

        private func rowItems() -> [RowItem] {
            var rows: [RowItem] = []
            for element in parent.elements {
                rows.append(RowItem(element: element, detailLabel: nil, detailValue: nil))
                if parent.expandedIds.contains(element.id) {
                    rows.append(RowItem(element: element, detailLabel: "Element ID", detailValue: "\(element.elementId)"))
                    let suffix = element.length == 1 ? "byte" : "bytes"
                    rows.append(RowItem(element: element, detailLabel: "Length", detailValue: "\(element.length) \(suffix)"))
                    for line in element.detailLines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        if let range = trimmed.range(of: ":") {
                            let label = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            rows.append(RowItem(element: element, detailLabel: label, detailValue: value))
                        } else {
                            rows.append(RowItem(element: element, detailLabel: "Detail", detailValue: trimmed))
                        }
                    }
                }
            }
            return rows
        }
    }
}

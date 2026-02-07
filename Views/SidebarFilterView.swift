import SwiftUI

struct SidebarFilterView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var expandedSections: Set<SidebarCategory> = []

    private let sortOptions: [ColumnId] = [
        .signal,
        .networkName,
        .channel,
        .band,
        .security,
        .vendor,
        .lastSeen,
        .seen,
        .maxRate
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Picker("Sort By", selection: Binding(
                            get: { viewModel.currentSortKey ?? ColumnId.signal.rawValue },
                            set: { viewModel.currentSortKey = $0 }
                        )) {
                            ForEach(sortOptions, id: \.self) { option in
                                Text(option.defaultTitle).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: { viewModel.isSortAscending.toggle() }) {
                            Image(systemName: viewModel.isSortAscending ? "arrow.up" : "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help(viewModel.isSortAscending ? "Ascending" : "Descending")

                        Button(action: { viewModel.clearQuickFilters() }) {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear Filters")
                    }
                    .controlSize(.small)

                    ForEach(SidebarCategory.allCases, id: \.self) { category in
                        let options = viewModel.sidebarOptions(for: category)
                        let total = options.reduce(0) { $0 + $1.count }
                        SidebarSection(
                            title: category.title,
                            options: options,
                            totalCount: total,
                            selection: binding(for: category),
                            isExpanded: Binding(
                                get: { expandedSections.contains(category) },
                                set: { expanded in
                                    if expanded { expandedSections.insert(category) }
                                    else { expandedSections.remove(category) }
                                }
                            )
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private func binding(for category: SidebarCategory) -> Binding<String?> {
        switch category {
        case .networkName:
            return $viewModel.quickFilterNetworkName
        case .mode:
            return $viewModel.quickFilterMode
        case .channel:
            return $viewModel.quickFilterChannel
        case .channelWidth:
            return $viewModel.quickFilterChannelWidth
        case .security:
            return $viewModel.quickFilterSecurity
        case .accessPoint:
            return $viewModel.quickFilterAccessPoint
        case .vendor:
            return $viewModel.quickFilterVendor
        }
    }
}

struct SidebarSection: View {
    let title: String
    let options: [(value: String, count: Int)]
    let totalCount: Int
    @Binding var selection: String?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                SidebarOptionRow(
                    label: "All",
                    count: totalCount,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }

                ForEach(options, id: \.value) { option in
                    SidebarOptionRow(
                        label: option.value,
                        count: option.count,
                        isSelected: selection == option.value
                    ) {
                        selection = option.value
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SidebarOptionRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

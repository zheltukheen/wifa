import SwiftUI
import AppKit

struct WiFACommands: Commands {
    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var uiState: AppUIState

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About WiFA") {
                showAboutPanel()
            }
        }

        CommandMenu("Scan") {
            Button("Refresh Now") {
                viewModel.refresh()
            }
            .keyboardShortcut("r")

            Divider()

            Picker("Scan Interval", selection: Binding(
                get: { viewModel.refreshInterval },
                set: { viewModel.updateRefreshInterval(to: $0) }
            )) {
                Text("1s").tag(1.0)
                Text("3s").tag(3.0)
                Text("5s").tag(5.0)
                Text("10s").tag(10.0)
                Text("30s").tag(30.0)
            }

            Button("Custom Interval…") {
                uiState.customIntervalText = String(Int(viewModel.refreshInterval))
                uiState.showingCustomIntervalAlert = true
            }
        }

        CommandMenu("Filters") {
            Toggle("2.4 GHz", isOn: $viewModel.filterBand24)
            Toggle("5 GHz", isOn: $viewModel.filterBand5)
            Toggle("6 GHz", isOn: $viewModel.filterBand6)

            Divider()

            Picker("Min Signal", selection: $viewModel.minSignalThreshold) {
                Text("-90 dBm").tag(-90.0)
                Text("-80 dBm").tag(-80.0)
                Text("-70 dBm").tag(-70.0)
                Text("-60 dBm").tag(-60.0)
                Text("-50 dBm").tag(-50.0)
            }

            Divider()

            Button("Clear Quick Filters") {
                viewModel.clearQuickFilters()
            }
        }

        CommandMenu("Display") {
            Picker("Signal Unit", selection: $viewModel.signalDisplayMode) {
                ForEach(SignalDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Highlight Connected Network", isOn: $viewModel.highlightConnectedNetworks)
        }

        CommandMenu("Panels") {
            Toggle("Show Filters Sidebar", isOn: $uiState.showSidebar)
            Toggle("Show Inspector", isOn: $uiState.showInspector)

            Divider()

            Picker("Bottom Panel", selection: $uiState.selectedBottomTab) {
                Text("Spectrum").tag(0)
                Text("History").tag(1)
                Text("Raw Data").tag(2)
            }
        }

        CommandMenu("Data") {
            Button("Export CSV") {
                viewModel.exportCSV()
            }
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let credits = NSAttributedString(string: "Native macOS Wi‑Fi Analyzer\n© 2026 WiFA Contributors")

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "WiFA",
            NSApplication.AboutPanelOptionKey.applicationVersion: "Version \(version) (\(build))",
            NSApplication.AboutPanelOptionKey.credits: credits
        ])
    }
}

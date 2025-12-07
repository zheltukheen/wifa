import SwiftUI

@main
struct WifiAnalyzerApp: App {
    @StateObject private var viewModel = AnalyzerViewModel()
    var body: some Scene {
        WindowGroup {
            MainTableView(viewModel: viewModel)
        }
    }
}

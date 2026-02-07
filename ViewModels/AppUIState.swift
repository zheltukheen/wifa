import Foundation

final class AppUIState: ObservableObject {
    @Published var showSidebar: Bool = false
    @Published var showInspector: Bool = true
    @Published var selectedBottomTab: Int = 0
    @Published var customIntervalText: String = ""
    @Published var showingCustomIntervalAlert: Bool = false
}

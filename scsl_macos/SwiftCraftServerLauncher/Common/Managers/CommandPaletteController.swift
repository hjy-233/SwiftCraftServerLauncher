import SwiftUI

final class CommandPaletteController: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""
    @Published var lastSelectionId: String?
    @Published var pathIds: [String] = []
    @Published var expandedIds: Set<String> = []
    @Published var searchContextPath: [String] = []

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

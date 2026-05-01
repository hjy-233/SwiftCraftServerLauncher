import SwiftUI

struct ServerPropertiesShortcutCommands: View {
    @Binding var showSidebar: Bool
    @Binding var isImportingFiles: Bool
    @Binding var showNewFolderPrompt: Bool
    @Binding var showNewFilePrompt: Bool
    let beginRenameSelected: () -> Void
    let confirmDeleteSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button { showSidebar.toggle() } label: { EmptyView() }
                .keyboardShortcut("\\", modifiers: [.command])
            Button { isImportingFiles = true } label: { EmptyView() }
                .keyboardShortcut("u", modifiers: [.command])
            Button { showNewFolderPrompt = true } label: { EmptyView() }
                .keyboardShortcut("N", modifiers: [.command, .shift])
            Button { showNewFilePrompt = true } label: { EmptyView() }
                .keyboardShortcut("n", modifiers: [.command])
            Button { beginRenameSelected() } label: { EmptyView() }
                .keyboardShortcut("r", modifiers: [.command])
            Button { confirmDeleteSelected() } label: { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .hidden()
    }
}

struct ServerPropertiesShortcutBar: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                shortcutBadge(text: "server.files.shortcut.new_file".localized())
                shortcutBadge(text: "server.files.shortcut.new_folder".localized())
                shortcutBadge(text: "server.files.shortcut.upload".localized())
                shortcutBadge(text: "server.files.shortcut.rename".localized())
                shortcutBadge(text: "server.files.shortcut.delete".localized())
                shortcutBadge(text: "server.files.shortcut.sidebar".localized())
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: 480, alignment: .trailing)
    }

    private func shortcutBadge(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.18))
            .clipShape(Capsule())
    }
}

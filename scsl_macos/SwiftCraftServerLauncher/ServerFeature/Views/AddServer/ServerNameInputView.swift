import SwiftUI

struct ServerNameInputView: View {
    @Binding var serverName: String
    @Binding var isServerNameDuplicate: Bool
    let onNameChange: () -> Void
    @FocusState private var isServerNameFocused: Bool
    @State private var showErrorPopover: Bool = false
    let isDisabled: Bool
    let serverSetupService: ServerSetupUtil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.name".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            TextField(
                "server.form.name.placeholder".localized(),
                text: $serverName
            )
            .textFieldStyle(.roundedBorder)
            .foregroundColor(.primary)
            .focused($isServerNameFocused)
            .focusEffectDisabled()
            .disabled(isDisabled)
            .popover(isPresented: $showErrorPopover, arrowEdge: .trailing) {
                if isServerNameDuplicate {
                    Text("server.form.name.duplicate".localized())
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            .onChange(of: serverName) { _, newName in
                onNameChange()
                Task {
                    let isDuplicate = await serverSetupService.checkServerNameDuplicate(newName)
                    await MainActor.run {
                        if isDuplicate != isServerNameDuplicate {
                            isServerNameDuplicate = isDuplicate
                        }
                        showErrorPopover = isDuplicate
                    }
                }
            }
            .onSubmit {
                onNameChange()
            }
        }
    }
}

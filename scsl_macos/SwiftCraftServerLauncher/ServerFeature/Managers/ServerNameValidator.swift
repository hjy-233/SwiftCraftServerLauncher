import SwiftUI

@MainActor
class ServerNameValidator: ObservableObject {
    @Published var serverName: String = ""
    @Published var isServerNameDuplicate: Bool = false

    private let serverSetupService: ServerSetupUtil

    init(serverSetupService: ServerSetupUtil) {
        self.serverSetupService = serverSetupService
    }

    func validateServerName() async {
        guard !serverName.isEmpty else {
            isServerNameDuplicate = false
            return
        }

        let isDuplicate = await serverSetupService.checkServerNameDuplicate(serverName)
        if isDuplicate != isServerNameDuplicate {
            isServerNameDuplicate = isDuplicate
        }
    }

    func setDefaultName(_ name: String) {
        if serverName.isEmpty {
            serverName = name
        }
    }

    func reset() {
        serverName = ""
        isServerNameDuplicate = false
    }

    var isFormValid: Bool {
        !serverName.isEmpty && !isServerNameDuplicate
    }
}

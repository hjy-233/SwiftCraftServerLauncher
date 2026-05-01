import SwiftUI

public struct ContentToolbarView: ToolbarContent {
    @State private var showingServerForm = false
    @State private var showingAddNodeForm = false
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject var detailState: ResourceDetailState
    @AppStorage("activeServerNodeId")
    private var activeServerNodeId: String = ServerNode.local.id

    private var selectedNodeForCreation: ServerNode {
        serverNodeRepository.getNode(by: activeServerNodeId) ?? .local
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingServerForm = true
            } label: {
                Label("toolbar.create_server".localized(), systemImage: "plus")
            }
            .help("toolbar.create_server".localized())
            .sheet(isPresented: $showingServerForm) {
                GameFormView(
                    initialCreationTarget: .server,
                    initialServerNode: selectedNodeForCreation
                )
                    .environmentObject(gameRepository)
                    .environmentObject(serverRepository)
                    .presentationBackgroundInteraction(.automatic)
            }

            Button {
                showingAddNodeForm = true
            } label: {
                Label("toolbar.add_linux_node".localized(), systemImage: "network.badge.shield.half.filled")
            }
            .help("toolbar.add_linux_node".localized())
            .sheet(isPresented: $showingAddNodeForm) {
                AddServerNodeSheet()
                    .environmentObject(serverNodeRepository)
                    .presentationBackgroundInteraction(.automatic)
            }
        }
    }
}

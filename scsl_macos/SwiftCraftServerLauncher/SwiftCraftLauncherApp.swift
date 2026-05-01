import Combine
import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct SwiftCraftServerLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self)
    private var appTerminationDelegate

    @Environment(\.scenePhase)
    private var scenePhase

    @Environment(\.openWindow)
    private var openWindow

    @AppStorage("showServerStatusMenuBar")
    private var showServerStatusMenuBar = true

    // MARK: - StateObjects
    @StateObject var gameRepository = GameRepository()
    @StateObject var serverRepository = ServerRepository()
    @StateObject var serverNodeRepository = ServerNodeRepository()
    @StateObject var gameLaunchUseCase = GameLaunchUseCase()
    @StateObject var serverLaunchUseCase = ServerLaunchUseCase()
    @StateObject private var globalErrorHandler = GlobalErrorHandler.shared
    @StateObject private var appUpdateService = AppUpdateService()
    @StateObject var generalSettingsManager = GeneralSettingsManager.shared
    @StateObject var themeManager = ThemeManager.shared
    @StateObject private var appIdleManager = AppIdleManager.shared
    @StateObject private var commandPalette = CommandPaletteController()
    @StateObject private var settingsNavigationManager = SettingsNavigationManager.shared

    // MARK: - Notification Delegate
    private let notificationCenterDelegate = NotificationCenterDelegate()

    init() {
        // 设置通知中心代理，确保前台时也能展示 Banner
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate

        Task {
            await NotificationManager.requestAuthorizationIfNeeded()
        }
    }

    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.appLogger, Logger.shared)
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(gameLaunchUseCase)
                .environmentObject(serverLaunchUseCase)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(commandPalette)
                .environmentObject(settingsNavigationManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
                .windowOpener()
                .titlebarSeparatorOnHover()
                .onAppear {
                    ServerDetailWindowManager.shared.configure(
                        serverRepository: serverRepository,
                        serverNodeRepository: serverNodeRepository,
                        serverLaunchUseCase: serverLaunchUseCase,
                        generalSettingsManager: generalSettingsManager
                    )
                    appIdleManager.startMonitoring()
                    BackupService.shared.startAutoBackupScheduler()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    appIdleManager.handleScenePhase(newPhase)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        SpotlightActionCenter.shared.send(identifier: identifier)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .conditionalRestorationBehavior()
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(format: "menu.about".localized(), Bundle.main.appName)) {
                    WindowManager.shared.openWindow(id: .about)
                }

                Button("menu.check.updates".localized()) {
                    appUpdateService.installLatestRelease()
                }
                .disabled(appUpdateService.isUpdating)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("menu.open.log".localized()) {
                    Logger.shared.openLogFile()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("menu.github".localized()) {
                    NSWorkspace.shared.open(URLConfig.API.GitHub.repositoryURL())
                }

                Button("menu.report_issue".localized()) {
                    NSWorkspace.shared.open(URLConfig.API.GitHub.issuesURL())
                }

                Button("about.contributors".localized()) {
                    openWindow(id: WindowID.contributors.rawValue)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("menu.view_license".localized()) {
                    NSWorkspace.shared.open(URLConfig.API.GitHub.licenseWebPage(ref: "dev"))
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button("menu.command.palette".localized()) {
                    commandPalette.present()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(settingsNavigationManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
        }

        appWindowGroups()

        MenuBarExtra(
            "menubar.servers.title".localized(),
            systemImage: "server.rack",
            isInserted: $showServerStatusMenuBar
        ) {
            ServerStatusMenuBarView()
                .environmentObject(serverRepository)
        }
        .menuBarExtraStyle(.menu)
    }
}

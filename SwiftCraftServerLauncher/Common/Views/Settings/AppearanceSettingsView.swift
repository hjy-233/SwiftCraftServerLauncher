import SwiftUI

public struct AppearanceSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @AppStorage("showServerStatusMenuBar")
    private var showServerStatusMenuBar = true

    private let defaultThemeMode: ThemeMode = .system
    private let defaultEnableConsoleColoredOutput = true
    private let defaultServerFileManagerShowShortcuts = true
    private let defaultOpenServerInNewWindow = false
    private let defaultShowServerStatusMenuBar = true

    public init() {}

    public var body: some View {
        Form {
            Section(
                header: Text("settings.appearance.section.global.header".localized())
            ) {
                LabeledContent("settings.appearance.theme".localized()) {
                    HStack(alignment: .top, spacing: 8) {
                        ThemeSelectorView(selectedTheme: $themeManager.themeMode)
                            .fixedSize()

                        resetIconButton(disabled: themeManager.themeMode == defaultThemeMode) {
                            themeManager.themeMode = defaultThemeMode
                        }
                    }
                }
                .labeledContentStyle(.custom)

                LabeledContent("settings.appearance.resource_card.style".localized()) {
                    Picker("", selection: $generalSettings.resourceCardStyle) {
                        Text("settings.appearance.resource_card.compact".localized()).tag(ResourceCardStyle.compact)
                        Text("settings.appearance.resource_card.card".localized()).tag(ResourceCardStyle.card)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .labeledContentStyle(.custom)
            }

            Section(
                header: Text("settings.appearance.section.server.header".localized())
            ) {
                Group {
                    LabeledContent("settings.appearance.console_color_output".localized()) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(
                                    "settings.appearance.console_color_output.enable".localized(),
                                    isOn: $generalSettings.enableConsoleColoredOutput
                                )
                                .toggleStyle(.checkbox)

                                Text("settings.appearance.console_color_output.description".localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            resetIconButton(disabled: generalSettings.enableConsoleColoredOutput == defaultEnableConsoleColoredOutput) {
                                generalSettings.enableConsoleColoredOutput = defaultEnableConsoleColoredOutput
                            }
                        }
                    }
                    .labeledContentStyle(.custom(alignment: .firstTextBaseline))

                    LabeledContent("settings.appearance.console.font".localized()) {
                        Picker("", selection: $generalSettings.consoleFontStyle) {
                            Text("settings.appearance.font.system".localized()).tag(ConsoleFontStyle.system)
                            Text("settings.appearance.font.monospaced".localized()).tag(ConsoleFontStyle.monospaced)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .labeledContentStyle(.custom)

                    LabeledContent("settings.appearance.console.line_spacing".localized()) {
                        HStack(spacing: 8) {
                            Text("\(Int(generalSettings.consoleLineSpacing))")
                                .frame(minWidth: 24, alignment: .trailing)
                                .monospacedDigit()
                            Slider(value: $generalSettings.consoleLineSpacing, in: 0...8, step: 1)
                                .frame(width: 200)
                        }
                    }
                    .labeledContentStyle(.custom)

                    LabeledContent("settings.appearance.console.highlight".localized()) {
                        Picker("", selection: $generalSettings.consoleHighlightStyle) {
                            Text("settings.appearance.highlight.system".localized()).tag(HighlightStyle.system)
                            Text("settings.appearance.highlight.vivid".localized()).tag(HighlightStyle.vivid)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .labeledContentStyle(.custom)
                }

                Group {
                    LabeledContent("settings.appearance.editor.font".localized()) {
                        Picker("", selection: $generalSettings.editorFontStyle) {
                            Text("settings.appearance.font.system".localized()).tag(EditorFontStyle.system)
                            Text("settings.appearance.font.monospaced".localized()).tag(EditorFontStyle.monospaced)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .labeledContentStyle(.custom)

                    LabeledContent("settings.appearance.editor.highlight".localized()) {
                        Picker("", selection: $generalSettings.editorHighlightStyle) {
                            Text("settings.appearance.highlight.system".localized()).tag(HighlightStyle.system)
                            Text("settings.appearance.highlight.vivid".localized()).tag(HighlightStyle.vivid)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .labeledContentStyle(.custom)
                }

                Group {
                    LabeledContent("settings.appearance.server_tabs".localized()) {
                        Menu {
                            ForEach(tabOptions) { option in
                                Toggle(option.title, isOn: Binding(
                                    get: { option.isOn() },
                                    set: { option.set($0) }
                                ))
                            }
                        } label: {
                            Text("settings.appearance.server_tabs.select".localized())
                                .frame(minWidth: 140, alignment: .leading)
                        }
                        .menuStyle(.automatic)
                        .controlSize(.small)
                    }
                    .labeledContentStyle(.custom(alignment: .top))

                    LabeledContent("settings.appearance.server_file_shortcuts".localized()) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(
                                    "settings.appearance.server_file_shortcuts.enable".localized(),
                                    isOn: $generalSettings.serverFileManagerShowShortcuts
                                )
                                .toggleStyle(.checkbox)

                                Text("settings.appearance.server_file_shortcuts.description".localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            resetIconButton(disabled: generalSettings.serverFileManagerShowShortcuts == defaultServerFileManagerShowShortcuts) {
                                generalSettings.serverFileManagerShowShortcuts = defaultServerFileManagerShowShortcuts
                            }
                        }
                    }
                    .labeledContentStyle(.custom(alignment: .firstTextBaseline))

                    LabeledContent("settings.server.open_in_new_window".localized()) {
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: $generalSettings.openServerInNewWindow)
                                .labelsHidden()

                            resetIconButton(disabled: generalSettings.openServerInNewWindow == defaultOpenServerInNewWindow) {
                                generalSettings.openServerInNewWindow = defaultOpenServerInNewWindow
                            }
                        }
                    }
                    .labeledContentStyle(.custom)

                    LabeledContent("settings.server.show_status_menubar".localized()) {
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: $showServerStatusMenuBar)
                                .labelsHidden()

                            resetIconButton(disabled: showServerStatusMenuBar == defaultShowServerStatusMenuBar) {
                                showServerStatusMenuBar = defaultShowServerStatusMenuBar
                            }
                        }
                    }
                    .labeledContentStyle(.custom)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var tabOptions: [TabOption] {
        [
            TabOption(
                id: "console",
                title: "settings.appearance.server_tab.console".localized(),
                isOn: { generalSettings.serverTabConsoleEnabled },
                set: { generalSettings.serverTabConsoleEnabled = $0 }
            ),
            TabOption(
                id: "server_config",
                title: "settings.appearance.server_tab.server_config".localized(),
                isOn: { generalSettings.serverTabConfigEnabled },
                set: { generalSettings.serverTabConfigEnabled = $0 }
            ),
            TabOption(
                id: "players",
                title: "settings.appearance.server_tab.players".localized(),
                isOn: { generalSettings.serverTabPlayersEnabled },
                set: { generalSettings.serverTabPlayersEnabled = $0 }
            ),
            TabOption(
                id: "worlds",
                title: "settings.appearance.server_tab.worlds".localized(),
                isOn: { generalSettings.serverTabWorldsEnabled },
                set: { generalSettings.serverTabWorldsEnabled = $0 }
            ),
            TabOption(
                id: "mods",
                title: "settings.appearance.server_tab.mods".localized(),
                isOn: { generalSettings.serverTabModsEnabled },
                set: { generalSettings.serverTabModsEnabled = $0 }
            ),
            TabOption(
                id: "plugins",
                title: "settings.appearance.server_tab.plugins".localized(),
                isOn: { generalSettings.serverTabPluginsEnabled },
                set: { generalSettings.serverTabPluginsEnabled = $0 }
            ),
            TabOption(
                id: "schedules",
                title: "settings.appearance.server_tab.schedules".localized(),
                isOn: { generalSettings.serverTabSchedulesEnabled },
                set: { generalSettings.serverTabSchedulesEnabled = $0 }
            ),
            TabOption(
                id: "logs",
                title: "settings.appearance.server_tab.logs".localized(),
                isOn: { generalSettings.serverTabLogsEnabled },
                set: { generalSettings.serverTabLogsEnabled = $0 }
            ),
        ]
    }

    @ViewBuilder
    private func resetIconButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .help("common.reset".localized())
        .disabled(disabled)
    }
}

private struct TabOption: Identifiable {
    let id: String
    let title: String
    let isOn: () -> Bool
    let set: (Bool) -> Void
}

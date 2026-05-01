import SwiftUI

public struct AISettingsView: View {
    @StateObject private var settings = AISettingsManager.shared
    @State private var showApiKey = false
    @State private var showApiKeyInfo = false
    @State private var showApiURLInfo = false
    @State private var showModelInfo = false

    public init() {}

    public var body: some View {
        Form {
            LabeledContent("settings.ai.api_type.label".localized()) {
                Picker("", selection: Binding(
                    get: { settings.selectedProvider },
                    set: { settings.selectedProvider = $0 }
                )) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .labeledContentStyle(.custom)

            LabeledContent("settings.ai.api_key.label".localized()) {
                HStack(spacing: 4) {
                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(
                        showApiKey
                            ? "settings.ai.api_key.hide".localized()
                            : "settings.ai.api_key.show".localized()
                    )

                    if showApiKey {
                        TextField(
                            "",
                            text: Binding(
                                get: { settings.apiKey },
                                set: { settings.apiKey = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(
                            "",
                            text: Binding(
                                get: { settings.apiKey },
                                set: { settings.apiKey = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    infoButton(isPresented: $showApiKeyInfo) {
                        Text("settings.ai.api_key.description".localized())
                    }
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))

            LabeledContent(apiURLLabel) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { currentAPIURL },
                                set: { updateAPIURL($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        infoButton(isPresented: $showApiURLInfo) {
                            Text("settings.ai.api_url.description".localized())
                        }
                    }

                    Text("settings.ai.api_url.recommend".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .labeledContentStyle(.custom)

            LabeledContent("settings.ai.model.label".localized()) {
                HStack(spacing: 4) {
                    TextField(
                        "settings.ai.model.placeholder".localized(),
                        text: $settings.modelOverride
                    )
                    .textFieldStyle(.roundedBorder)

                    infoButton(isPresented: $showModelInfo) {
                        Text("settings.ai.model.description".localized())
                    }
                }
            }
            .labeledContentStyle(.custom)
        }
        .formStyle(.grouped)
    }

    private var apiURLLabel: String {
        settings.selectedProvider == .ollama
            ? "settings.ai.ollama.url.label".localized()
            : "settings.ai.api_url.label".localized()
    }

    private var currentAPIURL: String {
        if settings.selectedProvider == .ollama {
            return settings.ollamaBaseURL
        }
        return settings.openAIBaseURL
    }

    private func updateAPIURL(_ value: String) {
        if settings.selectedProvider == .ollama {
            settings.ollamaBaseURL = value
        } else {
            settings.openAIBaseURL = value
        }
    }

    @ViewBuilder
    private func infoButton(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented) {
            content()
                .font(.caption)
                .padding(10)
                .frame(width: 260, alignment: .leading)
        }
    }
}

#Preview {
    AISettingsView()
}

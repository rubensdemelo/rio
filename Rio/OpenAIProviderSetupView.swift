import SwiftUI

struct OpenAIProviderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OpenAIProviderSettings.self) private var providerSettings
    @State private var isShowingKeyDetails = false
    @State private var isConfirmingDeletion = false

    let didChangeConfiguration: () -> Void

    var body: some View {
        Group {
            if isShowingKeyDetails {
                OpenAIAPIKeyDetailsView(
                    didChangeConfiguration: didChangeConfiguration,
                    closeDetails: { isShowingKeyDetails = false },
                    isInitialSetup: false
                )
            } else if !providerSettings.isConfigured {
                OpenAIAPIKeyDetailsView(
                    didChangeConfiguration: didChangeConfiguration,
                    closeDetails: { dismiss() },
                    isInitialSetup: true
                )
            } else {
                keyOverview
            }
        }
        .padding(24)
        .frame(width: 440)
        .confirmationDialog(
            "Delete OpenAI API key?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                providerSettings.remove()
                didChangeConfiguration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the current API key. You can add it again later.")
        }
    }

    private var keyOverview: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("OpenAI API key")
                .font(.title2.weight(.bold))

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("OpenAI")
                        .font(.body.weight(.medium))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(providerSettings.isConfigured ? Color.green : Color.secondary)
                            .frame(width: 10, height: 10)
                        Text(providerSettings.isConfigured ? "Configured" : "Not configured")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                if providerSettings.isConfigured {
                    Button(role: .destructive) {
                        isConfirmingDeletion = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                } else {
                    Button("Add key") {
                        isShowingKeyDetails = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

}

private struct OpenAIAPIKeyDetailsView: View {
    @Environment(OpenAIProviderSettings.self) private var providerSettings
    @State private var isConfirmingDeletion = false

    let didChangeConfiguration: () -> Void
    let closeDetails: () -> Void
    let isInitialSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("OpenAI API key")
                .font(.title2.weight(.bold))

            SecureField("Paste API key", text: Bindable(providerSettings).apiKey)
                .textFieldStyle(.roundedBorder)

            if let errorMessage = providerSettings.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if providerSettings.isConfigured && !isInitialSetup {
                    Button(role: .destructive) {
                        isConfirmingDeletion = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                Spacer()
                if isInitialSetup {
                    Button("Done") {
                        if providerSettings.save() {
                            didChangeConfiguration()
                            closeDetails()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(providerSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Back", action: closeDetails)
                    Button("Save key") {
                        if providerSettings.save() {
                            didChangeConfiguration()
                            closeDetails()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(providerSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Delete OpenAI API key?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                providerSettings.remove()
                didChangeConfiguration()
                closeDetails()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the current API key. You can add it again later.")
        }
    }
}

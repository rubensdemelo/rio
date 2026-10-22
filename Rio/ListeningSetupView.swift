import SwiftUI

struct ListeningSetupView: View {
    let showsProviderSetup: Bool
    let readiness: SessionReadiness?
    let openProviderSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsProviderSetup {
                setupRow(
                    symbolName: "exclamationmark.circle.fill",
                    tint: .red,
                    title: "OpenAI API key",
                    detail: nil
                ) {
                    Button("Add API key", action: openProviderSetup)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else if !unmetChecks.isEmpty {
                ForEach(unmetChecks.enumerated(), id: \.element.id) { index, check in
                    if index > 0 {
                        Divider().padding(.vertical, 12)
                    }
                    prerequisiteRow(check)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showsProviderSetup ? 0 : 16)
        .background {
            if !showsProviderSetup {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening prerequisites")
    }

    private var unmetChecks: [PrerequisiteCheck] {
        guard !showsProviderSetup else { return [] }
        return readiness?.checks.filter { $0.reason != nil } ?? []
    }

    private func prerequisiteRow(_ check: PrerequisiteCheck) -> some View {
        let presentation = PrerequisiteCheckPresentation(check: check)
        return setupRow(
            symbolName: presentation.symbolName,
            tint: presentation.tint,
            title: presentation.title,
            detail: presentation.detail
        ) {
            if check.kind == .meetingAudio,
               check.reason == .systemAudioPermissionDenied {
                Button("Open System Settings") {
                    SystemSettingsOpener.openSystemAudioRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func setupRow<Action: View>(
        symbolName: String,
        tint: Color,
        title: String,
        detail: String?,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)
            action()
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrerequisiteCheckPresentation: Equatable {
    let title: String
    let detail: String
    let symbolName: String
    let tintName: SessionStatusPresentation.TintName

    init(check: PrerequisiteCheck) {
        title = check.kind.title
        if let reason = check.reason {
            detail = reason.guidanceMessage
            symbolName = "exclamationmark.circle.fill"
            tintName = .unavailable
        } else {
            detail = "Ready."
            symbolName = "checkmark.circle.fill"
            tintName = .active
        }
    }

    var tint: Color {
        switch tintName {
        case .neutral:
            .secondary
        case .active:
            .accentColor
        case .warning:
            .orange
        case .unavailable:
            .red
        }
    }
}

private extension PrerequisiteKind {
    var title: String {
        switch self {
        case .meetingAudio:
            "Meeting audio access"
        case .meetingTranscription:
            "Meeting transcription"
        case .openAI:
            "OpenAI API"
        }
    }
}

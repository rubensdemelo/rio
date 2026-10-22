import AppKit
import SwiftUI

enum RioMainWindowSizing {
    static func minimumContentHeight(
        apiKeyOnly: Bool,
        needsSetup: Bool,
        compactReady: Bool,
        hasInsights: Bool = false
    ) -> CGFloat {
        apiKeyOnly ? 80 : needsSetup ? 420 : compactReady ? 64 : hasInsights ? 420 : 180
    }

    static func windowHeight(
        apiKeyOnly: Bool,
        needsSetup: Bool,
        compactReady: Bool,
        hasInsights: Bool = false
    ) -> CGFloat {
        apiKeyOnly ? 120 : needsSetup ? 480 : compactReady ? 104 : hasInsights ? 680 : 240
    }

    static func windowWidth(hasInsights: Bool = false) -> CGFloat {
        hasInsights ? 920 : 640
    }
}

struct RioView<Controller: SessionShellControlling>: View {
    private let controller: Controller
    @Environment(\.openWindow) private var openWindow
    @Environment(OpenAIProviderSettings.self) private var providerSettings
    @Environment(RioPanelRouter.self) private var panelRouter
    @Environment(MeetingProfileSettings.self) private var meetingProfileSettings

    init(controller: Controller) {
        self.controller = controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sessionHeader

            if showsSessionStatus {
                sessionStatus
            }

            if showsVoiceFeedback {
                VoiceFeedbackView(
                    status: controller.status,
                    feedbackModel: controller.feedback,
                    failure: controller.failure,
                    unavailableReason: controller.unavailableReason
                )
            }

            content
        }
        .padding(20)
        .frame(
            minWidth: 480,
            idealWidth: hasInsights ? 920 : 560,
            maxWidth: hasInsights ? .infinity : 720,
            minHeight: RioMainWindowSizing.minimumContentHeight(
                apiKeyOnly: setupNeedsOnlyAPIKey,
                needsSetup: shouldShowSetup,
                compactReady: usesCompactReadyLayout,
                hasInsights: hasInsights
            ),
            maxHeight: hasInsights ? .infinity : nil,
            alignment: .topLeading
        )
        .task {
            await controller.checkReadiness()
        }
        .onAppear {
            resizeMainWindowIfNeeded()
        }
        .onChange(of: shouldShowSetup) { _, _ in
            resizeMainWindowIfNeeded()
        }
        .onChange(of: controller.status) { _, _ in
            resizeMainWindowIfNeeded()
        }
        .onChange(of: controller.cards.count) { _, _ in
            resizeMainWindowIfNeeded()
        }
        .sheet(item: Bindable(panelRouter).presentedPanel) { panel in
            switch panel {
            case .provider:
                OpenAIProviderSetupView {
                    Task { await controller.checkReadiness() }
                }
            }
        }
    }

    private var shouldShowSetup: Bool {
        !providerSettings.isConfigured || controller.readiness?.isReady == false
    }

    private var setupNeedsOnlyAPIKey: Bool {
        !providerSettings.isConfigured
    }

    private var usesCompactReadyLayout: Bool {
        controller.status == .stopped && !shouldShowSetup
    }

    private var hasInsights: Bool {
        !controller.cards.isEmpty
    }

    private func resizeMainWindowIfNeeded() {
        // Runs after the current update so the window resizes to the new layout.
        Task { @MainActor in
            guard let window = NSApp.windows.first(where: { $0.title == "Rio" }) else {
                return
            }

            let targetHeight = RioMainWindowSizing.windowHeight(
                apiKeyOnly: setupNeedsOnlyAPIKey,
                needsSetup: shouldShowSetup,
                compactReady: usesCompactReadyLayout,
                hasInsights: hasInsights
            )
            let targetWidth = RioMainWindowSizing.windowWidth(hasInsights: hasInsights)
            guard abs(window.frame.height - targetHeight) > 1
                || abs(window.frame.width - targetWidth) > 1 else {
                return
            }

            var frame = window.frame
            frame.origin.x += (frame.width - targetWidth) / 2
            frame.origin.y += frame.height - targetHeight
            frame.size.width = targetWidth
            frame.size.height = targetHeight
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private var sessionHeader: some View {
        Group {
            if providerSettings.isConfigured {
                HStack(spacing: 20) {
                    meetingProfileControl
                    Spacer(minLength: 0)
                    sessionAction
                }
            }
        }
    }

    private var sessionStatus: some View {
        let presentation = SessionStatusPresentation(
            status: controller.status,
            unavailableReason: controller.unavailableReason,
            failure: controller.failure
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: presentation.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(presentation.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.body.weight(.semibold))
                    Text(presentation.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session status")
            .accessibilityValue("\(presentation.title). \(presentation.detail)")

            if presentation.recoveryAction == .openSystemAudioRecording {
                Button("Open System Settings") {
                    SystemSettingsOpener.openSystemAudioRecording()
                }
                .controlSize(.small)
                .padding(.leading, 40)
                .accessibilityHint("Opens the Screen and System Audio Recording privacy settings for Rio.")
            }
        }
    }

    private var showsSessionStatus: Bool {
        switch controller.status {
        case .checkingAvailability, .paused, .interrupted, .unavailable:
            if controller.status == .unavailable,
               controller.unavailableReason == .openAIAPIKeyMissing,
               !providerSettings.isConfigured {
                return false
            }
            return true
        case .stopped, .listening, .processing:
            return hasMicrophoneFailure
        }
    }

    private var showsVoiceFeedback: Bool {
        controller.status == .listening || controller.status == .processing || hasMicrophoneFailure
    }

    private var hasMicrophoneFailure: Bool {
        if controller.unavailableReason == .microphonePermissionDenied
            || controller.unavailableReason == .audioInputUnavailable {
            return true
        }
        if case .some(.stage(.audioCapture, _)) = controller.failure { return true }
        if case .some(.unavailable(.microphonePermissionDenied)) = controller.failure { return true }
        if case .some(.unavailable(.audioInputUnavailable)) = controller.failure { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if !providerSettings.isConfigured || controller.readiness?.isReady == false {
            ListeningSetupView(
                showsProviderSetup: !providerSettings.isConfigured,
                readiness: controller.readiness,
                openProviderSetup: {
                    panelRouter.showProvider()
                }
            )
        }

        if !controller.cards.isEmpty {
            InsightStreamView(cards: controller.cards)
        }
    }

    private var meetingProfileControl: some View {
        HStack(spacing: 8) {
            if meetingProfileSettings.profiles.isEmpty {
                Text(meetingProfileSettings.defaultProfile.title)
                    .lineLimit(1)
            } else {
                Picker("Meeting profile", selection: Bindable(meetingProfileSettings).selection) {
                    Text(meetingProfileSettings.defaultProfile.title)
                        .tag(meetingProfileSettings.defaultProfile)
                    ForEach(meetingProfileSettings.profiles) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                .disabled(!isStartAction)
            }

            Button("Configure meeting profiles", systemImage: "slider.horizontal.3") {
                openWindow(id: RioWindow.profiles.rawValue)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Configure meeting profiles")
        }
        .font(.subheadline)
        .help(meetingProfileSettings.selection.detail)
    }

    private var primaryAction: some View {
        Button {
            Task {
                await controller.performPrimaryAction()
            }
        } label: {
            Label(controller.primaryActionTitle, systemImage: primaryActionSymbol)
                .frame(minWidth: 170)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("l", modifiers: [.command])
        .disabled(isPrimaryActionDisabled)
        .accessibilityLabel(controller.primaryActionTitle)
        .accessibilityHint(primaryActionHint)
        .help("\(controller.primaryActionTitle) (⌘L)")
    }

    @ViewBuilder
    private var sessionAction: some View {
        if isStartAction && !isReadyForListening && providerSettings.isConfigured {
            Button("Set Up") {
                openSetup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens the settings needed before Rio can listen.")
            .help("Set up listening")
        } else {
            primaryAction
        }
    }

    private var isReadyForListening: Bool {
        providerSettings.isConfigured && controller.readiness?.isReady == true
    }

    private func openSetup() {
        if !providerSettings.isConfigured {
            panelRouter.showProvider()
            return
        }

        if let reason = controller.readiness?.checks.compactMap(\.reason).first {
            switch reason {
            case .openAIAPIKeyMissing, .openAIAPIKeyInvalid:
                panelRouter.showProvider()
            case .microphonePermissionDenied:
                SystemSettingsOpener.openMicrophone()
            case .microphonePermissionUndetermined:
                Task { await controller.performPrimaryAction() }
            case .systemAudioPermissionDenied, .systemAudioCaptureFailed, .systemAudioUnavailable:
                SystemSettingsOpener.openSystemAudioRecording()
            case .audioInputUnavailable:
                Task { await controller.checkReadiness() }
            }
            return
        }

        if let reason = controller.unavailableReason {
            switch reason {
            case .openAIAPIKeyMissing, .openAIAPIKeyInvalid:
                panelRouter.showProvider()
            case .microphonePermissionDenied:
                SystemSettingsOpener.openMicrophone()
            case .systemAudioPermissionDenied, .systemAudioCaptureFailed, .systemAudioUnavailable:
                SystemSettingsOpener.openSystemAudioRecording()
            case .microphonePermissionUndetermined:
                Task { await controller.performPrimaryAction() }
            case .audioInputUnavailable:
                Task { await controller.checkReadiness() }
            }
            return
        }

        Task { await controller.checkReadiness() }
    }

    private var isPrimaryActionDisabled: Bool {
        controller.isPerformingPrimaryAction
            || controller.isPerformingPauseAction
            || (isStartAction && (
                !providerSettings.isConfigured
                    || !controller.isReadyToStartListening
            ))
    }

    private var isStartAction: Bool {
        controller.isStartAction
    }

    private var primaryActionSymbol: String {
        if controller.status == .checkingAvailability { return "hourglass" }
        return isStartAction ? "waveform" : "stop.fill"
    }

    private var primaryActionHint: String {
        if isStartAction && !providerSettings.isConfigured {
            return "Add an OpenAI API key in Provider settings before starting listening."
        }

        if isStartAction && controller.readiness == nil {
            return "Rio is checking whether listening can begin."
        }

        if isStartAction && !controller.isReadyToStartListening {
            return "Complete the listening prerequisites above before starting."
        }

        if isStartAction,
           let readiness = controller.readiness,
           !readiness.isReady {
            return "Start Listening to request the remaining macOS audio permission."
        }

        if controller.status == .checkingAvailability {
            return "Rio is checking whether listening can begin."
        }
        if isStartAction {
            return "Starts a new listening session. Keyboard shortcut Command-L."
        }
        return controller.status == .paused
            ? "Stops the paused session and clears its insights. Keyboard shortcut Command-L."
            : "Stops the current session and clears its insights. Keyboard shortcut Command-L."
    }
}

#Preview("Stopped") {
    RioView(controller: FakeSessionController())
        .previewEnvironment()
}

#Preview("Listening — empty") {
    RioView(controller: FakeSessionController(status: .listening))
        .previewEnvironment()
}

#Preview("Insight cards") {
    RioView(
        controller: FakeSessionController(
            status: .listening,
            cards: [
                InsightCard(
                    stableKey: "preview-important",
                    category: .important,
                    text: "A concise important point appears here.",
                    explicitOwner: nil,
                    state: .new
                ),
                InsightCard(
                    stableKey: "preview-decision",
                    category: .decision,
                    text: "A changed decision is presented as an update.",
                    explicitOwner: nil,
                    state: .updated
                ),
                InsightCard(
                    stableKey: "preview-question",
                    category: .question,
                    text: "A resolved question remains easy to identify.",
                    explicitOwner: nil,
                    state: .resolved
                ),
            ]
        )
    )
    .previewEnvironment()
}

#Preview("Unavailable") {
    RioView(
        controller: FakeSessionController(
            status: .unavailable,
            unavailableReason: .openAIAPIKeyMissing,
            startOutcome: .unavailable(.openAIAPIKeyMissing)
        )
    )
    .previewEnvironment(apiKey: nil)
}

#Preview("Interrupted") {
    RioView(
        controller: FakeSessionController(
            status: .interrupted,
            failure: .stage(.audioCapture, .interrupted),
            startOutcome: .interrupted
        )
    )
    .previewEnvironment()
}

private struct PreviewAPIKeyStore: OpenAIAPIKeyStore {
    let key: String?

    func load() throws -> String? { key }
    func save(_ key: String) throws {}
    func remove() throws {}
}

private extension View {
    /// Previews never touch the real Keychain and always supply every
    /// environment object the session window reads.
    func previewEnvironment(apiKey: String? = "sk-preview") -> some View {
        environment(OpenAIProviderSettings(keyStore: PreviewAPIKeyStore(key: apiKey)))
            .environment(RioPanelRouter())
            .environment(MeetingProfileSettings(defaults: UserDefaults(suiteName: "RioPreviews") ?? .standard))
    }
}

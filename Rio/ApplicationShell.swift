import Combine
import AppKit
import SwiftUI

@MainActor
final class RioPanelRouter: ObservableObject {
    enum Panel: String, Identifiable {
        case provider

        var id: String { rawValue }
    }

    @Published var presentedPanel: Panel?

    func showProvider() {
        presentedPanel = .provider
    }

}

enum SystemSettingsOpener {
    static let screenAndSystemAudioRecordingURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    static func openScreenAndSystemAudioRecording() {
        guard !NSWorkspace.shared.open(screenAndSystemAudioRecordingURL) else {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}

enum FakeSessionStartOutcome: Sendable, Equatable {
    case listening
    case unavailable(UnavailableReason)
    case interrupted
    case failure(PipelineFailure)
}

@MainActor
protocol SessionShellControlling: ObservableObject {
    var status: SessionStatus { get }
    var cards: [InsightCard] { get }
    var feedback: SessionFeedbackSnapshot { get }
    var readiness: SessionReadiness? { get }
    var unavailableReason: UnavailableReason? { get }
    var failure: PipelineFailure? { get }
    var isPerformingPrimaryAction: Bool { get }
    var isPerformingPauseAction: Bool { get }
    var isReadyToStartListening: Bool { get }
    var primaryActionTitle: String { get }
    var pauseActionTitle: String { get }

    func checkReadiness() async
    func performPrimaryAction() async
    func performPauseAction() async
}

@MainActor
final class FakeSessionController: SessionShellControlling {
    @Published private(set) var status: SessionStatus
    @Published private(set) var cards: [InsightCard]
    @Published private(set) var feedback: SessionFeedbackSnapshot
    @Published private(set) var readiness: SessionReadiness?
    @Published private(set) var unavailableReason: UnavailableReason?
    @Published private(set) var failure: PipelineFailure?
    @Published private(set) var isPerformingPrimaryAction = false
    @Published private(set) var isPerformingPauseAction = false

    private let startOutcome: FakeSessionStartOutcome
    private let transitionDelay: Duration

    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(
        status: SessionStatus = .stopped,
        cards: [InsightCard] = [],
        feedback: SessionFeedbackSnapshot = .inactive,
        readiness: SessionReadiness? = nil,
        unavailableReason: UnavailableReason? = nil,
        failure: PipelineFailure? = nil,
        startOutcome: FakeSessionStartOutcome = .listening,
        transitionDelay: Duration = .zero
    ) {
        self.status = status
        self.cards = cards
        self.feedback = feedback
        self.readiness = readiness
        self.unavailableReason = unavailableReason
        self.failure = failure
        self.startOutcome = startOutcome
        self.transitionDelay = transitionDelay
    }

    var primaryActionTitle: String {
        switch status {
        case .listening, .processing:
            "Stop Listening"
        case .checkingAvailability:
            "Checking…"
        case .paused:
            "Stop Listening"
        case .stopped, .interrupted, .unavailable:
            "Start Listening"
        }
    }

    var pauseActionTitle: String {
        status == .paused ? "Resume Listening" : "Pause Listening"
    }

    var isReadyToStartListening: Bool {
        readiness?.isReady == true
    }

    func checkReadiness() async {
        // The fake controller receives readiness through its initializer or inject().
    }

    func performPrimaryAction() async {
        guard !isPerformingPrimaryAction else { return }

        switch status {
        case .listening, .processing:
            await stop()
        case .paused:
            await stop()
        case .stopped, .interrupted, .unavailable:
            await start()
        case .checkingAvailability:
            break
        }
    }

    func performPauseAction() async {
        guard !isPerformingPauseAction else { return }
        guard status == .listening || status == .processing || status == .paused else {
            return
        }
        isPerformingPauseAction = true
        if transitionDelay > .zero {
            try? await Task.sleep(for: transitionDelay)
        }
        status = status == .paused ? .listening : .paused
        isPerformingPauseAction = false
    }

    func inject(
        status: SessionStatus,
        cards: [InsightCard] = [],
        feedback: SessionFeedbackSnapshot = .inactive,
        readiness: SessionReadiness? = nil,
        unavailableReason: UnavailableReason? = nil,
        failure: PipelineFailure? = nil
    ) {
        self.status = status
        self.cards = cards
        self.feedback = feedback
        self.readiness = readiness
        self.unavailableReason = unavailableReason
        self.failure = failure
    }

    private func start() async {
        startCount += 1
        isPerformingPrimaryAction = true
        status = .checkingAvailability
        unavailableReason = nil
        failure = nil

        if transitionDelay > .zero {
            do {
                try await Task.sleep(for: transitionDelay)
            } catch {
                status = .stopped
                isPerformingPrimaryAction = false
                return
            }
        }

        switch startOutcome {
        case .listening:
            status = .listening
            feedback = SessionFeedbackSnapshot(
                audioInput: AudioInputSnapshot(
                    level: 0,
                    hasReceivedAudio: true,
                    isMuted: false
                ),
                finalizedSpeechSegmentCount: 0
            )
        case .unavailable(let reason):
            unavailableReason = reason
            status = .unavailable
        case .interrupted:
            failure = .stage(.sessionLifecycle, .interrupted)
            status = .interrupted
        case .failure(let startFailure):
            apply(startFailure)
        }

        isPerformingPrimaryAction = false
    }

    private func stop() async {
        stopCount += 1
        isPerformingPrimaryAction = true
        cards.removeAll()
        feedback = .inactive
        unavailableReason = nil
        failure = nil
        status = .stopped
        isPerformingPrimaryAction = false
    }

    private func apply(_ startFailure: PipelineFailure) {
        failure = startFailure

        switch startFailure {
        case .unavailable(let reason):
            unavailableReason = reason
            status = .unavailable
        case .stage(_, .interrupted):
            status = .interrupted
        case .stage, .cancelled:
            status = .unavailable
        }
    }
}

struct RioView<Controller: SessionShellControlling>: View {
    @ObservedObject private var controller: Controller
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @EnvironmentObject private var insightHistory: InsightHistoryStore
    @EnvironmentObject private var panelRouter: RioPanelRouter

    init(controller: Controller) {
        self.controller = controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sessionControls

            if showsSessionStatus {
                sessionStatus
            }

            if showsVoiceFeedback {
                VoiceFeedbackView(
                    status: controller.status,
                    feedback: controller.feedback,
                    failure: controller.failure,
                    unavailableReason: controller.unavailableReason
                )
            }

            content
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await controller.checkReadiness()
        }
        .sheet(item: $panelRouter.presentedPanel) { panel in
            switch panel {
            case .provider:
                OpenAIProviderSetupView {
                    Task { await controller.checkReadiness() }
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
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session status")
            .accessibilityValue("\(presentation.title). \(presentation.detail)")

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

    private var hasUnavailablePrerequisite: Bool {
        controller.unavailableReason != nil || controller.readiness?.isReady == false
    }

    @ViewBuilder
    private var content: some View {
        if !providerSettings.isConfigured {
            OpenAIProviderSetupCard {
                panelRouter.showProvider()
            }
        }

        if let readiness = controller.readiness, !readiness.isReady {
            PrerequisiteChecklistView(report: readiness)
        }

        if !controller.cards.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(controller.cards, id: \.stableKey) { card in
                    InsightCardView(card: card)
                }
            }
            .accessibilityLabel("Meeting insights")
        }
    }

    private var sessionControls: some View {
        HStack {
            Spacer()
            primaryAction
            Spacer()
        }
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

    private var isPrimaryActionDisabled: Bool {
        controller.isPerformingPrimaryAction
            || controller.isPerformingPauseAction
            || (isStartAction && (
                !providerSettings.isConfigured
                    || !controller.isReadyToStartListening
            ))
    }

    private var isStartAction: Bool {
        switch controller.status {
        case .stopped, .interrupted, .unavailable:
            true
        case .checkingAvailability, .listening, .processing, .paused:
            false
        }
    }

    private var primaryActionSymbol: String {
        switch controller.status {
        case .listening, .processing:
            "stop.fill"
        case .paused:
            "stop.fill"
        case .checkingAvailability:
            "hourglass"
        case .stopped, .interrupted, .unavailable:
            "waveform"
        }
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

        switch controller.status {
        case .listening, .processing:
            return "Stops the current session and clears its insights. Keyboard shortcut Command-L."
        case .paused:
            return "Stops the paused session and clears its insights. Keyboard shortcut Command-L."
        case .checkingAvailability:
            return "Rio is checking whether listening can begin."
        case .stopped, .interrupted, .unavailable:
            return "Starts a new listening session. Keyboard shortcut Command-L."
        }
    }
}

enum VoiceFeedbackCondition: Equatable {
    case waiting
    case live
    case muted
    case paused
    case connectionError
}

struct VoiceFeedbackPresentation: Equatable {
    let condition: VoiceFeedbackCondition
    let title: String
    let detail: String
    let symbolName: String
    let tintName: SessionStatusPresentation.TintName

    init(
        status: SessionStatus,
        feedback: SessionFeedbackSnapshot,
        failure: PipelineFailure? = nil,
        unavailableReason: UnavailableReason? = nil
    ) {
        let isAudioFailure: Bool = {
            if case .some(.unavailable(.microphonePermissionDenied)) = failure { return true }
            if case .some(.unavailable(.audioInputUnavailable)) = failure { return true }
            if case .some(.stage(.audioCapture, _)) = failure { return true }
            return unavailableReason == .microphonePermissionDenied
                || unavailableReason == .audioInputUnavailable
        }()

        if isAudioFailure {
            condition = .connectionError
            title = "Meeting audio connection error"
            detail = "Audio input stopped. Stop and start listening again."
            symbolName = "mic.slash.fill"
            tintName = .unavailable
        } else if status == .paused {
            condition = .paused
            title = "Listening paused"
            detail = "Meeting audio and transcription are paused."
            symbolName = "pause.circle.fill"
            tintName = .warning
        } else if feedback.audioInput.isMuted {
            condition = .muted
            title = "Meeting audio is silent"
            detail = "No meeting audio detected. Check the browser call and its output device."
            symbolName = "mic.slash"
            tintName = .warning
        } else if feedback.audioInput.hasReceivedAudio {
            condition = .live
            title = "Meeting audio live"
            detail = Self.speechDetail(for: feedback.finalizedSpeechSegmentCount)
            symbolName = "mic.fill"
            tintName = .active
        } else {
            condition = .waiting
            title = "Listening for speech"
            detail = "Meeting audio is ready. Rio will generate insights from the call."
            symbolName = "mic"
            tintName = .active
        }
    }

    private static func speechDetail(for count: Int) -> String {
        guard count > 0 else {
            return "Transcription is active. Collecting finalized message chunks for insights."
        }
        let noun = count == 1 ? "chunk" : "chunks"
        return "Transcription is active. \(count) message \(noun) collected for insights."
    }

    var tint: Color {
        switch tintName {
        case .neutral: .secondary
        case .active: .accentColor
        case .warning: .orange
        case .unavailable: .red
        }
    }
}

private struct VoiceFeedbackView: View {
    let status: SessionStatus
    let feedback: SessionFeedbackSnapshot
    let failure: PipelineFailure?
    let unavailableReason: UnavailableReason?

    var body: some View {
        let presentation = VoiceFeedbackPresentation(
            status: status,
            feedback: feedback,
            failure: failure,
            unavailableReason: unavailableReason
        )

        if presentation.condition == .live || presentation.condition == .waiting {
            HStack(spacing: 12) {
                AudioInputMeterView(
                    level: feedback.audioInput.level,
                    isActive: true
                )
                .frame(width: 72, height: 28)

                Label(presentation.title, systemImage: presentation.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(presentation.tint)

                Spacer(minLength: 0)

                Text("Live chunks sent to OpenAI. Nothing is saved by Rio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice feedback")
            .accessibilityValue("\(presentation.title). \(presentation.detail)")
        } else {
            detailedFeedback(presentation)
        }
    }

    private func detailedFeedback(_ presentation: VoiceFeedbackPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AudioInputMeterView(
                    level: feedback.audioInput.level,
                    isActive: false
                )
                .frame(width: 92, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Label(presentation.title, systemImage: presentation.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(presentation.tint)
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(presentation.tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice feedback")
        .accessibilityValue("\(presentation.title). \(presentation.detail)")
    }
}

private struct AudioInputMeterView: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let centerDistance = abs(Float(index) - 5.5) / 5.5
        let threshold = centerDistance * 0.38
        let normalized = max(0, min(1, (level - threshold) / 0.62))
        return 6 + CGFloat(normalized) * 28
    }
}

private struct PrerequisiteChecklistView: View {
    let report: SessionReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before listening")
                .font(.title3.weight(.semibold))

            ForEach(report.checks) { check in
                let presentation = PrerequisiteCheckPresentation(check: check)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.tint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.title)
                            .font(.body.weight(.medium))
                        Text(presentation.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)

                        if check.kind == .meetingAudio,
                           check.reason == .systemAudioPermissionDenied {
                            Button("Open Screen & System Audio Recording") {
                                SystemSettingsOpener.openScreenAndSystemAudioRecording()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening prerequisites")
    }
}

private struct OpenAIProviderSetupCard: View {
    let openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect OpenAI", systemImage: "key.fill")
                .font(.title3.weight(.semibold))
            Text("Bring your own OpenAI API key to transcribe meeting audio and generate insights. The key stays in your Mac’s Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add OpenAI API key", action: openSetup)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct OpenAIProviderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @EnvironmentObject private var listeningCadenceSettings: ListeningCadenceSettings
    @State private var isShowingKeyDetails = false
    @State private var isConfirmingDeletion = false

    let didChangeConfiguration: () -> Void

    var body: some View {
        Group {
            if isShowingKeyDetails {
                OpenAIAPIKeyDetailsView(
                    didChangeConfiguration: didChangeConfiguration,
                    closeDetails: { isShowingKeyDetails = false }
                )
            } else {
                keyOverview
            }
        }
        .padding(24)
        .frame(width: 440)
        .confirmationDialog(
            "Delete Open AI API key?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                providerSettings.remove()
                didChangeConfiguration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the key from your login Keychain. You can add it again later.")
        }
    }

    private var keyOverview: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Keys")
                    .font(.title2.weight(.bold))
                Text("Stored only in your login Keychain. They are never shown again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Open AI")
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

            Divider()

            listeningCadenceSection

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var listeningCadenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insight pace")
                .font(.headline)
            Text("Choose how much meeting audio Rio groups before asking OpenAI for an update. Longer choices use fewer requests and more context, but insights arrive later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Audio batch", selection: $listeningCadenceSettings.selection) {
                ForEach(ListeningCadence.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }
            .pickerStyle(.segmented)

            Text(listeningCadenceSettings.selection.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("This takes effect the next time you start listening.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OpenAIAPIKeyDetailsView: View {
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @State private var isConfirmingDeletion = false

    let didChangeConfiguration: () -> Void
    let closeDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.title2.weight(.bold))
                Text("Stored only in your login Keychain. It is never shown again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API key")
                    .font(.headline)
                SecureField("Paste a new API key", text: $providerSettings.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage = providerSettings.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if providerSettings.isConfigured {
                    Button(role: .destructive) {
                        isConfirmingDeletion = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                Spacer()
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
        .confirmationDialog(
            "Delete Open AI API key?",
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
            Text("This removes the key from your login Keychain. You can add it again later.")
        }
    }
}

struct RecentInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var insightHistory: InsightHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent insights")
                        .font(.title2.weight(.semibold))
                    Text("Only insight cards from the last two days are kept on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !insightHistory.entries.isEmpty {
                    Button("Clear", role: .destructive) {
                        insightHistory.clear()
                    }
                }
            }

            if insightHistory.entries.isEmpty {
                ContentUnavailableView(
                    "No recent insights",
                    systemImage: "clock",
                    description: Text("Insights from meetings will appear here for two days.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(insightHistory.entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                InsightCardView(card: entry.card)
                                Text(entry.savedAt, format: .dateTime.month().day().hour().minute().second())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540, height: 560)
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

private struct InsightCardView: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(card.category.displayName, systemImage: card.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.category.tint)

                Spacer()

                Text(card.state.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(card.text)
                .font(.body)
                .foregroundStyle(card.state == .resolved ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(card.category.tint.opacity(0.22), lineWidth: 1)
        }
        .opacity(card.state == .resolved ? 0.72 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityDescription)
    }
}

struct SessionStatusPresentation: Equatable {
    let title: String
    let detail: String
    let symbolName: String
    let tintName: TintName

    enum TintName: Equatable {
        case neutral
        case active
        case warning
        case unavailable
    }

    init(
        status: SessionStatus,
        unavailableReason: UnavailableReason? = nil,
        failure: PipelineFailure? = nil
    ) {
        switch status {
        case .stopped:
            title = "Stopped"
            detail = "Nothing from a meeting is being retained."
            symbolName = "stop.circle"
            tintName = .neutral
        case .checkingAvailability:
            title = "Checking availability"
            detail = "Confirming this Mac is ready."
            symbolName = "ellipsis.circle"
            tintName = .neutral
        case .listening:
            title = "Listening"
            detail = "Insights appear as the meeting develops."
            symbolName = "waveform.circle.fill"
            tintName = .active
        case .processing:
            title = "Processing"
            detail = "Refreshing live insights."
            symbolName = "sparkles"
            tintName = .active
        case .paused:
            title = "Paused"
            detail = "Audio input is paused. Your session remains open."
            symbolName = "pause.circle.fill"
            tintName = .warning
        case .interrupted:
            title = "Interrupted"
            detail = "Listening stopped unexpectedly. Start again when ready."
            symbolName = "exclamationmark.circle"
            tintName = .warning
        case .unavailable:
            title = "Unavailable"
            detail = unavailableReason?.guidanceMessage
                ?? failure?.guidanceMessage
                ?? "Rio could not start listening."
            symbolName = "xmark.circle"
            tintName = .unavailable
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

struct EmptyStatePresentation: Equatable {
    let title: String
    let detail: String
    let symbolName: String

    init(
        status: SessionStatus,
        statusDetail: String,
        hasUnavailablePrerequisite: Bool = true
    ) {
        switch status {
        case .stopped:
            title = "Ready to listen"
            detail = "Start listening to see live insights here."
            symbolName = "waveform"
        case .checkingAvailability:
            title = "Getting ready"
            detail = "This should only take a moment."
            symbolName = "hourglass"
        case .listening:
            title = "Listening for useful moments"
            detail = "Important points, decisions, actions, questions, and risks will appear here."
            symbolName = "ear"
        case .processing:
            title = "Insights are on the way"
            detail = "Rio is processing the latest meeting context."
            symbolName = "sparkles"
        case .paused:
            title = "Listening is paused"
            detail = "Resume listening when you are ready."
            symbolName = "pause.circle"
        case .interrupted:
            title = "Listening was interrupted"
            detail = "Start listening to try again."
            symbolName = "exclamationmark.circle"
        case .unavailable:
            if hasUnavailablePrerequisite {
                title = "Rio needs setup"
                detail = "Resolve the unavailable prerequisite above, then try again."
            } else {
                title = "Couldn’t restart listening"
                detail = "Try Start Listening again."
            }
            symbolName = "xmark.circle"
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

private extension UnavailableReason {
    var guidanceMessage: String {
        switch self {
        case .microphonePermissionUndetermined:
            "Click Start Listening and allow microphone access when macOS asks."
        case .microphonePermissionDenied:
            "Open System Settings → Privacy & Security → Microphone and enable Rio."
        case .audioInputUnavailable:
            "Connect or enable a microphone, then try again."
        case .systemAudioPermissionDenied:
            "Click Start Listening to let macOS request access. Then enable Rio here if it appears."
        case .systemAudioUnavailable:
            "Rio could not find a display to capture meeting audio from. Connect or enable a display, then try again."
        case .openAIAPIKeyMissing:
            "Add your OpenAI API key in Rio’s Provider settings. Rio sends bounded, temporary meeting-audio chunks to OpenAI for transcription and temporary meeting text for insights."
        case .openAIAPIKeyInvalid:
            "Rio could not authenticate with OpenAI. Replace the key in Rio’s Provider settings and start listening again."
        }
    }

}

private extension PipelineFailure {
    var guidanceMessage: String {
        switch self {
        case .unavailable(let reason):
            reason.guidanceMessage
        case .stage(.audioCapture, .failed):
            "System audio capture stopped unexpectedly. Rio will retry when it can; otherwise start listening again."
        case .stage(.speechRecognition, .failed):
            "Meeting transcription stopped unexpectedly. Start listening again."
        case .stage(.insightGeneration, .network):
            "Rio could not reach OpenAI for insights. Check your internet connection, then start listening again."
        case .stage(.insightGeneration, .rateLimited):
            "OpenAI rate-limited or quota-limited the insight request. Check your OpenAI project usage, then try again."
        case .stage(.insightGeneration, .serviceUnavailable):
            "OpenAI is temporarily unavailable for insights. Try starting listening again in a moment."
        case .stage(.insightGeneration, .requestRejected(let statusCode)):
            "OpenAI rejected the insight request (HTTP \(statusCode)). Check your project access and try again."
        case .stage(.insightGeneration, .responseInvalid):
            "OpenAI returned an unexpected insight response. Start listening again; if it repeats, check the configured model."
        case .stage(.insightGeneration, .failed):
            "Insight generation stopped unexpectedly. Start listening again."
        case .stage(_, .interrupted):
            "Listening was interrupted."
        case .stage(_, .overloaded):
            "Rio could not keep up with the audio stream."
        case .stage, .cancelled:
            "Rio could not start listening."
        }
    }
}

private extension InsightCategory {
    var displayName: String {
        switch self {
        case .important: "Important"
        case .decision: "Decision"
        case .action: "Action"
        case .question: "Question"
        case .risk: "Risk"
        }
    }

    var symbolName: String {
        switch self {
        case .important: "star.fill"
        case .decision: "checkmark.circle.fill"
        case .action: "arrow.right.circle.fill"
        case .question: "questionmark.circle.fill"
        case .risk: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .important: .indigo
        case .decision: .green
        case .action: .blue
        case .question: .purple
        case .risk: .orange
        }
    }
}

private extension InsightCardState {
    var displayName: String {
        switch self {
        case .new: "New"
        case .updated: "Updated"
        case .resolved: "Resolved"
        }
    }
}

extension InsightCard {
    var accessibilityDescription: String {
        [category.displayName, state.displayName, text].joined(separator: ", ")
    }
}

#Preview("Stopped") {
    RioView(controller: FakeSessionController())
        .environmentObject(OpenAIProviderSettings())
        .environmentObject(InsightHistoryStore())
        .environmentObject(RioPanelRouter())
}

#Preview("Listening — empty") {
    RioView(controller: FakeSessionController(status: .listening))
        .environmentObject(OpenAIProviderSettings())
        .environmentObject(InsightHistoryStore())
        .environmentObject(RioPanelRouter())
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
    .environmentObject(OpenAIProviderSettings())
    .environmentObject(InsightHistoryStore())
    .environmentObject(RioPanelRouter())
}

#Preview("Unavailable") {
    RioView(
        controller: FakeSessionController(
            status: .unavailable,
            unavailableReason: .openAIAPIKeyMissing,
            startOutcome: .unavailable(.openAIAPIKeyMissing)
        )
    )
    .environmentObject(OpenAIProviderSettings())
    .environmentObject(InsightHistoryStore())
    .environmentObject(RioPanelRouter())
}

#Preview("Interrupted") {
    RioView(
        controller: FakeSessionController(
            status: .interrupted,
            failure: .stage(.audioCapture, .interrupted),
            startOutcome: .interrupted
        )
    )
    .environmentObject(OpenAIProviderSettings())
    .environmentObject(InsightHistoryStore())
    .environmentObject(RioPanelRouter())
}

import Combine
import AppKit
import SwiftUI

enum RioLaunchPresentation {
    static let activationPolicy: NSApplication.ActivationPolicy = .accessory
    static let opensMainWindowOnLaunch = false
}

enum RioWindow: String {
    case main
    case profiles
    case recentMeetings = "recent-meetings"
}

@MainActor
struct RioMenuWindowRouter {
    let openWindow: (String) -> Void
    let activate: () -> Void

    func open(_ window: RioWindow) {
        openWindow(window.rawValue)
        activate()
    }
}

@MainActor
final class RioPanelRouter: ObservableObject {
    enum Panel: String, Identifiable {
        case provider
        case profiles

        var id: String { rawValue }
    }

    @Published var presentedPanel: Panel?

    func showProvider() {
        presentedPanel = .provider
    }

    func showProfiles() {
        presentedPanel = .profiles
    }

}

enum SystemSettingsOpener {
    static let microphoneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!

    static let systemAudioRecordingURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    static func openMicrophone() {
        guard !NSWorkspace.shared.open(microphoneURL) else {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }

    static func openSystemAudioRecording() {
        guard !NSWorkspace.shared.open(systemAudioRecordingURL) else {
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

struct RioMenuBarContent<Controller: SessionShellControlling>: View {
    @ObservedObject private var controller: Controller
    @ObservedObject private var providerSettings: OpenAIProviderSettings
    @ObservedObject private var panelRouter: RioPanelRouter
    @Environment(\.openWindow) private var openWindow

    init(
        controller: Controller,
        providerSettings: OpenAIProviderSettings,
        panelRouter: RioPanelRouter
    ) {
        self.controller = controller
        self.providerSettings = providerSettings
        self.panelRouter = panelRouter
    }

    var body: some View {
        Button("Open Rio") {
            windowRouter.open(.main)
        }

        Button {
            Task { await controller.performPrimaryAction() }
        } label: {
            Label(controller.primaryActionTitle, systemImage: primaryActionSystemImage)
        }
        .disabled(!primaryActionIsEnabled)

        if !providerSettings.isConfigured {
            Text("Add an OpenAI API key to start listening")
        } else if isStartAction && !controller.isReadyToStartListening {
            Text("Open Rio to finish listening setup")
        }

        Button("Manage Profiles…") {
            windowRouter.open(.profiles)
        }

        Button("Recent Meetings") {
            windowRouter.open(.recentMeetings)
        }

        Button("Provider & API Key…") {
            panelRouter.showProvider()
            windowRouter.open(.main)
        }

        Divider()

        Button("Quit Rio") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var windowRouter: RioMenuWindowRouter {
        RioMenuWindowRouter(
            openWindow: { openWindow(id: $0) },
            activate: { NSApp.activate(ignoringOtherApps: true) }
        )
    }

    private var primaryActionIsEnabled: Bool {
        !controller.isPerformingPrimaryAction
            && controller.status != .checkingAvailability
            && (!isStartAction || (providerSettings.isConfigured && controller.isReadyToStartListening))
    }

    private var primaryActionSystemImage: String {
        controller.status == .listening || controller.status == .processing
            ? "stop.fill"
            : "record.circle"
    }

    private var isStartAction: Bool {
        switch controller.status {
        case .stopped, .interrupted, .unavailable:
            true
        case .checkingAvailability, .listening, .processing, .paused:
            false
        }
    }
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
        readiness != nil && readiness?.blockingReason == nil
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

enum RioMainWindowSizing {
    static func minimumContentHeight(
        apiKeyOnly: Bool,
        needsSetup: Bool,
        compactReady: Bool
    ) -> CGFloat {
        apiKeyOnly ? 80 : needsSetup ? 420 : compactReady ? 64 : 180
    }

    static func windowHeight(
        apiKeyOnly: Bool,
        needsSetup: Bool,
        compactReady: Bool
    ) -> CGFloat {
        apiKeyOnly ? 120 : needsSetup ? 480 : compactReady ? 104 : 240
    }
}

struct RioView<Controller: SessionShellControlling>: View {
    @ObservedObject private var controller: Controller
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @EnvironmentObject private var panelRouter: RioPanelRouter
    @EnvironmentObject private var meetingProfileSettings: MeetingProfileSettings

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
                    feedback: controller.feedback,
                    failure: controller.failure,
                    unavailableReason: controller.unavailableReason
                )
            }

            content
        }
        .padding(20)
        .frame(
            minWidth: 480,
            idealWidth: 560,
            maxWidth: 720,
            minHeight: RioMainWindowSizing.minimumContentHeight(
                apiKeyOnly: setupNeedsOnlyAPIKey,
                needsSetup: shouldShowSetup,
                compactReady: usesCompactReadyLayout
            ),
            alignment: .topLeading
        )
        .background(.clear)
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
        .sheet(item: $panelRouter.presentedPanel) { panel in
            switch panel {
            case .provider:
                OpenAIProviderSetupView {
                    Task { await controller.checkReadiness() }
                }
            case .profiles:
                MeetingProfileSettingsView()
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

    private func resizeMainWindowIfNeeded() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == "Rio" }) else {
                return
            }

            let targetHeight = RioMainWindowSizing.windowHeight(
                apiKeyOnly: setupNeedsOnlyAPIKey,
                needsSetup: shouldShowSetup,
                compactReady: usesCompactReadyLayout
            )
            guard abs(window.frame.height - targetHeight) > 1 else {
                return
            }

            var frame = window.frame
            frame.origin.y += frame.height - targetHeight
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

    private var hasUnavailablePrerequisite: Bool {
        controller.unavailableReason != nil || controller.readiness?.isReady == false
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
                Label("General meeting guidance", systemImage: "person.crop.circle")
                    .lineLimit(1)
            } else {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Picker("Meeting profile", selection: $meetingProfileSettings.selection) {
                    ForEach(meetingProfileSettings.profiles) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                .disabled(!isStartAction)
            }

            Button {
                openWindow(id: "profiles")
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Configure meeting profiles")
            .accessibilityLabel("Configure meeting profiles")
        }
        .font(.subheadline)
        .help(meetingProfileSettings.profiles.isEmpty ? "Rio uses general meeting guidance until you add a profile." : meetingProfileSettings.selection.detail)
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

        if isStartAction,
           let readiness = controller.readiness,
           !readiness.isReady {
            return "Start Listening to request the remaining macOS audio permission."
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
            detail = Self.speechDetail(for: feedback)
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

    private static func speechDetail(for feedback: SessionFeedbackSnapshot) -> String {
        guard feedback.finalizedSpeechSegmentCount > 0 else {
            return "Transcription is active. Waiting for finalized meeting audio."
        }
        let progress = feedback.latestFinalizedSpeechEndOffset.map {
            " Latest finalized speech: \(Self.elapsedTimestamp($0))."
        } ?? ""
        return "Transcription is active.\(progress)"
    }

    private static func elapsedTimestamp(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = max(0, Int(components.seconds))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
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

                VStack(alignment: .leading, spacing: 2) {
                    Label(presentation.title, systemImage: presentation.symbolName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(presentation.tint)

                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("Audio isn’t saved.")
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

private struct ListeningSetupView: View {
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
                ForEach(Array(unmetChecks.enumerated()), id: \.element.id) { index, check in
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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

struct MeetingProfileSettingsView: View {
    @EnvironmentObject private var meetingProfileSettings: MeetingProfileSettings
    @State private var selectedProfileID: String?
    @State private var showingNewProfile = false
    @State private var newName = ""
    @State private var newGuidance = ""
    @State private var newInsightPace: ListeningCadence = .thirtySeconds
    @State private var newTechnicalVocabulary = ""
    @State private var addError: String?

    var body: some View {
        HStack(spacing: 0) {
            profileList

            Divider()

            VStack(spacing: 0) {
                if showingNewProfile || selectedProfile == nil {
                    newProfileForm
                } else if let selectedProfile {
                    MeetingProfileEditorRow(profile: selectedProfile)
                    .id(selectedProfile.id)
                }
            }
        }
        .onAppear {
            selectInitialProfile()
        }
        .onChange(of: selectedProfileID) { _, newValue in
            if newValue != nil {
                showingNewProfile = false
            }
        }
        .onChange(of: meetingProfileSettings.profiles) { _, profiles in
            guard let selectedProfileID else {
                showingNewProfile = profiles.isEmpty
                return
            }
            guard profiles.contains(where: { $0.id == selectedProfileID }) else {
                self.selectedProfileID = profiles.first?.id
                showingNewProfile = profiles.isEmpty
                return
            }
        }
        .frame(width: 760, height: 560)
    }

    private var selectedProfile: MeetingProfile? {
        guard let selectedProfileID else { return nil }
        return meetingProfileSettings.profiles.first(where: { $0.id == selectedProfileID })
    }

    private var profileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom profiles")
                    .font(.headline)
                Spacer()
                Button {
                    selectedProfileID = nil
                    showingNewProfile = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Create a custom meeting profile")
                .accessibilityLabel("New profile")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List(selection: $selectedProfileID) {
                if meetingProfileSettings.profiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(meetingProfileSettings.profiles) { profile in
                        Label(profile.name, systemImage: "person.crop.circle")
                            .tag(profile.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 250)
    }

    private var newProfileForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A profile is saved on this Mac and applied to the next listening session.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ProfileField(title: "Name") {
                TextField("e.g. Customer support", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }

            ProfileField(title: "Meeting guidance") {
                ProfileTextEditor(
                    text: $newGuidance,
                    placeholder: "Describe what Rio should prioritize in this meeting.",
                    accessibilityLabel: "New profile guidance"
                )
            }

            ProfileField(title: "Insight pace") {
                ListeningCadencePicker(selection: $newInsightPace)
            }

            ProfileField(title: "Technical vocabulary (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    ProfileTextEditor(
                        text: $newTechnicalVocabulary,
                        placeholder: "e.g. SwiftUI, AVAudioEngine, CFErrorDomain",
                        accessibilityLabel: "New profile technical vocabulary"
                    )
                    HStack {
                        Text("Separate terms with commas or new lines. Terms only, not meeting notes.")
                        Spacer()
                        Text("\(newTechnicalVocabulary.count)/\(TranscriptionVocabularyConfiguration.maximumPromptLength)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let addError {
                    Text(addError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Add Profile") { addProfile() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        MeetingProfile.custom(
                            name: newName,
                            guidance: newGuidance,
                            insightPace: newInsightPace,
                            technicalVocabulary: newTechnicalVocabulary
                        ) == nil
                    )
            }
        }
        .padding(20)
    }

    private func selectInitialProfile() {
        guard selectedProfileID == nil else { return }
        if let firstProfile = meetingProfileSettings.profiles.first {
            selectedProfileID = firstProfile.id
        } else {
            showingNewProfile = true
        }
    }

    private func addProfile() {
        guard let profile = meetingProfileSettings.addCustomProfile(
            name: newName,
            guidance: newGuidance,
            insightPace: newInsightPace,
            technicalVocabulary: newTechnicalVocabulary
        ) else {
            addError = "Use a nonempty name and guidance within the field limits."
            return
        }

        newName = ""
        newGuidance = ""
        newInsightPace = .thirtySeconds
        newTechnicalVocabulary = ""
        addError = nil
        selectedProfileID = profile.id
        showingNewProfile = false
    }
}

private struct MeetingProfileEditorRow: View {
    let profile: MeetingProfile

    @EnvironmentObject private var meetingProfileSettings: MeetingProfileSettings
    @State private var name: String
    @State private var guidance: String
    @State private var insightPace: ListeningCadence
    @State private var technicalVocabulary: String
    @State private var saveError: String?

    init(profile: MeetingProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _guidance = State(initialValue: profile.guidance)
        _insightPace = State(initialValue: profile.insightPace)
        _technicalVocabulary = State(initialValue: profile.technicalVocabulary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileField(title: "Name") {
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            ProfileField(title: "Meeting guidance") {
                ProfileTextEditor(
                    text: $guidance,
                    placeholder: "Describe what Rio should prioritize in this meeting.",
                    accessibilityLabel: "Profile guidance"
                )
            }

            ProfileField(title: "Insight pace") {
                ListeningCadencePicker(selection: $insightPace)
            }

            ProfileField(title: "Technical vocabulary (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    ProfileTextEditor(
                        text: $technicalVocabulary,
                        placeholder: "Product names, acronyms, versions, or error-code prefixes",
                        accessibilityLabel: "Profile technical vocabulary"
                    )
                    HStack {
                        Text("Use terms only, not meeting notes.")
                        Spacer()
                        Text("\(technicalVocabulary.count)/\(TranscriptionVocabularyConfiguration.maximumPromptLength)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let saveError {
                    Text(saveError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    meetingProfileSettings.deleteCustomProfile(id: profile.id)
                }
                Button("Save Changes") { saveProfile() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        MeetingProfile.custom(
                            name: name,
                            guidance: guidance,
                            insightPace: insightPace,
                            technicalVocabulary: technicalVocabulary
                        ) == nil
                    )
            }
        }
        .padding(20)
    }

    private func saveProfile() {
        guard meetingProfileSettings.updateCustomProfile(
            id: profile.id,
            name: name,
            guidance: guidance,
            insightPace: insightPace,
            technicalVocabulary: technicalVocabulary
        ) else {
            saveError = "Use a nonempty name and guidance within the field limits."
            return
        }
        saveError = nil
    }

}

private struct ProfileField<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
            content()
        }
    }
}

private struct ListeningCadencePicker: View {
    @Binding var selection: ListeningCadence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Update insights every", selection: $selection) {
                ForEach(ListeningCadence.allCases) { cadence in
                    Text(cadence.shortTitle)
                        .tag(cadence)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Update insights every")
            .accessibilityValue(selection.title)

            Text(selection.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...3)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct OpenAIProviderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
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

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

}

private struct OpenAIAPIKeyDetailsView: View {
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @State private var isConfirmingDeletion = false

    let didChangeConfiguration: () -> Void
    let closeDetails: () -> Void
    let isInitialSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("OpenAI API key")
                .font(.title2.weight(.bold))

            SecureField("Paste API key", text: $providerSettings.apiKey)
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
            Text("This removes the current API key. You can add it again later.")
        }
    }
}

enum RecentMeetingDetailSection: String, CaseIterable, Identifiable {
    case insights
    case transcript

    var id: Self { self }

    var title: String {
        switch self {
        case .insights: "Insights"
        case .transcript: "Transcript"
        }
    }
}

struct RecentTranscriptSegment: Equatable, Identifiable {
    let sequenceNumber: UInt64
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let text: String

    init(
        sequenceNumber: UInt64,
        startOffset: TimeInterval = 0,
        endOffset: TimeInterval = 0,
        text: String
    ) {
        self.sequenceNumber = sequenceNumber
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.text = text
    }

    var id: UInt64 { sequenceNumber }

    var timestamp: String {
        let seconds = max(0, Int(startOffset))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct RecentMeetingDetailPresentation: Equatable {
    let insights: [InsightCard]
    let transcriptSegments: [RecentTranscriptSegment]

    var orderedTranscriptSegments: [RecentTranscriptSegment] {
        transcriptSegments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    func transcriptSegments(matching query: String) -> [RecentTranscriptSegment] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return orderedTranscriptSegments }
        return orderedTranscriptSegments.filter {
            $0.text.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var transcriptText: String {
        orderedTranscriptSegments
            .map(\.text)
            .joined(separator: "\n")
    }
}

/// The meeting history UI expects the history agent to provide:
/// `MeetingHistoryStore.meetings`, `MeetingHistoryStore.clear(meetingID:)`,
/// `MeetingHistoryStore.clearAll()`, and `SavedMeeting` values with `id`,
/// `startedAt`, `endedAt`, `insights`, and `transcriptSegments`. Transcript
/// segments expose `sequenceNumber` and `text`.
struct RecentMeetingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var meetingHistory: MeetingHistoryStore
    @State private var selectedMeetingID: UUID?
    @State private var selectedSection: RecentMeetingDetailSection = .insights
    @State private var meetingPendingDeletion: SavedMeeting?
    @State private var isConfirmingClear = false
    @State private var transcriptQuery = ""

    private var meetings: [SavedMeeting] {
        meetingHistory.meetings.sorted { $0.startedAt > $1.startedAt }
    }

    private var selectedMeeting: SavedMeeting? {
        guard let selectedMeetingID else { return meetings.first }
        return meetings.first { $0.id == selectedMeetingID } ?? meetings.first
    }

    var body: some View {
        HStack(spacing: 0) {
            meetingList

            Divider()

            if let selectedMeeting {
                meetingDetail(selectedMeeting)
            } else {
                ContentUnavailableView(
                    "No recent meetings",
                    systemImage: "clock",
                    description: Text("Completed meetings are kept on this Mac for two days.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 500, idealHeight: 620)
        .onAppear {
            selectFirstMeetingIfNeeded()
        }
        .onChange(of: meetingHistory.meetings) { _, _ in
            selectFirstMeetingIfNeeded()
        }
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: Binding(
                get: { meetingPendingDeletion != nil },
                set: { if !$0 { meetingPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let meetingPendingDeletion {
                    let deletedID = meetingPendingDeletion.id
                    meetingHistory.clear(meetingID: meetingPendingDeletion.id)
                    if selectedMeetingID == deletedID {
                        selectedMeetingID = nil
                    }
                }
                meetingPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                meetingPendingDeletion = nil
            }
        }
        .confirmationDialog(
            "Clear all recent meetings?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                meetingHistory.clearAll()
                selectedMeetingID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved transcripts and insights from this Mac.")
        }
    }

    private var meetingList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent meetings")
                    .font(.headline)
                Spacer()
                if !meetings.isEmpty {
                    Button("Clear All", role: .destructive) {
                        isConfirmingClear = true
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings",
                    systemImage: "clock",
                    description: Text("Saved meetings remain available for two days.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(meetings, selection: $selectedMeetingID) { meeting in
                    Button {
                        selectedMeetingID = meeting.id
                        selectedSection = meeting.profile == .internalTechnical ? .transcript : .insights
                        transcriptQuery = ""
                    } label: {
                        MeetingHistoryRow(meeting: meeting)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Meeting", role: .destructive) {
                            meetingPendingDeletion = meeting
                        }
                    }
                    .tag(meeting.id)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 250)
    }

    @ViewBuilder
    private func meetingDetail(_ meeting: SavedMeeting) -> some View {
        let presentation = RecentMeetingDetailPresentation(
            insights: meeting.insights.map(\.card),
            transcriptSegments: meeting.transcriptSegments.map {
                RecentTranscriptSegment(
                    sequenceNumber: $0.sequenceNumber,
                    startOffset: $0.startOffset,
                    endOffset: $0.endOffset,
                    text: $0.text
                )
            }
        )

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.startedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.title2.weight(.semibold))
                    Text(meetingDuration(for: meeting))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        meeting.profile.title,
                        systemImage: meeting.profile == .internalTechnical
                            ? "wrench.and.screwdriver"
                            : "person.2"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if meeting.incompleteTranscript {
                        Label("Transcript incomplete", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    meetingPendingDeletion = meeting
                } label: {
                    Label("Delete Meeting", systemImage: "trash")
                }
                .help("Delete this meeting's transcript and insights")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Picker("Meeting detail", selection: $selectedSection) {
                ForEach(RecentMeetingDetailSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedSection {
                case .insights:
                    insightsContent(presentation.insights)
                case .transcript:
                    transcriptContent(presentation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
    }

    @ViewBuilder
    private func insightsContent(_ insights: [InsightCard]) -> some View {
        if insights.isEmpty {
            ContentUnavailableView(
                "No insights",
                systemImage: "lightbulb",
                description: Text("Rio did not save any insights for this meeting.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(insights, id: \.stableKey) { card in
                        InsightCardView(card: card)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func transcriptContent(_ presentation: RecentMeetingDetailPresentation) -> some View {
        if presentation.orderedTranscriptSegments.isEmpty {
            ContentUnavailableView(
                "No transcript",
                systemImage: "text.quote",
                description: Text("No finalized meeting text was saved.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let matches = presentation.transcriptSegments(matching: transcriptQuery)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search transcript", text: $transcriptQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search saved transcript")

                if matches.isEmpty {
                    ContentUnavailableView.search(text: transcriptQuery)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matches) { segment in
                                HStack(alignment: .top, spacing: 14) {
                                    Text(segment.timestamp)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58, alignment: .trailing)
                                        .accessibilityLabel("Meeting time \(segment.timestamp)")
                                    Text(segment.text)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func selectFirstMeetingIfNeeded() {
        guard let selectedMeetingID,
              meetings.contains(where: { $0.id == selectedMeetingID }) else {
            selectedMeetingID = meetings.first?.id
            transcriptQuery = ""
            if let first = meetings.first {
                selectedSection = first.profile == .internalTechnical ? .transcript : .insights
            }
            return
        }
    }

    private func meetingDuration(for meeting: SavedMeeting) -> String {
        let seconds = max(0, meeting.endedAt.timeIntervalSince(meeting.startedAt))
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds) % 60
        return minutes > 0
            ? "\(minutes)m \(remainingSeconds)s"
            : "\(remainingSeconds)s"
    }
}

private struct MeetingHistoryRow: View {
    let meeting: SavedMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(meeting.startedAt, format: .dateTime.month().day().hour().minute())
                .font(.body.weight(.medium))
            HStack(spacing: 8) {
                Text(meeting.endedAt, format: .dateTime.hour().minute())
                Text("•")
                Text("\(meeting.transcriptSegments.count) transcript chunks")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if meeting.incompleteTranscript {
                Text("Transcript incomplete")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
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

private struct InsightStreamView: View {
    let cards: [InsightCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Insights")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.stableKey) { index, card in
                        InsightCardView(card: card)

                        if index != cards.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: 520)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting insights")
    }
}

private struct InsightCardView: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(card.category.displayName, systemImage: card.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(card.state.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(card.state == .resolved ? .tertiary : .secondary)
            }

            Text(card.text)
                .font(.body)
                .foregroundStyle(card.state == .resolved ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
    let recoveryAction: SessionRecoveryAction?

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
        recoveryAction = status == .unavailable
            && (unavailableReason == .systemAudioPermissionDenied
                || unavailableReason == .systemAudioCaptureFailed)
            ? .openSystemAudioRecording
            : nil

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

enum SessionRecoveryAction: Equatable {
    case openSystemAudioRecording
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
            "Rio needs System Audio Recording access to listen to meeting audio."
        case .systemAudioCaptureFailed:
            "Rio could not start system audio capture. Confirm the System Audio Recording permission is enabled, then restart Rio."
        case .systemAudioUnavailable:
            "Rio could not find an available system audio output. Connect or enable an audio output, then try again."
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
        case .stage(.speechRecognition, .overloaded):
            "Transcription fell behind and stopped before skipping meeting audio. The transcript saved so far is marked incomplete. Start listening again to resume."
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
            "Rio stopped before skipping meeting audio. The transcript saved so far is marked incomplete. Start listening again to resume."
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
        .environmentObject(RioPanelRouter())
}

#Preview("Listening — empty") {
    RioView(controller: FakeSessionController(status: .listening))
        .environmentObject(OpenAIProviderSettings())
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
    .environmentObject(RioPanelRouter())
}

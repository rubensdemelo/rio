import Combine
import Foundation
import Observation

@MainActor
final class LiveSessionController: SessionShellControlling {
    @Published private(set) var status: SessionStatus = .stopped
    @Published private(set) var cards: [InsightCard] = []
    @Published private(set) var feedback: SessionFeedbackSnapshot = .inactive
    @Published private(set) var readiness: SessionReadiness?
    @Published private(set) var unavailableReason: UnavailableReason?
    @Published private(set) var failure: PipelineFailure?
    @Published private(set) var isPerformingPrimaryAction = false
    @Published private(set) var isPerformingPauseAction = false

    let lifecycle: SessionLifecycleCoordinator
    let insightStore: InMemoryInsightStore
    private let meetingProfileSettings: MeetingProfileSettings?

    private var monitoringTask: Task<Void, Never>?

    init(
        lifecycle: SessionLifecycleCoordinator,
        insightStore: InMemoryInsightStore,
        meetingProfileSettings: MeetingProfileSettings? = nil
    ) {
        self.lifecycle = lifecycle
        self.insightStore = insightStore
        self.meetingProfileSettings = meetingProfileSettings
        observeInsightStore()
        status = lifecycle.status
        readiness = lifecycle.readiness
        cards = insightStore.cards
        Task { @MainActor [weak self] in
            await self?.refreshSnapshot()
        }
    }

    var primaryActionTitle: String {
        switch status {
        case .listening, .processing:
            "Stop Listening"
        case .paused:
            "Stop Listening"
        case .checkingAvailability:
            "Checking…"
        case .stopped, .unavailable:
            "Start Listening"
        case .interrupted:
            failure == nil ? "Stop Listening" : "Start Listening"
        }
    }

    var pauseActionTitle: String {
        status == .paused ? "Resume Listening" : "Pause Listening"
    }

    var isReadyToStartListening: Bool {
        // Permission states that macOS can request or re-check only when the
        // capture starts must not disable the action that triggers that check.
        readiness != nil && readiness?.blockingReason == nil
    }

    func checkReadiness() async {
        _ = await lifecycle.checkReadiness()
        await refreshSnapshot()
    }

    func performPrimaryAction() async {
        guard !isPerformingPrimaryAction else {
            return
        }

        isPerformingPrimaryAction = true
        defer { isPerformingPrimaryAction = false }

        switch lifecycle.status {
        case .listening, .processing, .paused:
            await stopListening()
        case .stopped, .unavailable:
            await startListening()
        case .interrupted:
            if lifecycle.failure == nil {
                await stopListening()
            } else {
                await startListening()
            }
        case .checkingAvailability:
            break
        }

        await refreshSnapshot()
    }

    private func startListening() async {
        if !isReadyToStartListening {
            await checkReadiness()
        }
        guard isReadyToStartListening else { return }

        failure = nil
        unavailableReason = nil
        do {
            await lifecycle.configure(
                profile: meetingProfileSettings?.selection ?? .fallback
            )
            try await lifecycle.start()
            startMonitoring()
        } catch let startFailure {
            apply(startFailure)
            stopMonitoring()
        }
    }

    private func stopListening() async {
        await lifecycle.stop()
        stopMonitoring()
    }

    func performPauseAction() async {
        guard !isPerformingPauseAction else { return }
        guard lifecycle.status == .listening || lifecycle.status == .processing || lifecycle.status == .paused else {
            return
        }

        isPerformingPauseAction = true
        defer { isPerformingPauseAction = false }

        if lifecycle.status == .paused {
            do {
                try await lifecycle.resume()
                startMonitoring()
            } catch let resumeFailure {
                apply(resumeFailure)
                stopMonitoring()
            }
        } else {
            await lifecycle.pause()
            startMonitoring()
        }
        await refreshSnapshot()
    }

    private func startMonitoring() {
        stopMonitoring()
        monitoringTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshSnapshot()
                switch self.lifecycle.status {
                case .stopped, .unavailable:
                    return
                case .interrupted where self.lifecycle.failure != nil:
                    return
                case .checkingAvailability, .listening, .processing, .paused, .interrupted:
                    // The input meter is visual feedback, not a real-time
                    // control. Ten updates per second keeps it responsive
                    // without continuously invalidating the card list.
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    private func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func refreshSnapshot() async {
        let nextStatus = lifecycle.status
        let nextReadiness = lifecycle.readiness
        let nextFailure = lifecycle.failure
        if status != nextStatus { status = nextStatus }
        if readiness != nextReadiness { readiness = nextReadiness }
        if failure != nextFailure { failure = nextFailure }
        if case let .unavailable(reason)? = failure {
            if unavailableReason != reason { unavailableReason = reason }
        } else if unavailableReason != nil {
            unavailableReason = nil
        }
        let nextFeedback = await lifecycle.feedbackSnapshot()
        let nextCards = insightStore.cards
        if feedback != nextFeedback { feedback = nextFeedback }
        if cards != nextCards { cards = nextCards }
    }

    private func observeInsightStore() {
        withObservationTracking {
            cards = insightStore.cards
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeInsightStore()
            }
        }
    }

    private func apply(_ startFailure: PipelineFailure) {
        failure = startFailure
        switch startFailure {
        case .unavailable(let reason):
            unavailableReason = reason
        case .stage, .cancelled:
            unavailableReason = nil
        }
        status = lifecycle.status
    }
}

@MainActor
enum RioCompositionRoot {
    static let defaultLocaleIdentifier = "en-US"

    static func makeLiveController(
        meetingHistory: MeetingHistoryStore? = nil,
        meetingProfileSettings: MeetingProfileSettings? = nil,
        apiKeyStore: any OpenAIAPIKeyStore = KeychainOpenAIAPIKeyStore()
    ) -> LiveSessionController {
        let localeIdentifier = defaultLocaleIdentifier
        let capture = CoreAudioSystemAudioCapture()
        let configurationProvider: @Sendable () -> OpenAIAPIConfiguration? = {
            OpenAIAPIConfiguration.stored(keyStore: apiKeyStore)
        }
        let speechRecognizer = OpenAITranscriptionAdapter(
            configurationProvider: configurationProvider,
            batchDuration: meetingProfileSettings?.selection.insightPace.audioBatchDuration
                ?? ListeningCadence.thirtySeconds.audioBatchDuration
        )
        let contextFactory = BoundedMeetingContextFactory(
            configuration: MeetingContextConfiguration(
                maximumAge: .seconds(180),
                maximumTokenCount: 2_000,
                maximumUTF8ByteCount: 20_000,
                batchTokenThreshold: 250,
                maximumBatchWait: .seconds(10)
            ),
            clock: ContinuousMeetingContextClock(),
            tokenEstimator: { text in
                max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
            }
        )
        let insightStore = InMemoryInsightStore()
        let insightGenerator: any SessionInsightGenerator = OpenAIInsightGenerator(
            configurationProvider: configurationProvider
        )
        let historyRecorder: any MeetingHistoryRecording = meetingHistory.map {
            MeetingHistoryStoreRecorder(store: $0)
        } ?? NoopMeetingHistoryRecorder()
        let lifecycle = SessionLifecycleCoordinator(
            localeIdentifier: localeIdentifier,
            capture: capture,
            speechRecognizer: speechRecognizer,
            contextFactory: contextFactory,
            insightGenerator: insightGenerator,
            insightState: insightStore,
            historyRecorder: historyRecorder
        )
        return LiveSessionController(
            lifecycle: lifecycle,
            insightStore: insightStore,
            meetingProfileSettings: meetingProfileSettings
        )
    }
}

@MainActor
private final class MeetingHistoryStoreRecorder: MeetingHistoryRecording {
    private let store: MeetingHistoryStore

    init(store: MeetingHistoryStore) {
        self.store = store
    }

    func record(_ meeting: MeetingHistoryRecord) {
        let savedMeeting = SavedMeeting(
            id: meeting.meetingID,
            startedAt: meeting.startedAt,
            endedAt: meeting.endedAt,
            transcriptSegments: meeting.transcript.map { segment in
                SavedTranscriptSegment(
                    sequenceNumber: segment.sequenceNumber,
                    startOffset: segment.startOffset.timeInterval,
                    endOffset: segment.endOffset.timeInterval,
                    text: segment.text
                )
            },
            insights: meeting.insights.map { card in
                SavedInsight(
                    sessionID: meeting.meetingID,
                    card: card,
                    savedAt: card.changedAt
                )
            },
            incompleteTranscript: meeting.incompleteTranscript,
            profile: meeting.profile
        )
        store.record(savedMeeting, now: meeting.endedAt)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

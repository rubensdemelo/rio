import Foundation

protocol SessionAudioCapture: AudioCapture {
    func permission() async -> MicrophonePermission
    func checkAvailability() async -> Availability
    func inputSnapshot() async -> AudioInputSnapshot
}

protocol SessionSpeechRecognizer: TemporarySpeechRecognizer {
    func availability() async -> Availability
    func prepare() async throws(PipelineFailure)
    func configure(batchDuration: Duration, transcriptionPrompt: String?) async
    func pause() async
}

protocol SessionInsightGenerator: InsightGenerator {
    func availability() async -> Availability
    func supportsLocale(identifier: String) async -> Bool
    func startSession(localeIdentifier: String) async throws(PipelineFailure)
    func stop() async
}

protocol MeetingContextFactory: Sendable {
    func makeContext() -> any RollingMeetingContext
}

private enum InsightRetryPolicy {
    static let maximumRetries = 3

    static func shouldRetry(_ failure: PipelineFailure) -> Bool {
        guard case .stage(.insightGeneration, let reason) = failure else {
            return false
        }
        switch reason {
        case .network, .rateLimited, .serviceUnavailable, .failed, .responseInvalid:
            return true
        case .interrupted, .overloaded, .invalidState, .requestRejected:
            return false
        }
    }

    static func delay(for retryNumber: Int) -> Duration {
        switch retryNumber {
        case 1: .seconds(1)
        case 2: .seconds(2)
        default: .seconds(4)
        }
    }
}

struct BoundedMeetingContextFactory: MeetingContextFactory, Sendable {
    let configuration: MeetingContextConfiguration
    let tokenEstimator: BoundedRollingMeetingContext.TokenEstimator
    let clock: any MeetingContextClock

    init(
        configuration: MeetingContextConfiguration,
        clock: any MeetingContextClock,
        tokenEstimator: @escaping BoundedRollingMeetingContext.TokenEstimator
    ) {
        self.configuration = configuration
        self.clock = clock
        self.tokenEstimator = tokenEstimator
    }

    func makeContext() -> any RollingMeetingContext {
        BoundedRollingMeetingContext(
            configuration: configuration,
            clock: clock,
            tokenEstimator: tokenEstimator
        )
    }
}

@MainActor
final class SessionLifecycleCoordinator: SessionLifecycle {
    private enum CleanupKind {
        case stop
        case sustainedSilence
        case cancel
        case failure(PipelineFailure)
    }

    private static let sustainedSilenceTimeout: Duration = .seconds(600)

    private let localeIdentifier: String
    private let capture: any SessionAudioCapture
    private let speechRecognizer: any SessionSpeechRecognizer
    private let contextFactory: any MeetingContextFactory
    private let insightGenerator: any SessionInsightGenerator
    private let insightState: any InsightState
    private let transcriptCollector: any TranscriptCollecting
    private let historyRecorder: any MeetingHistoryRecording
    private let failureRecorder: any SessionFailureRecording
    private let captureRecoveryDelays: [Duration]
    private let captureInactivityTimeout: Duration

    private(set) var status: SessionStatus = .stopped
    private(set) var failure: PipelineFailure?
    private(set) var readiness: SessionReadiness?

    private var nextSessionID: UInt64 = 0
    private var activeSessionID: UInt64?
    private var activeContext: (any RollingMeetingContext)?
    private var audioForwardingTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var finalizedSpeechSegmentCount = 0
    private var latestFinalizedSpeechEndOffset: Duration?
    private var activeMeetingID: UUID?
    private var activeMeetingStartedAt: Date?
    private var incompleteTranscript = false
    private var configuredProfile: MeetingProfile = .fallback
    private var activeMeetingProfile: MeetingProfile = .fallback

    init(
        localeIdentifier: String,
        capture: any SessionAudioCapture,
        speechRecognizer: any SessionSpeechRecognizer,
        contextFactory: any MeetingContextFactory,
        insightGenerator: any SessionInsightGenerator,
        insightState: any InsightState,
        transcriptCollector: any TranscriptCollecting = InMemoryTranscriptCollector(),
        historyRecorder: any MeetingHistoryRecording = NoopMeetingHistoryRecorder(),
        failureRecorder: any SessionFailureRecording = UnifiedSessionFailureRecorder(),
        captureInactivityTimeout: Duration = .seconds(5),
        captureRecoveryDelays: [Duration] = [
            .zero,
            .milliseconds(500),
            .seconds(2),
            .seconds(5),
        ]
    ) {
        precondition(captureInactivityTimeout > .zero)
        self.localeIdentifier = localeIdentifier
        self.capture = capture
        self.speechRecognizer = speechRecognizer
        self.contextFactory = contextFactory
        self.insightGenerator = insightGenerator
        self.insightState = insightState
        self.transcriptCollector = transcriptCollector
        self.historyRecorder = historyRecorder
        self.failureRecorder = failureRecorder
        self.captureInactivityTimeout = captureInactivityTimeout
        self.captureRecoveryDelays = captureRecoveryDelays
    }

    func checkAvailability() async -> Availability {
        let report = await checkReadiness()
        guard let reason = report.blockingReason
            ?? report.checks.compactMap(\.reason).first else {
            return .available
        }
        return .unavailable(reason)
    }

    func configure(cadence: ListeningCadence) async {
        await configure(
            cadence: cadence,
            profile: .fallback
        )
    }

    func configure(profile: MeetingProfile) async {
        guard activeSessionID == nil else { return }
        await speechRecognizer.configure(
            batchDuration: profile.insightPace.audioBatchDuration,
            transcriptionPrompt: profile.transcriptionPrompt
        )
        configuredProfile = profile
        if let profileGenerator = insightGenerator as? any ProfileConfigurableInsightGenerator {
            await profileGenerator.configure(profile: profile)
        }
    }

    func configure(
        cadence: ListeningCadence,
        profile: MeetingProfile
    ) async {
        guard activeSessionID == nil else { return }
        await speechRecognizer.configure(
            batchDuration: cadence.audioBatchDuration,
            transcriptionPrompt: profile.transcriptionPrompt
        )
        configuredProfile = profile
        if let profileGenerator = insightGenerator as? any ProfileConfigurableInsightGenerator {
            await profileGenerator.configure(profile: profile)
        }
    }

    func checkReadiness() async -> SessionReadiness {
        let captureAvailability = await capture.checkAvailability()

        let meetingAudioReason: UnavailableReason? = {
            if case .unavailable(let reason) = captureAvailability {
                return reason
            }
            return nil
        }()

        let speechPreparationFailure: PipelineFailure?
        do {
            try await speechRecognizer.prepare()
            speechPreparationFailure = nil
        } catch let failure {
            speechPreparationFailure = failure
        }
        let speechAvailability = await speechRecognizer.availability()
        let speechReason: UnavailableReason?
        if case .unavailable(let reason) = speechAvailability {
            speechReason = reason
        } else {
            speechReason = speechPreparationFailure.flatMap { failure in
                if case .unavailable(let reason) = failure {
                    return reason
                }
                return .openAIAPIKeyMissing
            }
        }

        let modelAvailability = await insightGenerator.availability()
        let modelReason: UnavailableReason?
        switch modelAvailability {
        case .available:
            let supportsLocale = await insightGenerator.supportsLocale(
                identifier: localeIdentifier
            )
            modelReason = supportsLocale ? nil : .openAIAPIKeyMissing
        case .unavailable(let reason):
            modelReason = reason
        }

        let report = SessionReadiness(
            checks: [
                PrerequisiteCheck(kind: .meetingAudio, reason: meetingAudioReason),
                PrerequisiteCheck(kind: .meetingTranscription, reason: speechReason),
                PrerequisiteCheck(kind: .openAI, reason: modelReason),
            ]
        )
        readiness = report
        return report
    }

    func start() async throws(PipelineFailure) {
        guard activeSessionID == nil, status != .checkingAvailability else {
            let failure = PipelineFailure.stage(.sessionLifecycle, .invalidState)
            failureRecorder.record(failure)
            throw failure
        }

        do {
            try await startAttempt()
        } catch let failure {
            guard shouldRetryStartup(after: failure), !Task.isCancelled else {
                throw failure
            }

            // Native capture and speech services can report cancellation while a
            // previous session is still releasing. Cleanup completed before this
            // point, so retry once with a fresh, entirely in-memory pipeline.
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                throw .cancelled
            }
            try await startAttempt()
        }
    }

    private func startAttempt() async throws(PipelineFailure) {
        nextSessionID &+= 1
        let sessionID = nextSessionID
        activeSessionID = sessionID
        activeContext = contextFactory.makeContext()
        insightState.reset()
        transcriptCollector.reset()
        finalizedSpeechSegmentCount = 0
        latestFinalizedSpeechEndOffset = nil
        activeMeetingID = UUID()
        activeMeetingStartedAt = Date()
        activeMeetingProfile = configuredProfile
        incompleteTranscript = false
        failure = nil
        status = .checkingAvailability

        do {
            try await preflight()
            try ensureActive(sessionID)

            try await insightGenerator.startSession(localeIdentifier: localeIdentifier)
            try ensureActive(sessionID)

            let audio = try await capture.start()
            try ensureActive(sessionID)

            let forwardedAudio = makeForwardedAudioStream(audio, sessionID: sessionID)
            audioForwardingTask = forwardedAudio.task
            let speech = try await speechRecognizer.recognize(audio: forwardedAudio.stream)
            try ensureActive(sessionID)

            speechTask = Task { [weak self] in
                await self?.consumeSpeech(speech, sessionID: sessionID)
            }
            generationTask = Task { [weak self] in
                await self?.generateBatches(sessionID: sessionID)
            }
            readiness = SessionReadiness(
                checks: readiness?.checks.map {
                    PrerequisiteCheck(kind: $0.kind, reason: nil)
                } ?? []
            )
            status = .listening
        } catch {
            let failure = error
            await cleanup(sessionID: sessionID, kind: .failure(failure))
            throw failure
        }
    }

    private func shouldRetryStartup(after failure: PipelineFailure) -> Bool {
        switch failure {
        case .cancelled,
             .stage(.speechRecognition, .invalidState),
             .stage(.insightGeneration, .invalidState):
            true
        case .unavailable, .stage:
            false
        }
    }

    func stop() async {
        guard let sessionID = activeSessionID else {
            status = .stopped
            insightState.reset()
            return
        }
        await cleanup(sessionID: sessionID, kind: .stop)
    }

    func pause() async {
        guard let sessionID = activeSessionID,
              status == .listening || status == .processing else {
            return
        }

        let audioTask = audioForwardingTask
        let speechTask = speechTask
        let generationTask = generationTask
        audioForwardingTask = nil
        self.speechTask = nil
        self.generationTask = nil

        status = .paused

        audioTask?.cancel()
        speechTask?.cancel()
        generationTask?.cancel()
        await speechRecognizer.pause()
        await capture.stop()
        guard activeSessionID == sessionID else { return }
    }

    func resume() async throws(PipelineFailure) {
        guard let sessionID = activeSessionID, status == .paused else {
            let failure = PipelineFailure.stage(.sessionLifecycle, .invalidState)
            failureRecorder.record(failure)
            throw failure
        }

        do {
            let audio = try await capture.start()
            try ensureActive(sessionID)

            let forwardedAudio = makeForwardedAudioStream(audio, sessionID: sessionID)
            audioForwardingTask = forwardedAudio.task
            let speech = try await speechRecognizer.recognize(audio: forwardedAudio.stream)
            try ensureActive(sessionID)

            speechTask = Task { [weak self] in
                await self?.consumeSpeech(speech, sessionID: sessionID)
            }
            generationTask = Task { [weak self] in
                await self?.generateBatches(sessionID: sessionID)
            }
            status = .listening
        } catch {
            let failure = error
            await cleanup(sessionID: sessionID, kind: .failure(failure))
            throw failure
        }
    }

    func cancel() async {
        guard let sessionID = activeSessionID else {
            status = .stopped
            insightState.reset()
            return
        }
        await cleanup(sessionID: sessionID, kind: .cancel)
    }

    private func preflight() async throws(PipelineFailure) {
        let report = await checkReadiness()
        if let reason = report.blockingReason {
            throw .unavailable(reason)
        }
    }

    private func consumeSpeech(
        _ stream: FinalizedSpeechStream,
        sessionID: UInt64
    ) async {
        guard let context = activeContext else {
            return
        }

        do {
            for try await segment in stream {
                guard activeSessionID == sessionID else {
                    return
                }
                try await context.append(segment)
                transcriptCollector.append(segment)
                finalizedSpeechSegmentCount += 1
                latestFinalizedSpeechEndOffset = segment.endOffset
                guard activeSessionID == sessionID else {
                    return
                }
            }
        } catch let failure as PipelineFailure {
            if failure == .cancelled, status == .paused {
                return
            }
            incompleteTranscript = true
            await fail(failure, sessionID: sessionID)
        } catch is CancellationError {
            if status == .paused {
                return
            }
            incompleteTranscript = true
            await fail(.cancelled, sessionID: sessionID)
        } catch {
            incompleteTranscript = true
            await fail(.stage(.speechRecognition, .failed), sessionID: sessionID)
        }
    }

    private func generateBatches(sessionID: UInt64) async {
        guard let context = activeContext else {
            return
        }

        do {
            while activeSessionID == sessionID {
                guard let batch = try await context.nextBatch() else {
                    return
                }
                guard activeSessionID == sessionID else {
                    return
                }

                status = .processing
                let generationBatch = MeetingContextBatch(
                    segments: batch.segments,
                    newSegments: batch.newSegments,
                    currentInsights: insightState.cards
                )
                let updates = try await generateInsights(
                    for: generationBatch,
                    sessionID: sessionID
                )
                guard activeSessionID == sessionID else {
                    return
                }
                try insightState.apply(updates, supportedBy: generationBatch)
                status = .listening
            }
        } catch let failure {
            if failure == .cancelled, status == .paused {
                return
            }
            await fail(failure, sessionID: sessionID)
        }
    }

    private func generateInsights(
        for batch: MeetingContextBatch,
        sessionID: UInt64
    ) async throws(PipelineFailure) -> [InsightUpdate] {
        var retryNumber = 0

        while true {
            do {
                return try await insightGenerator.generate(from: batch)
            } catch let failure {
                guard InsightRetryPolicy.shouldRetry(failure) else {
                    throw failure
                }

                guard retryNumber < InsightRetryPolicy.maximumRetries else {
                    // Keep capture and finalized-transcript collection alive.
                    // The bounded batch has already been delivered to this
                    // method and is intentionally skipped only after retries
                    // are exhausted.
                    return []
                }

                retryNumber += 1
                await insightGenerator.stop()
                try ensureActive(sessionID)
                do {
                    try await Task.sleep(
                        for: InsightRetryPolicy.delay(for: retryNumber)
                    )
                } catch {
                    throw .cancelled
                }
                try ensureActive(sessionID)
                try await insightGenerator.startSession(localeIdentifier: localeIdentifier)
                try ensureActive(sessionID)
            }
        }
    }

    private func fail(_ failure: PipelineFailure, sessionID: UInt64) async {
        guard activeSessionID == sessionID else {
            return
        }
        if case .stage(.audioCapture, _) = failure {
            incompleteTranscript = true
        }
        await cleanup(sessionID: sessionID, kind: .failure(failure))
    }

    private func cleanup(sessionID: UInt64, kind: CleanupKind) async {
        guard activeSessionID == sessionID else {
            return
        }

        if case .failure(let failure) = kind {
            failureRecorder.record(failure)
        }

        let transcript = transcriptCollector.snapshot()
        let insights = insightState.cards
        let meetingRecord: MeetingHistoryRecord? = {
            let shouldRecord: Bool
            switch kind {
            case .stop:
                shouldRecord = true
            case .sustainedSilence:
                shouldRecord = !transcript.isEmpty || !insights.isEmpty
            case .failure:
                shouldRecord = status != .checkingAvailability
            case .cancel:
                shouldRecord = false
            }
            guard shouldRecord,
                  let meetingID = activeMeetingID,
                  let startedAt = activeMeetingStartedAt else {
                return nil
            }
            return MeetingHistoryRecord(
                meetingID: meetingID,
                startedAt: startedAt,
                endedAt: Date(),
                transcript: transcript,
                insights: insights,
                incompleteTranscript: incompleteTranscript,
                profile: activeMeetingProfile
            )
        }()

        activeSessionID = nil
        finalizedSpeechSegmentCount = 0
        latestFinalizedSpeechEndOffset = nil
        activeMeetingID = nil
        activeMeetingStartedAt = nil
        incompleteTranscript = false
        let context = activeContext
        activeContext = nil

        let audioTask = audioForwardingTask
        let speechTask = speechTask
        let generationTask = generationTask
        audioForwardingTask = nil
        self.speechTask = nil
        self.generationTask = nil

        audioTask?.cancel()
        speechTask?.cancel()
        generationTask?.cancel()

        switch kind {
        case .stop, .sustainedSilence:
            await speechRecognizer.stop()
            await capture.stop()
            await insightGenerator.stop()
        case .cancel, .failure:
            await speechRecognizer.cancel()
            await capture.cancel()
            await insightGenerator.cancel()
        }

        await context?.cancel()
        await context?.clear()
        insightState.reset()

        switch kind {
        case .failure(let failure):
            self.failure = failure
            status = status(for: failure)
        case .stop, .sustainedSilence, .cancel:
            failure = nil
            status = .stopped
        }

        if let meetingRecord {
            historyRecorder.record(meetingRecord)
        }

        transcriptCollector.reset()
    }

    private func stopForSustainedSilence(sessionID: UInt64) async {
        guard activeSessionID == sessionID else {
            return
        }

        // This is called by the forwarding task itself. Detach its handle before
        // cleanup so that cleanup never tries to cancel its currently executing task.
        audioForwardingTask = nil
        await cleanup(sessionID: sessionID, kind: .sustainedSilence)
    }

    private func makeForwardedAudioStream(
        _ source: AudioStream,
        sessionID: UInt64
    ) -> (stream: AudioStream, task: Task<Void, Never>) {
        var continuation: AudioStream.Continuation?
        let stream = AudioStream { continuation = $0 }
        let task = Task { [weak self] in
            var currentSource = source
            var nextRecoveryAttempt = 0
            var consecutiveSilence = Duration.zero

            while let self {
                var inactivityTask = makeCaptureInactivityTask(sessionID: sessionID)
                do {
                    for try await chunk in currentSource {
                        inactivityTask.cancel()
                        nextRecoveryAttempt = 0
                        if status == .interrupted {
                            status = .listening
                        }
                        if chunk.inputLevel < AudioChunk.signalThreshold {
                            consecutiveSilence += chunk.duration
                            if consecutiveSilence >= Self.sustainedSilenceTimeout {
                                await stopForSustainedSilence(sessionID: sessionID)
                                continuation?.finish()
                                return
                            }
                        } else {
                            consecutiveSilence = .zero
                        }
                        continuation?.yield(chunk)
                        inactivityTask = makeCaptureInactivityTask(sessionID: sessionID)
                    }
                    inactivityTask.cancel()
                    guard !Task.isCancelled,
                          activeSessionID == sessionID,
                          status != .paused else {
                        continuation?.finish(throwing: PipelineFailure.cancelled)
                        return
                    }
                    throw PipelineFailure.stage(.audioCapture, .interrupted)
                } catch {
                    inactivityTask.cancel()
                    let reportedFailure = normalizedCaptureFailure(error)
                    if let recoveredSource = await recoverCapture(
                        from: reportedFailure,
                        sessionID: sessionID,
                        nextAttempt: &nextRecoveryAttempt
                    ) {
                        currentSource = recoveredSource
                        continue
                    }
                    continuation?.finish(throwing: reportedFailure)
                    await fail(reportedFailure, sessionID: sessionID)
                    return
                }
            }
            continuation?.finish(throwing: PipelineFailure.cancelled)
        }
        return (stream, task)
    }

    private func makeCaptureInactivityTask(
        sessionID: UInt64
    ) -> Task<Void, Never> {
        let timeout = captureInactivityTimeout
        return Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  activeSessionID == sessionID else {
                return
            }
            await capture.cancel()
        }
    }

    private func normalizedCaptureFailure(_ error: any Error) -> PipelineFailure {
        if let failure = error as? PipelineFailure {
            return failure == .cancelled
                ? .stage(.audioCapture, .interrupted)
                : failure
        }
        if error is CancellationError {
            return .stage(.audioCapture, .interrupted)
        }
        return .stage(.audioCapture, .failed)
    }

    private func recoverCapture(
        from failure: PipelineFailure,
        sessionID: UInt64,
        nextAttempt: inout Int
    ) async -> AudioStream? {
        guard failure == .stage(.audioCapture, .interrupted),
              activeSessionID == sessionID,
              !Task.isCancelled else {
            return nil
        }

        incompleteTranscript = true
        self.failure = nil
        status = .interrupted

        while nextAttempt < captureRecoveryDelays.count {
            let delay = captureRecoveryDelays[nextAttempt]
            nextAttempt += 1
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return nil
                }
            }

            guard activeSessionID == sessionID, !Task.isCancelled else {
                return nil
            }

            do {
                let recoveredSource = try await capture.start()
                try ensureActive(sessionID)
                return recoveredSource
            } catch {
                // Core Audio route changes can remain unavailable briefly while
                // macOS rebuilds the device graph. Retry only within this bound.
            }
        }

        return nil
    }

    func feedbackSnapshot() async -> SessionFeedbackSnapshot {
        guard activeSessionID != nil else {
            return .inactive
        }
        return SessionFeedbackSnapshot(
            audioInput: await capture.inputSnapshot(),
            finalizedSpeechSegmentCount: finalizedSpeechSegmentCount,
            latestFinalizedSpeechEndOffset: latestFinalizedSpeechEndOffset
        )
    }

    private func ensureActive(_ sessionID: UInt64) throws(PipelineFailure) {
        guard activeSessionID == sessionID, !Task.isCancelled else {
            throw .cancelled
        }
    }

    private func availabilityFailure(for availability: Availability) -> PipelineFailure {
        switch availability {
        case .available:
            return .stage(.sessionLifecycle, .invalidState)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    private func availability(for failure: PipelineFailure) -> Availability {
        switch failure {
        case .unavailable(let reason):
            return .unavailable(reason)
        case .stage, .cancelled:
            return .unavailable(.openAIAPIKeyMissing)
        }
    }

    private func status(for failure: PipelineFailure) -> SessionStatus {
        switch failure {
        case .stage(_, .interrupted):
            return .interrupted
        case .unavailable, .stage, .cancelled:
            return .unavailable
        }
    }
}

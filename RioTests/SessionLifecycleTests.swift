import Foundation
import XCTest

@MainActor
final class SessionLifecycleTests: XCTestCase {
    func testCadenceIsConfiguredBeforeAListeningSessionStarts() async throws {
        let speech = TestSessionSpeechRecognizer()
        let coordinator = makeCoordinator(speech: speech)

        await coordinator.configure(cadence: .thirtySeconds)

        let configuredBatchDuration = await speech.batchDuration()
        XCTAssertEqual(configuredBatchDuration, .seconds(30))
    }

    func testConfiguredProfileIsRecordedWithTheCompletedMeeting() async throws {
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(historyRecorder: historyRecorder)

        await coordinator.configure(cadence: .thirtySeconds, profile: .internalTechnical)
        try await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(historyRecorder.records().first?.profile, .internalTechnical)
    }

    func testConfiguredProfileAppliesItsTranscriptionSettings() async throws {
        let speech = TestSessionSpeechRecognizer()
        let profile = try XCTUnwrap(
            MeetingProfile.custom(
                name: "Incident review",
                guidance: "Prioritize evidence.",
                insightPace: .ninetySeconds,
                technicalVocabulary: "z/OS, IRLM"
            )
        )
        let coordinator = makeCoordinator(speech: speech)

        await coordinator.configure(profile: profile)

        let batchDuration = await speech.batchDuration()
        let transcriptionPrompt = await speech.transcriptionPrompt()
        XCTAssertEqual(batchDuration, .seconds(90))
        XCTAssertEqual(transcriptionPrompt, "z/OS, IRLM")
    }

    func testAcceptedFinalizedSpeechSegmentsAreForwardedExactlyOnce() async throws {
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let coordinator = makeCoordinator(
            speech: speech,
            transcriptCollector: transcriptCollector
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        let firstSegment = makeSegment(sequence: 1, text: "first finalized segment")
        let secondSegment = FinalizedSpeechSegment(
            sequenceNumber: 2,
            text: "second finalized segment",
            startOffset: .seconds(1),
            endOffset: .seconds(2)
        )
        speechStream?.yield(firstSegment)
        speechStream?.yield(secondSegment)

        await waitUntil {
            transcriptCollector.segments == [firstSegment, secondSegment]
        }

        XCTAssertEqual(transcriptCollector.segments, [firstSegment, secondSegment])
        await coordinator.stop()
    }

    func testNormalStopRecordsMeetingSnapshotWithTranscriptAndCurrentInsights() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            updates: [makeUpdate(text: "captured insight")]
        )
        let state = TestSessionInsightState()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let segment = makeSegment(sequence: 1, text: "the meeting transcript")
        let speechStream = await speech.lastStream()
        speechStream?.yield(segment)
        await waitUntil { state.cards.count == 1 }
        let expectedInsights = state.cards

        await coordinator.stop()

        let records = historyRecorder.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].transcript, [segment])
        XCTAssertEqual(records[0].insights, expectedInsights)
        XCTAssertFalse(records[0].incompleteTranscript)
        XCTAssertLessThanOrEqual(records[0].startedAt, records[0].endedAt)
    }

    func testTranscriptionFailureSavesTheAvailableTranscriptAsIncomplete() async throws {
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let segment = makeSegment(sequence: 1, text: "available before interruption")
        let speechStream = await speech.lastStream()
        speechStream?.yield(segment)
        await waitUntil { transcriptCollector.segments == [segment] }
        speechStream?.finish(throwing: PipelineFailure.stage(.speechRecognition, .failed))
        await waitUntil { coordinator.status == .unavailable }

        let records = historyRecorder.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].transcript, [segment])
        XCTAssertTrue(records[0].incompleteTranscript)
    }

    func testTerminalFailureIsRecordedByTheGeneralDiagnosticsGuardrail() async throws {
        let speech = TestSessionSpeechRecognizer()
        let failureRecorder = TestSessionFailureRecorder()
        let coordinator = makeCoordinator(
            speech: speech,
            failureRecorder: failureRecorder
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.finish(
            throwing: PipelineFailure.stage(.speechRecognition, .failed)
        )
        await waitUntil { coordinator.status == .unavailable }

        XCTAssertEqual(
            failureRecorder.failures,
            [.stage(.speechRecognition, .failed)]
        )
    }

    func testTranscriptionOverloadStopsAndMarksSavedTranscriptIncomplete() async throws {
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let segment = FinalizedSpeechSegment(
            sequenceNumber: 1,
            text: "continuous prefix before bounded queue overload",
            startOffset: .seconds(90),
            endOffset: .seconds(120)
        )
        let speechStream = await speech.lastStream()
        speechStream?.yield(segment)
        await waitUntil {
            transcriptCollector.segments == [segment]
        }

        speechStream?.finish(throwing: PipelineFailure.stage(.speechRecognition, .overloaded))
        await waitUntil { coordinator.status == .unavailable }

        XCTAssertEqual(
            coordinator.failure,
            .stage(.speechRecognition, .overloaded)
        )
        XCTAssertEqual(historyRecorder.records().first?.transcript, [segment])
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
    }

    func testTerminatedAudioConsumerStopsCaptureAndMarksTranscriptIncomplete() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture, speech: speech, historyRecorder: historyRecorder
        )
        try await coordinator.start()
        let audioStream = await capture.lastStream()
        audioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil(speech: speech, forwardedAudioChunkCount: 1)

        await speech.terminateAudioConsumption()
        audioStream?.yield(makeAudioChunk(sequence: 2))
        await waitUntil {
            coordinator.status == .unavailable && historyRecorder.records().count == 1
        }

        XCTAssertEqual(coordinator.failure, .stage(.audioCapture, .failed))
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
        let starts = await capture.startCount()
        let cancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
    }

    func testAudioForwardingOverloadStopsAndMarksSavedTranscriptIncomplete() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer(
            stallsAfterForwardingFirstAudioChunk: true
        )
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let segment = makeSegment(sequence: 1, text: "saved prefix before audio overload")
        let speechStream = await speech.lastStream()
        speechStream?.yield(segment)
        await waitUntil { transcriptCollector.segments == [segment] }

        let audioStream = await capture.lastStream()
        audioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil(speech: speech, forwardedAudioChunkCount: 1)
        for sequence in 2...34 {
            audioStream?.yield(makeAudioChunk(sequence: UInt64(sequence)))
        }

        await waitUntil(timeout: .seconds(1)) {
            coordinator.status == .unavailable
                && historyRecorder.records().count == 1
        }

        XCTAssertEqual(
            coordinator.failure,
            .stage(.audioCapture, .overloaded)
        )
        XCTAssertEqual(historyRecorder.records().first?.transcript, [segment])
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
        let captureStarts = await capture.startCount()
        let captureCancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        XCTAssertEqual(captureStarts, 1)
        XCTAssertEqual(captureCancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
    }

    func testPermissionDeniedStopsBeforeStartingPipeline() async throws {
        let capture = TestSessionAudioCapture(
            permission: .denied,
            availability: .unavailable(.microphonePermissionDenied)
        )
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            state: state
        )

        let availability = await coordinator.checkAvailability()
        XCTAssertEqual(availability, .unavailable(.microphonePermissionDenied))
        do {
            try await coordinator.start()
            XCTFail("Permission denial must stop startup")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .unavailable(.microphonePermissionDenied)
            )
        }

        XCTAssertEqual(coordinator.status, .unavailable)
        let captureStarts = await capture.startCount()
        let generatorStarts = await generator.startSessionCount()
        XCTAssertEqual(captureStarts, 0)
        XCTAssertEqual(generatorStarts, 0)
    }

    func testPauseStopsInputWithoutClearingSessionAndResumeRestartsInput() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator
        )

        try await coordinator.start()
        await coordinator.pause()

        XCTAssertEqual(coordinator.status, .paused)
        let startsAfterPause = await capture.startCount()
        let stopsAfterPause = await capture.stopCount()
        let generatorStopsAfterPause = await generator.stopCount()
        XCTAssertEqual(startsAfterPause, 1)
        XCTAssertEqual(stopsAfterPause, 1)
        XCTAssertEqual(generatorStopsAfterPause, 0)

        try await coordinator.resume()
        XCTAssertEqual(coordinator.status, .listening)
        let startsAfterResume = await capture.startCount()
        XCTAssertEqual(startsAfterResume, 2)

        await coordinator.stop()
        XCTAssertEqual(coordinator.status, .stopped)
        let stopsAfterStop = await capture.stopCount()
        let generatorStopsAfterStop = await generator.stopCount()
        XCTAssertEqual(stopsAfterStop, 2)
        XCTAssertEqual(generatorStopsAfterStop, 1)
    }

    func testTranscriptionUnavailableStopsBeforeCapture() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer(
            availability: .unavailable(.openAIAPIKeyMissing)
        )
        let generator = TestSessionInsightGenerator()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator
        )

        do {
            try await coordinator.start()
            XCTFail("Speech unavailability must stop startup")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .unavailable(.openAIAPIKeyMissing)
            )
        }

        XCTAssertEqual(coordinator.status, .unavailable)
        let captureStarts = await capture.startCount()
        let generatorStarts = await generator.startSessionCount()
        XCTAssertEqual(captureStarts, 0)
        XCTAssertEqual(generatorStarts, 0)
    }

    func testTranscriptionFailureDuringPreparationStopsBeforeCapture() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer(
            availability: .unavailable(.openAIAPIKeyInvalid)
        )
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech
        )

        do {
            try await coordinator.start()
            XCTFail("An unavailable transcription service must stop startup")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .unavailable(.openAIAPIKeyInvalid)
            )
        }

        let captureStarts = await capture.startCount()
        XCTAssertEqual(captureStarts, 0)
    }

    func testModelUnavailableStopsBeforeCapture() async throws {
        let capture = TestSessionAudioCapture()
        let generator = TestSessionInsightGenerator(
            availability: .unavailable(.openAIAPIKeyMissing)
        )
        let coordinator = makeCoordinator(
            capture: capture,
            generator: generator
        )

        do {
            try await coordinator.start()
            XCTFail("Model unavailability must stop startup")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .unavailable(.openAIAPIKeyMissing)
            )
        }

        let captureStarts = await capture.startCount()
        let generatorStarts = await generator.startSessionCount()
        XCTAssertEqual(captureStarts, 0)
        XCTAssertEqual(generatorStarts, 0)
    }

    func testReadinessReportsAllUnavailablePrerequisitesTogether() async {
        let capture = TestSessionAudioCapture(
            permission: .denied,
            availability: .unavailable(.microphonePermissionDenied)
        )
        let speech = TestSessionSpeechRecognizer(
            availability: .unavailable(.openAIAPIKeyMissing)
        )
        let generator = TestSessionInsightGenerator(
            availability: .unavailable(.openAIAPIKeyInvalid)
        )
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator
        )

        let report = await coordinator.checkReadiness()

        XCTAssertEqual(
            report.checks.map(\.kind),
            [.meetingAudio, .meetingTranscription, .openAI]
        )
        XCTAssertEqual(report.checks[0].reason, .microphonePermissionDenied)
        XCTAssertEqual(report.checks[1].reason, .openAIAPIKeyMissing)
        XCTAssertEqual(report.checks[2].reason, .openAIAPIKeyInvalid)
        XCTAssertFalse(report.isReady)
    }

    func testSystemAudioPermissionDoesNotReportAsBlockingAvailability() {
        let readiness = SessionReadiness(
            checks: [
                PrerequisiteCheck(
                    kind: .meetingAudio,
                    reason: .systemAudioPermissionDenied
                )
            ]
        )

        XCTAssertNil(readiness.blockingReason)
        XCTAssertFalse(readiness.isReady)
    }

    func testCaptureStartFailureCleansPartialStartup() async throws {
        let capture = TestSessionAudioCapture(
            startFailure: .stage(.audioCapture, .failed)
        )
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let contextFactory = TestMeetingContextFactory()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            contextFactory: contextFactory,
            state: state
        )

        do {
            try await coordinator.start()
            XCTFail("Capture startup failure must propagate")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .stage(.audioCapture, .failed)
            )
        }

        XCTAssertEqual(coordinator.status, .unavailable)
        let captureCancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        let generatorCancellations = await generator.cancelCount()
        let contexts = contextFactory.contexts()
        let contextCancellations = await contexts[0].cancelCount()
        XCTAssertEqual(captureCancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
        XCTAssertEqual(generatorCancellations, 1)
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contextCancellations, 1)
        XCTAssertEqual(state.resetCount, 2)
    }

    func testTransientStartupCancellationRetriesWithFreshPipeline() async throws {
        let capture = TestSessionAudioCapture(startFailure: .cancelled)
        let coordinator = makeCoordinator(capture: capture)

        try await coordinator.start()

        XCTAssertEqual(coordinator.status, .listening)
        let captureStarts = await capture.startCount()
        let captureCancellations = await capture.cancelCount()
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(captureCancellations, 1)
        await coordinator.stop()
    }

    func testSpeechFailureWhileListeningPropagatesAndCleans() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.finish(
            throwing: PipelineFailure.stage(.speechRecognition, .failed)
        )
        await waitUntil { coordinator.status == .unavailable }

        let captureCancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        let generatorCancellations = await generator.cancelCount()
        XCTAssertEqual(captureCancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
        XCTAssertEqual(generatorCancellations, 1)
        XCTAssertEqual(state.resetCount, 2)
    }

    func testRepeatedTransientGenerationFailureDoesNotStopListening() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            generateFailure: .stage(.insightGeneration, .failed),
            generateFailureCount: 2
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic generation failure"))
        await waitUntil(timeout: .seconds(8)) { state.appliedContexts.count == 1 }

        XCTAssertEqual(coordinator.status, .listening)
        XCTAssertEqual(state.appliedContexts.count, 1)
        let generatorCancellations = await generator.cancelCount()
        XCTAssertEqual(generatorCancellations, 0)
        await coordinator.stop()
    }

    func testTransientGenerationFailureRestartsTheModelAndRetriesTheBatch() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            updates: [makeUpdate(text: "recovered synthetic insight")],
            generateFailure: .stage(.insightGeneration, .failed)
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic retry"))
        await waitUntil(timeout: .seconds(8)) { state.appliedContexts.count == 1 }

        XCTAssertEqual(coordinator.status, SessionStatus.listening)
        let modelStops = await generator.stopCount()
        let modelStarts = await generator.startSessionCount()
        XCTAssertEqual(modelStops, 1)
        XCTAssertEqual(modelStarts, 2)
        await coordinator.stop()
    }

    func testTransientNetworkFailureRestartsTheModelAndRetriesTheSameBatch() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            updates: [makeUpdate(text: "recovered network insight")],
            generateFailure: .stage(.insightGeneration, .network),
            generateFailureCount: 2
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic network retry"))
        await waitUntil(timeout: .seconds(8)) { state.cards.count == 1 }

        XCTAssertEqual(coordinator.status, .listening)
        XCTAssertEqual(state.appliedContexts.count, 1)
        let modelStops = await generator.stopCount()
        let modelStarts = await generator.startSessionCount()
        XCTAssertEqual(modelStops, 2)
        XCTAssertEqual(modelStarts, 3)
        await coordinator.stop()
    }

    func testTransientInvalidInsightResponseRestartsTheModelAndRetriesTheBatch() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            updates: [makeUpdate(text: "recovered after an invalid response")],
            generateFailure: .stage(.insightGeneration, .responseInvalid)
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic invalid response"))
        await waitUntil(timeout: .seconds(8)) { state.appliedContexts.count == 1 }

        XCTAssertEqual(coordinator.status, SessionStatus.listening)
        let modelStops = await generator.stopCount()
        let modelStarts = await generator.startSessionCount()
        XCTAssertEqual(modelStops, 1)
        XCTAssertEqual(modelStarts, 2)
        await coordinator.stop()
    }

    func testStopWhileProcessingCancelsGenerationAndClearsState() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            delay: .seconds(5),
            updates: [makeUpdate(text: "late synthetic result")]
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic stop while processing"))
        await waitUntil { coordinator.status == SessionStatus.processing }

        await coordinator.stop()

        XCTAssertEqual(coordinator.status, .stopped)
        XCTAssertTrue(state.appliedContexts.isEmpty)
        let generatorStops = await generator.stopCount()
        XCTAssertEqual(generatorStops, 1)
    }

    func testExplicitCancellationClearsEveryActiveComponent() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            delay: .seconds(5),
            updates: [makeUpdate(text: "late cancellation result")]
        )
        let contextFactory = TestMeetingContextFactory()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            contextFactory: contextFactory,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic cancellation"))
        await waitUntil { coordinator.status == SessionStatus.processing }

        await coordinator.cancel()

        XCTAssertEqual(coordinator.status, .stopped)
        let captureCancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        let generatorCancellations = await generator.cancelCount()
        XCTAssertEqual(captureCancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
        XCTAssertEqual(generatorCancellations, 1)
        XCTAssertTrue(state.appliedContexts.isEmpty)
    }

    func testGenerationRequestsRemainSerializedAcrossBatches() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            delay: .milliseconds(10),
            updates: [makeUpdate(text: "serialized result")]
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "first batch"))
        speechStream?.yield(makeSegment(sequence: 2, text: "second batch"))
        await waitUntil { state.appliedContexts.count == 2 }

        let maximumConcurrentRequests = await generator.maximumConcurrentRequests()
        XCTAssertEqual(maximumConcurrentRequests, 1)
        await coordinator.stop()
    }

    func testLaterInsightRequestsReceiveTheBoundedCurrentCardState() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            updates: [makeUpdate(text: "checkout latency increased")]
        )
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            state: state
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "latency increased"))
        await waitUntil { state.cards.count == 1 }
        let firstCard = state.cards[0]

        speechStream?.yield(makeSegment(sequence: 2, text: "payment latency is unknown"))
        await waitUntil { state.appliedContexts.count == 2 }

        let generatedBatches = await generator.generatedBatches()
        XCTAssertEqual(generatedBatches.count, 2)
        XCTAssertTrue(generatedBatches[0].currentInsights.isEmpty)
        XCTAssertEqual(generatedBatches[1].currentInsights, [firstCard])
        await coordinator.stop()
    }

    func testCaptureInterruptionRecoversWithinTheSameMeetingWithoutLosingTranscript() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        let segmentBeforeInterruption = makeSegment(
            sequence: 1,
            text: "finalized before route change"
        )
        speechStream?.yield(segmentBeforeInterruption)
        await waitUntil {
            transcriptCollector.segments == [segmentBeforeInterruption]
        }

        let audioStream = await capture.lastStream()
        audioStream?.finish(
            throwing: PipelineFailure.stage(.audioCapture, .interrupted)
        )
        await waitUntil(capture: capture, startCount: 2)
        XCTAssertEqual(coordinator.status, .interrupted)
        XCTAssertTrue(historyRecorder.records().isEmpty)

        let recoveredAudioStream = await capture.lastStream()
        recoveredAudioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil { coordinator.status == .listening }

        let segmentAfterInterruption = FinalizedSpeechSegment(
            sequenceNumber: 2,
            text: "finalized after route recovery",
            startOffset: .seconds(1),
            endOffset: .seconds(2)
        )
        speechStream?.yield(segmentAfterInterruption)
        await waitUntil {
            transcriptCollector.segments == [
                segmentBeforeInterruption,
                segmentAfterInterruption,
            ]
        }
        await coordinator.stop()

        let captureStarts = await capture.startCount()
        let recognitionStarts = await speech.recognizeCount()
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(recognitionStarts, 1)
        XCTAssertEqual(historyRecorder.records().count, 1)
        XCTAssertEqual(
            historyRecorder.records().first?.transcript,
            [segmentBeforeInterruption, segmentAfterInterruption]
        )
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
    }

    func testUnexpectedNormalCaptureCompletionRecoversWithinTheSameMeeting() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        let segmentBeforeCompletion = makeSegment(
            sequence: 1,
            text: "finalized before unexpected capture completion"
        )
        speechStream?.yield(segmentBeforeCompletion)
        await waitUntil {
            transcriptCollector.segments == [segmentBeforeCompletion]
        }

        let audioStream = await capture.lastStream()
        audioStream?.finish()

        await waitUntil(capture: capture, startCount: 2)
        XCTAssertEqual(coordinator.status, .interrupted)
        XCTAssertTrue(historyRecorder.records().isEmpty)

        let recoveredAudioStream = await capture.lastStream()
        recoveredAudioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil { coordinator.status == .listening }

        let segmentAfterCompletion = FinalizedSpeechSegment(
            sequenceNumber: 2,
            text: "finalized after capture recovery",
            startOffset: .seconds(1),
            endOffset: .seconds(2)
        )
        speechStream?.yield(segmentAfterCompletion)
        await waitUntil {
            transcriptCollector.segments == [
                segmentBeforeCompletion,
                segmentAfterCompletion,
            ]
        }

        await coordinator.stop()

        let captureStarts = await capture.startCount()
        let recognitionStarts = await speech.recognizeCount()
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(recognitionStarts, 1)
        XCTAssertEqual(historyRecorder.records().count, 1)
        XCTAssertEqual(
            historyRecorder.records().first?.transcript,
            [segmentBeforeCompletion, segmentAfterCompletion]
        )
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
    }

    func testUnexpectedCaptureCancellationUsesTheSameRecoveryPath() async throws {
        let capture = TestSessionAudioCapture()
        let coordinator = makeCoordinator(capture: capture)

        try await coordinator.start()
        let audioStream = await capture.lastStream()
        audioStream?.finish(throwing: PipelineFailure.cancelled)
        await waitUntil(capture: capture, startCount: 2)
        XCTAssertEqual(coordinator.status, .interrupted)

        let recoveredAudioStream = await capture.lastStream()
        recoveredAudioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil { coordinator.status == .listening }

        let captureStarts = await capture.startCount()
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(coordinator.status, .listening)
        XCTAssertNil(coordinator.failure)
        await coordinator.stop()
    }

    func testOpenCaptureStreamWithoutAudioFramesTriggersSameMeetingRecovery() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            captureInactivityTimeout: .milliseconds(20),
            captureRecoveryDelays: [.zero]
        )

        try await coordinator.start()

        await waitUntil(capture: capture, startCount: 2)
        XCTAssertEqual(coordinator.status, .interrupted)

        let recoveredAudioStream = await capture.lastStream()
        recoveredAudioStream?.yield(makeAudioChunk(sequence: 1))
        await waitUntil { coordinator.status == .listening }

        let captureStarts = await capture.startCount()
        let recognitionStarts = await speech.recognizeCount()
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(recognitionStarts, 1)
        XCTAssertEqual(coordinator.status, .listening)
        XCTAssertNil(coordinator.failure)
        await coordinator.stop()
    }

    func testSustainedSilentFramesEndAndDiscardAnEmptyMeeting() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let audioStream = await capture.lastStream()
        audioStream?.yield(makeAudioChunk(sequence: 1, duration: .seconds(300)))
        audioStream?.yield(makeAudioChunk(sequence: 2, duration: .seconds(300)))

        await waitUntil { coordinator.status == .stopped }

        let captureStops = await capture.stopCount()
        let speechStops = await speech.stopCount()
        let generatorStops = await generator.stopCount()
        XCTAssertNil(coordinator.failure)
        XCTAssertTrue(historyRecorder.records().isEmpty)
        XCTAssertEqual(captureStops, 1)
        XCTAssertEqual(speechStops, 1)
        XCTAssertEqual(generatorStops, 1)
    }

    func testSustainedSilenceAutoStopSavesExistingMeetingContent() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let transcriptCollector = TestTranscriptCollector()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let segment = makeSegment(sequence: 1, text: "content before the meeting ended")
        let speechStream = await speech.lastStream()
        speechStream?.yield(segment)
        await waitUntil { transcriptCollector.segments == [segment] }

        let audioStream = await capture.lastStream()
        audioStream?.yield(makeAudioChunk(sequence: 1, duration: .seconds(600)))
        await waitUntil { coordinator.status == .stopped }

        let record = try XCTUnwrap(historyRecorder.records().first)
        XCTAssertEqual(record.transcript, [segment])
        XCTAssertFalse(record.incompleteTranscript)
    }

    func testDetectedSignalResetsSustainedSilenceInterval() async throws {
        let capture = TestSessionAudioCapture()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            historyRecorder: historyRecorder
        )

        try await coordinator.start()
        let audioStream = await capture.lastStream()
        audioStream?.yield(makeAudioChunk(sequence: 1, duration: .seconds(599)))
        audioStream?.yield(
            makeAudioChunk(
                sequence: 2,
                duration: .milliseconds(20),
                inputLevel: AudioChunk.signalThreshold
            )
        )
        audioStream?.yield(makeAudioChunk(sequence: 3, duration: .seconds(1)))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.status, .listening)
        XCTAssertTrue(historyRecorder.records().isEmpty)
        await coordinator.stop()
    }

    func testRepeatedCaptureStartsWithoutAudioFramesExhaustRecoveryBound() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            historyRecorder: historyRecorder,
            captureInactivityTimeout: .milliseconds(20),
            captureRecoveryDelays: [.zero, .zero, .zero]
        )

        try await coordinator.start()

        await waitUntil(timeout: .seconds(1)) {
            coordinator.status == .interrupted
                && historyRecorder.records().count == 1
        }

        let captureStarts = await capture.startCount()
        let recognitionStarts = await speech.recognizeCount()
        XCTAssertEqual(captureStarts, 4)
        XCTAssertEqual(recognitionStarts, 1)
        XCTAssertEqual(
            coordinator.failure,
            .stage(.audioCapture, .interrupted)
        )
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
    }

    func testCaptureInterruptionEndsMeetingOnlyAfterRecoveryAttemptsAreExhausted() async throws {
        let capture = TestSessionAudioCapture()
        let historyRecorder = TestMeetingHistoryRecorder()
        let coordinator = makeCoordinator(
            capture: capture,
            historyRecorder: historyRecorder,
            captureRecoveryDelays: [.zero, .zero, .zero]
        )

        try await coordinator.start()
        await capture.failNextStarts(
            with: .stage(.audioCapture, .failed),
            count: 3
        )
        let audioStream = await capture.lastStream()
        audioStream?.finish(
            throwing: PipelineFailure.stage(.audioCapture, .interrupted)
        )
        await waitUntil {
            coordinator.status == .interrupted
                && historyRecorder.records().count == 1
        }

        let captureStarts = await capture.startCount()
        XCTAssertEqual(captureStarts, 4)
        XCTAssertEqual(
            coordinator.failure,
            .stage(.audioCapture, .interrupted)
        )
        XCTAssertEqual(historyRecorder.records().count, 1)
        XCTAssertTrue(historyRecorder.records().first?.incompleteTranscript == true)
    }

    func testRapidStartStopRestartUsesIsolatedSessionAndRejectsStaleResults() async throws {
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            delay: .milliseconds(50),
            updates: [makeUpdate(text: "synthetic stale result")],
            ignoresCancellation: true
        )
        let contextFactory = TestMeetingContextFactory()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            speech: speech,
            generator: generator,
            contextFactory: contextFactory,
            state: state
        )

        try await coordinator.start()
        let firstSpeechStream = await speech.lastStream()
        firstSpeechStream?.yield(makeSegment(sequence: 1, text: "old session"))
        await waitUntil { coordinator.status == SessionStatus.processing }
        await coordinator.stop()

        try await coordinator.start()
        let secondSpeechStream = await speech.lastStream()
        secondSpeechStream?.yield(makeSegment(sequence: 1, text: "new session"))
        await waitUntil { state.appliedContexts.count == 1 }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(state.appliedContexts.count, 1)
        XCTAssertEqual(state.appliedContexts[0].segments[0].text, "new session")
        let contexts = contextFactory.contexts()
        let firstContextSegments = await contexts[0].storedSegments()
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(firstContextSegments.isEmpty)
        await coordinator.stop()
    }

    func testMultipleStopRequestsAreIdempotent() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator
        )

        try await coordinator.start()
        async let firstStop: Void = coordinator.stop()
        async let secondStop: Void = coordinator.stop()
        _ = await (firstStop, secondStop)

        XCTAssertEqual(coordinator.status, .stopped)
        let captureStops = await capture.stopCount()
        let speechStops = await speech.stopCount()
        let generatorStops = await generator.stopCount()
        XCTAssertEqual(captureStops, 1)
        XCTAssertEqual(speechStops, 1)
        XCTAssertEqual(generatorStops, 1)
    }

    func testCleanupAfterSpeechStartupFailureResetsEveryComponent() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer(
            recognizeFailure: .stage(.speechRecognition, .failed)
        )
        let generator = TestSessionInsightGenerator()
        let contextFactory = TestMeetingContextFactory()
        let state = TestSessionInsightState()
        let coordinator = makeCoordinator(
            capture: capture,
            speech: speech,
            generator: generator,
            contextFactory: contextFactory,
            state: state
        )

        do {
            try await coordinator.start()
            XCTFail("Speech startup failure must propagate")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .stage(.speechRecognition, .failed)
            )
        }

        let captureCancellations = await capture.cancelCount()
        let speechCancellations = await speech.cancelCount()
        let generatorCancellations = await generator.cancelCount()
        let context = contextFactory.contexts()[0]
        let contextCancellations = await context.cancelCount()
        let storedSegments = await context.storedSegments()
        XCTAssertEqual(captureCancellations, 1)
        XCTAssertEqual(speechCancellations, 1)
        XCTAssertEqual(generatorCancellations, 1)
        XCTAssertEqual(contextCancellations, 1)
        XCTAssertTrue(storedSegments.isEmpty)
        XCTAssertTrue(state.appliedContexts.isEmpty)
    }

    func testInsightStateFailureCleansActiveSession() async throws {
        let speech = TestSessionSpeechRecognizer()
        let state = TestSessionInsightState(
            applyFailure: .stage(.insightState, .invalidState)
        )
        let coordinator = makeCoordinator(speech: speech, state: state)

        try await coordinator.start()
        let speechStream = await speech.lastStream()
        speechStream?.yield(makeSegment(sequence: 1, text: "synthetic state failure"))
        await waitUntil { coordinator.status == .unavailable }

        XCTAssertEqual(coordinator.status, .unavailable)
        XCTAssertTrue(state.appliedContexts.isEmpty)
        let speechCancellations = await speech.cancelCount()
        XCTAssertEqual(speechCancellations, 1)
    }

    private func makeCoordinator(
        capture: TestSessionAudioCapture = TestSessionAudioCapture(),
        speech: TestSessionSpeechRecognizer = TestSessionSpeechRecognizer(),
        generator: TestSessionInsightGenerator = TestSessionInsightGenerator(),
        contextFactory: TestMeetingContextFactory = TestMeetingContextFactory(),
        state: TestSessionInsightState = TestSessionInsightState(),
        transcriptCollector: any TranscriptCollecting = TestTranscriptCollector(),
        historyRecorder: any MeetingHistoryRecording = TestMeetingHistoryRecorder(),
        failureRecorder: any SessionFailureRecording = TestSessionFailureRecorder(),
        captureInactivityTimeout: Duration = .seconds(5),
        captureRecoveryDelays: [Duration] = [
            .zero,
            .milliseconds(500),
            .seconds(2),
            .seconds(5),
        ]
    ) -> SessionLifecycleCoordinator {
        SessionLifecycleCoordinator(
            localeIdentifier: "en-US",
            capture: capture,
            speechRecognizer: speech,
            contextFactory: contextFactory,
            insightGenerator: generator,
            insightState: state,
            transcriptCollector: transcriptCollector,
            historyRecorder: historyRecorder,
            failureRecorder: failureRecorder,
            captureInactivityTimeout: captureInactivityTimeout,
            captureRecoveryDelays: captureRecoveryDelays
        )
    }

    private func waitUntil(
        timeout: Duration = .milliseconds(100),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for lifecycle transition")
    }

    private func waitUntil(
        capture: TestSessionAudioCapture,
        startCount expectedStartCount: Int,
        timeout: Duration = .seconds(1)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await capture.startCount() >= expectedStartCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for capture restart")
    }

    private func waitUntil(
        speech: TestSessionSpeechRecognizer,
        forwardedAudioChunkCount expectedCount: Int,
        timeout: Duration = .seconds(1)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await speech.forwardedAudioChunkCount() >= expectedCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for forwarded audio")
    }

    private func makeSegment(sequence: UInt64, text: String) -> FinalizedSpeechSegment {
        FinalizedSpeechSegment(
            sequenceNumber: sequence,
            text: text,
            startOffset: .zero,
            endOffset: .seconds(1)
        )
    }

    private func makeAudioChunk(
        sequence: UInt64,
        duration: Duration = .milliseconds(20),
        inputLevel: Float = 0
    ) -> AudioChunk {
        AudioChunk(
            sequenceNumber: sequence,
            duration: duration,
            sampleRate: 48_000,
            channelCount: 2,
            samples: [0, 0],
            inputLevel: inputLevel
        )
    }

    private func makeUpdate(text: String) -> InsightUpdate {
        InsightUpdate(
            stableKey: text,
            operation: .add,
            category: .important,
            text: text,
            explicitOwner: nil
        )
    }

}

@MainActor
private final class TestSessionFailureRecorder: SessionFailureRecording {
    private(set) var failures: [PipelineFailure] = []

    func record(_ failure: PipelineFailure) {
        failures.append(failure)
    }
}

final class TestStream<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Element, any Error>
    private let continuation: AsyncThrowingStream<Element, any Error>.Continuation

    init() {
        var capturedContinuation: AsyncThrowingStream<Element, any Error>.Continuation?
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(32)) {
            capturedContinuation = $0
        }
        continuation = capturedContinuation!
    }

    func yield(_ element: Element) {
        continuation.yield(element)
    }

    func finish(throwing error: (any Error)? = nil) {
        continuation.finish(throwing: error)
    }
}

actor TestSessionAudioCapture: SessionAudioCapture {
    private let configuredPermission: MicrophonePermission
    private let configuredAvailability: Availability
    private var startFailure: PipelineFailure?
    private var remainingStartFailures: Int
    private let configuredInputSnapshot: AudioInputSnapshot
    private var currentStream: TestStream<AudioChunk>?
    private var starts = 0
    private var stops = 0
    private var cancellations = 0

    init(
        permission: MicrophonePermission = .granted,
        availability: Availability = .available,
        startFailure: PipelineFailure? = nil,
        startFailureCount: Int = 1,
        inputSnapshot: AudioInputSnapshot = .inactive
    ) {
        configuredPermission = permission
        configuredAvailability = availability
        self.startFailure = startFailure
        remainingStartFailures = startFailure == nil ? 0 : startFailureCount
        configuredInputSnapshot = inputSnapshot
    }

    func permission() async -> MicrophonePermission {
        configuredPermission
    }

    func checkAvailability() async -> Availability {
        configuredAvailability
    }

    func inputSnapshot() async -> AudioInputSnapshot {
        configuredInputSnapshot
    }

    func start() async throws(PipelineFailure) -> AudioStream {
        starts += 1
        if let startFailure, remainingStartFailures > 0 {
            remainingStartFailures -= 1
            throw startFailure
        }
        let source = TestStream<AudioChunk>()
        currentStream = source
        return source.stream
    }

    func failNextStarts(with failure: PipelineFailure, count: Int) {
        startFailure = failure
        remainingStartFailures = count
    }

    func stop() async {
        stops += 1
        currentStream?.finish(throwing: PipelineFailure.cancelled)
        currentStream = nil
    }

    func cancel() async {
        cancellations += 1
        currentStream?.finish(throwing: PipelineFailure.cancelled)
        currentStream = nil
    }

    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
    func cancelCount() -> Int { cancellations }
    func lastStream() -> TestStream<AudioChunk>? { currentStream }
}

actor TestSessionSpeechRecognizer: SessionSpeechRecognizer {
    private let configuredAvailability: Availability
    private let recognizeFailure: PipelineFailure?
    private var currentStream: TestStream<FinalizedSpeechSegment>?
    private var recognitions = 0
    private var stops = 0
    private var cancellations = 0
    private var configuredBatchDuration: Duration?
    private var configuredTranscriptionPrompt: String?
    private let stallsAfterForwardingFirstAudioChunk: Bool
    private var forwardedAudioChunks = 0
    private var audioConsumptionTask: Task<Void, Never>?

    init(
        availability: Availability = .available,
        recognizeFailure: PipelineFailure? = nil,
        stallsAfterForwardingFirstAudioChunk: Bool = false
    ) {
        configuredAvailability = availability
        self.recognizeFailure = recognizeFailure
        self.stallsAfterForwardingFirstAudioChunk = stallsAfterForwardingFirstAudioChunk
    }

    func availability() async -> Availability {
        configuredAvailability
    }

    func prepare() async throws(PipelineFailure) {
        if case .unavailable(let reason) = configuredAvailability {
            throw .unavailable(reason)
        }
    }

    func configure(batchDuration: Duration, transcriptionPrompt: String?) async {
        configuredBatchDuration = batchDuration
        configuredTranscriptionPrompt = transcriptionPrompt
    }

    func pause() async {
        stops += 1
        audioConsumptionTask?.cancel()
        audioConsumptionTask = nil
        currentStream?.finish(throwing: PipelineFailure.cancelled)
        currentStream = nil
    }

    func recognize(audio: AudioStream) async throws(PipelineFailure) -> FinalizedSpeechStream {
        recognitions += 1
        if let recognizeFailure {
            throw recognizeFailure
        }
        let shouldStall = stallsAfterForwardingFirstAudioChunk
        audioConsumptionTask = Task { [weak self] in
            do {
                for try await _ in audio {
                    await self?.recordForwardedAudioChunk()
                    if shouldStall {
                        try await Task.sleep(for: .seconds(60))
                    }
                }
            } catch {
                return
            }
        }
        let source = TestStream<FinalizedSpeechSegment>()
        currentStream = source
        return source.stream
    }

    func stop() async {
        stops += 1
        audioConsumptionTask?.cancel()
        audioConsumptionTask = nil
        currentStream?.finish(throwing: PipelineFailure.cancelled)
        currentStream = nil
    }

    func cancel() async {
        cancellations += 1
        audioConsumptionTask?.cancel()
        audioConsumptionTask = nil
        currentStream?.finish(throwing: PipelineFailure.cancelled)
        currentStream = nil
    }

    func stopCount() -> Int { stops }
    func cancelCount() -> Int { cancellations }
    func recognizeCount() -> Int { recognitions }
    func forwardedAudioChunkCount() -> Int { forwardedAudioChunks }
    func lastStream() -> TestStream<FinalizedSpeechSegment>? { currentStream }
    func batchDuration() -> Duration? { configuredBatchDuration }
    func transcriptionPrompt() -> String? { configuredTranscriptionPrompt }

    func terminateAudioConsumption() async {
        let task = audioConsumptionTask
        task?.cancel()
        await task?.value
        audioConsumptionTask = nil
    }

    private func recordForwardedAudioChunk() {
        forwardedAudioChunks += 1
    }
}

final class TestMeetingContextFactory: MeetingContextFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var createdContexts: [TestMeetingContext] = []

    func makeContext() -> any RollingMeetingContext {
        let context = TestMeetingContext()
        lock.lock()
        createdContexts.append(context)
        lock.unlock()
        return context
    }

    func contexts() -> [TestMeetingContext] {
        lock.lock()
        defer { lock.unlock() }
        return createdContexts
    }
}

actor TestMeetingContext: RollingMeetingContext {
    private var pendingBatches: [MeetingContextBatch] = []
    private var waiting: CheckedContinuation<MeetingContextBatch?, any Error>?
    private var segments: [FinalizedSpeechSegment] = []
    private var cancelled = false
    private var cancels = 0

    func append(_ segment: FinalizedSpeechSegment) async throws(PipelineFailure) {
        guard !cancelled else {
            throw .cancelled
        }
        segments.append(segment)
        let batch = MeetingContextBatch(segments: [segment])
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: batch)
        } else {
            pendingBatches.append(batch)
        }
    }

    func nextBatch() async throws(PipelineFailure) -> MeetingContextBatch? {
        guard !cancelled else {
            throw .cancelled
        }
        if !pendingBatches.isEmpty {
            return pendingBatches.removeFirst()
        }
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<MeetingContextBatch?, any Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: PipelineFailure.cancelled)
                    } else {
                        waiting = continuation
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelWaitingBatch()
                }
            }
        } catch let failure as PipelineFailure {
            throw failure
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .stage(.rollingContext, .failed)
        }
    }

    func clear() async {
        pendingBatches.removeAll()
        segments.removeAll()
    }

    func cancel() async {
        cancelled = true
        cancels += 1
        pendingBatches.removeAll()
        segments.removeAll()
        if let waiting {
            self.waiting = nil
            waiting.resume(throwing: PipelineFailure.cancelled)
        }
    }

    private func cancelWaitingBatch() {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(throwing: PipelineFailure.cancelled)
    }

    func cancelCount() -> Int { cancels }
    func storedSegments() -> [FinalizedSpeechSegment] { segments }
}

actor TestSessionInsightGenerator: SessionInsightGenerator {
    private let configuredAvailability: Availability
    private let startFailure: PipelineFailure?
    private let delay: Duration
    private let updates: [InsightUpdate]
    private let updateProvider: (@Sendable (MeetingContextBatch) -> [InsightUpdate])?
    private let generateFailure: PipelineFailure?
    private var remainingGenerateFailures: Int
    private let ignoresCancellation: Bool
    private var started = false
    private var starts = 0
    private var stops = 0
    private var cancellations = 0
    private var activeRequests = 0
    private var maximumActiveRequests = 0
    private var receivedBatches: [MeetingContextBatch] = []

    init(
        availability: Availability = .available,
        startFailure: PipelineFailure? = nil,
        delay: Duration = .zero,
        updates: [InsightUpdate] = [],
        updateProvider: (@Sendable (MeetingContextBatch) -> [InsightUpdate])? = nil,
        generateFailure: PipelineFailure? = nil,
        generateFailureCount: Int = 1,
        ignoresCancellation: Bool = false
    ) {
        configuredAvailability = availability
        self.startFailure = startFailure
        self.delay = delay
        self.updates = updates
        self.updateProvider = updateProvider
        self.generateFailure = generateFailure
        remainingGenerateFailures = generateFailureCount
        self.ignoresCancellation = ignoresCancellation
    }

    func availability() async -> Availability {
        configuredAvailability
    }

    func supportsLocale(identifier: String) async -> Bool {
        true
    }

    func startSession(localeIdentifier: String) async throws(PipelineFailure) {
        starts += 1
        if let startFailure {
            throw startFailure
        }
        started = true
    }

    func generate(from batch: MeetingContextBatch) async throws(PipelineFailure) -> [InsightUpdate] {
        guard started else {
            throw .stage(.insightGeneration, .invalidState)
        }
        activeRequests += 1
        receivedBatches.append(batch)
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        defer { activeRequests -= 1 }

        if delay > .zero {
            try? await Task.sleep(for: delay)
            if !ignoresCancellation, Task.isCancelled {
                throw .cancelled
            }
        }
        if let generateFailure {
            if remainingGenerateFailures > 0 {
                remainingGenerateFailures -= 1
                throw generateFailure
            }
        }
        return updateProvider?(batch) ?? updates
    }

    func stop() async {
        stops += 1
        started = false
    }

    func cancel() async {
        cancellations += 1
        started = false
    }

    func startSessionCount() -> Int { starts }
    func stopCount() -> Int { stops }
    func cancelCount() -> Int { cancellations }
    func maximumConcurrentRequests() -> Int { maximumActiveRequests }
    func generatedBatches() -> [MeetingContextBatch] { receivedBatches }
}

@MainActor
final class TestSessionInsightState: InsightState {
    private let applyFailure: PipelineFailure?
    private(set) var cards: [InsightCard] = []
    private(set) var appliedContexts: [MeetingContextBatch] = []
    private(set) var resetCount = 0

    init(applyFailure: PipelineFailure? = nil) {
        self.applyFailure = applyFailure
    }

    func apply(
        _ updates: [InsightUpdate],
        supportedBy sourceContext: MeetingContextBatch
    ) throws(PipelineFailure) {
        appliedContexts.append(sourceContext)
        if let applyFailure {
            throw applyFailure
        }
        cards = updates.map {
            InsightCard(
                stableKey: $0.stableKey,
                category: $0.category,
                text: $0.text,
                explicitOwner: $0.explicitOwner,
                state: .new
            )
        }
    }

    func reset() {
        resetCount += 1
        cards.removeAll()
        appliedContexts.removeAll()
    }
}

@MainActor
final class TestTranscriptCollector: TranscriptCollecting {
    private(set) var segments: [FinalizedSpeechSegment] = []

    func append(_ segment: FinalizedSpeechSegment) {
        segments.append(segment)
    }

    func snapshot() -> [FinalizedSpeechSegment] {
        segments
    }

    func reset() {
        segments.removeAll()
    }
}

@MainActor
final class TestMeetingHistoryRecorder: MeetingHistoryRecording {
    private var recordedMeetings: [MeetingHistoryRecord] = []

    func record(_ meeting: MeetingHistoryRecord) {
        recordedMeetings.append(meeting)
    }

    func records() -> [MeetingHistoryRecord] {
        recordedMeetings
    }
}

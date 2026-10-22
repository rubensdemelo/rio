import SwiftUI

enum FakeSessionStartOutcome: Sendable, Equatable {
    case listening
    case unavailable(UnavailableReason)
    case interrupted
    case failure(PipelineFailure)
}

@MainActor
@Observable
final class FakeSessionController: SessionShellControlling {
    private(set) var status: SessionStatus
    private(set) var cards: [InsightCard]
    let feedback: SessionFeedbackModel
    private(set) var readiness: SessionReadiness?
    private(set) var unavailableReason: UnavailableReason?
    private(set) var failure: PipelineFailure?
    private(set) var isPerformingPrimaryAction = false
    private(set) var isPerformingPauseAction = false

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
        self.feedback = SessionFeedbackModel(feedback)
        self.readiness = readiness
        self.unavailableReason = unavailableReason
        self.failure = failure
        self.startOutcome = startOutcome
        self.transitionDelay = transitionDelay
    }

    func checkReadiness() async {
        // The fake controller receives readiness through its initializer or inject().
    }

    func performPrimaryAction() async {
        guard !isPerformingPrimaryAction, status != .checkingAvailability else { return }

        if isStartAction {
            await start()
        } else {
            await stop()
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
        self.feedback.update(feedback)
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
            feedback.update(SessionFeedbackSnapshot(
                audioInput: AudioInputSnapshot(
                    level: 0,
                    hasReceivedAudio: true,
                    isMuted: false
                ),
                finalizedSpeechSegmentCount: 0
            ))
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
        feedback.update(.inactive)
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

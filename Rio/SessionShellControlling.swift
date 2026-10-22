import SwiftUI

/// Audio feedback changes several times a second while listening. It is
/// observed apart from the controller so those updates redraw only the
/// voice feedback instead of the whole session window.
@MainActor
@Observable
final class SessionFeedbackModel {
    private(set) var snapshot: SessionFeedbackSnapshot

    init(_ snapshot: SessionFeedbackSnapshot = .inactive) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: SessionFeedbackSnapshot) {
        if snapshot != nextSnapshot { snapshot = nextSnapshot }
    }
}

@MainActor
protocol SessionShellControlling: AnyObject, Observable {
    var status: SessionStatus { get }
    var cards: [InsightCard] { get }
    var feedback: SessionFeedbackModel { get }
    var readiness: SessionReadiness? { get }
    var unavailableReason: UnavailableReason? { get }
    var failure: PipelineFailure? { get }
    var isPerformingPrimaryAction: Bool { get }
    var isPerformingPauseAction: Bool { get }

    func checkReadiness() async
    func performPrimaryAction() async
    func performPauseAction() async
}

extension SessionShellControlling {
    /// An interruption without a failure is still reconnecting, so its primary
    /// action stops the session rather than starting a new one.
    var isStartAction: Bool {
        switch status {
        case .stopped, .unavailable:
            true
        case .interrupted:
            failure != nil
        case .checkingAvailability, .listening, .processing, .paused:
            false
        }
    }

    var primaryActionTitle: String {
        if status == .checkingAvailability { return "Checking…" }
        return isStartAction ? "Start Listening" : "Stop Listening"
    }

    var pauseActionTitle: String {
        status == .paused ? "Resume Listening" : "Pause Listening"
    }

    var isReadyToStartListening: Bool {
        // Permission states that macOS can request or re-check only when the
        // capture starts must not disable the action that triggers that check.
        readiness != nil && readiness?.blockingReason == nil
    }
}

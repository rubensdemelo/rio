import SwiftUI

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
            if failure == nil {
                title = "Reconnecting meeting audio"
                detail = "Rio is keeping this meeting open while audio reconnects."
                symbolName = "arrow.trianglehead.2.clockwise.rotate.90"
            } else {
                title = "Interrupted"
                detail = "Listening stopped after audio recovery attempts were exhausted."
                symbolName = "exclamationmark.circle"
            }
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

extension UnavailableReason {
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
        case .stage(.meetingHistory, .failed):
            "Rio couldn’t save this meeting. Open Recent Meetings to retry before quitting."
        case .stage(_, .interrupted):
            "Listening was interrupted."
        case .stage(_, .overloaded):
            "Rio stopped before skipping meeting audio. The transcript saved so far is marked incomplete. Start listening again to resume."
        case .stage, .cancelled:
            "Rio could not start listening."
        }
    }
}

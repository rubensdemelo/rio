import SwiftUI

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
        Duration.seconds(max(0, duration.components.seconds)).elapsedTimestamp
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

struct VoiceFeedbackView: View {
    let status: SessionStatus
    let feedbackModel: SessionFeedbackModel
    let failure: PipelineFailure?
    let unavailableReason: UnavailableReason?

    private var feedback: SessionFeedbackSnapshot {
        feedbackModel.snapshot
    }

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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
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

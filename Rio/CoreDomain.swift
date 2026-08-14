import Combine
import Foundation

enum MeetingProfile: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case customerCritical
    case internalTechnical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customerCritical: "Customer-critical"
        case .internalTechnical: "Internal technical"
        }
    }

    var detail: String {
        switch self {
        case .customerCritical:
            "Prioritizes cautious, evidence-grounded insights for customer conversations."
        case .internalTechnical:
            "Prioritizes accurate technical speech capture for internal knowledge."
        }
    }
}

@MainActor
final class MeetingProfileSettings: ObservableObject {
    private static let storageKey = "meetingProfile"

    @Published var selection: MeetingProfile {
        didSet { defaults.set(selection.rawValue, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = MeetingProfile(
            rawValue: defaults.string(forKey: Self.storageKey) ?? ""
        ) ?? .customerCritical
    }
}

enum TranscriptionVocabularyConfiguration {
    static let maximumPromptLength = 1_000
    static let storageKey = "transcriptionVocabularyPrompt"

    static func storedPrompt(defaults: UserDefaults = .standard) -> String? {
        normalized(defaults.string(forKey: storageKey))
    }

    static func normalized(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class TranscriptionVocabularySettings: ObservableObject {
    static let maximumPromptLength = TranscriptionVocabularyConfiguration.maximumPromptLength

    @Published var prompt: String {
        didSet {
            if prompt.count > Self.maximumPromptLength {
                prompt = String(prompt.prefix(Self.maximumPromptLength))
                return
            }
            defaults.set(prompt, forKey: TranscriptionVocabularyConfiguration.storageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prompt = String(
            (defaults.string(forKey: TranscriptionVocabularyConfiguration.storageKey) ?? "")
                .prefix(Self.maximumPromptLength)
        )
    }

    var transcriptionPrompt: String? {
        TranscriptionVocabularyConfiguration.normalized(prompt)
    }
}

enum ListeningCadence: Int, CaseIterable, Hashable, Identifiable, Sendable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case fortyFiveSeconds = 45

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) seconds"
    }

    var audioBatchDuration: Duration {
        .seconds(Double(rawValue))
    }

    var detail: String {
        switch self {
        case .fifteenSeconds:
            "Quicker updates with smaller audio batches. Rio uses more requests and less context per update."
        case .thirtySeconds:
            "A balanced pace with more context per update and fewer requests."
        case .fortyFiveSeconds:
            "Fewer requests and fuller context, but insights arrive later and cover larger time windows."
        }
    }
}

@MainActor
final class ListeningCadenceSettings: ObservableObject {
    private static let storageKey = "listeningCadenceSeconds"

    @Published var selection: ListeningCadence {
        didSet {
            defaults.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSeconds = defaults.integer(forKey: Self.storageKey)
        selection = ListeningCadence(rawValue: storedSeconds) ?? .thirtySeconds
    }
}

struct SessionID: Hashable, Sendable, Equatable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

enum SessionStatus: Sendable, Equatable {
    case stopped
    case checkingAvailability
    case listening
    case processing
    case paused
    case interrupted
    case unavailable
}

struct AudioChunk: Sendable, Equatable {
    let sequenceNumber: UInt64
    let duration: Duration
    let sampleRate: Double
    let channelCount: Int
    let samples: [Float]

    /// A normalized, content-free input level used only for live UI feedback.
    let inputLevel: Float

    init(
        sequenceNumber: UInt64,
        duration: Duration,
        sampleRate: Double,
        channelCount: Int,
        samples: [Float],
        inputLevel: Float? = nil
    ) {
        self.sequenceNumber = sequenceNumber
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
        self.inputLevel = inputLevel ?? Self.normalizedInputLevel(for: samples)
    }

    private static func normalizedInputLevel(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(into: Float.zero) { result, sample in
            result += sample * sample
        } / Float(samples.count)
        return min(1, max(0, sqrt(meanSquare) * 4))
    }
}

struct AudioInputSnapshot: Sendable, Equatable {
    let level: Float
    let hasReceivedAudio: Bool
    let isMuted: Bool

    static let inactive = AudioInputSnapshot(
        level: 0,
        hasReceivedAudio: false,
        isMuted: false
    )
}

struct SessionFeedbackSnapshot: Sendable, Equatable {
    let audioInput: AudioInputSnapshot
    let finalizedSpeechSegmentCount: Int

    static let inactive = SessionFeedbackSnapshot(
        audioInput: .inactive,
        finalizedSpeechSegmentCount: 0
    )
}

struct FinalizedSpeechSegment: Sendable, Equatable {
    let sequenceNumber: UInt64
    let text: String
    let startOffset: Duration
    let endOffset: Duration
}

enum InsightCategory: Sendable, Equatable {
    case important
    case decision
    case action
    case question
    case risk
}

enum InsightOperation: Sendable, Equatable {
    case add
    case update
    case resolve
}

enum InsightCardState: Sendable, Equatable {
    case new
    case updated
    case resolved
}

struct InsightUpdate: Sendable, Equatable {
    let stableKey: String
    let operation: InsightOperation
    let category: InsightCategory
    let text: String
    let explicitOwner: String?
}

struct InsightCard: Sendable, Equatable {
    let stableKey: String
    let category: InsightCategory
    let text: String
    let explicitOwner: String?
    let state: InsightCardState
}

enum Availability: Sendable, Equatable {
    case available
    case unavailable(UnavailableReason)
}

enum UnavailableReason: Sendable, Equatable {
    case microphonePermissionUndetermined
    case microphonePermissionDenied
    case audioInputUnavailable
    case systemAudioPermissionDenied
    case systemAudioUnavailable
    case openAIAPIKeyMissing
    case openAIAPIKeyInvalid
}

enum PrerequisiteKind: Sendable, Equatable, CaseIterable {
    case meetingAudio
    case meetingTranscription
    case openAI
}

struct PrerequisiteCheck: Sendable, Equatable, Identifiable {
    let kind: PrerequisiteKind
    let reason: UnavailableReason?

    var id: PrerequisiteKind { kind }
    var isReady: Bool { reason == nil }
}

struct SessionReadiness: Sendable, Equatable {
    let checks: [PrerequisiteCheck]

    var isReady: Bool {
        checks.allSatisfy(\.isReady)
    }

    var blockingReason: UnavailableReason? {
        checks
            .compactMap(\.reason)
            .first {
                $0 != .microphonePermissionUndetermined
                    && $0 != .systemAudioPermissionDenied
            }
    }
}

enum PipelineStage: Sendable, Equatable {
    case audioCapture
    case speechRecognition
    case rollingContext
    case insightGeneration
    case insightState
    case sessionLifecycle
}

enum PipelineFailureReason: Sendable, Equatable {
    case failed
    case interrupted
    case overloaded
    case invalidState
    case network
    case rateLimited
    case serviceUnavailable
    case requestRejected(statusCode: Int)
    case responseInvalid
}

enum PipelineFailure: Error, Sendable, Equatable {
    case unavailable(UnavailableReason)
    case stage(PipelineStage, PipelineFailureReason)
    case cancelled
}

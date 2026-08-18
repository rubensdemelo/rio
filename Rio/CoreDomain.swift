import Combine
import Foundation

struct MeetingProfile: Codable, Hashable, Identifiable, Sendable {
    enum BuiltIn: String, Codable, Sendable {
        case customerCritical
        case internalTechnical
    }

    static let maximumNameLength = 60
    static let maximumGuidanceLength = 1_000

    let id: String
    let name: String
    let guidance: String
    let builtIn: BuiltIn?

    var title: String { name }
    var detail: String { guidance }
    var isBuiltIn: Bool { builtIn != nil }

    static let customerCritical = MeetingProfile(
        id: BuiltIn.customerCritical.rawValue,
        name: "Customer-critical",
        guidance: "Prioritizes cautious, evidence-grounded insights for customer conversations.",
        builtIn: .customerCritical
    )

    static let internalTechnical = MeetingProfile(
        id: BuiltIn.internalTechnical.rawValue,
        name: "Internal technical",
        guidance: "Prioritizes accurate technical speech capture for internal knowledge.",
        builtIn: .internalTechnical
    )

    static let builtInProfiles = [customerCritical, internalTechnical]

    // Kept as a compatibility view for callers that only need the shipped profiles.
    static var allCases: [MeetingProfile] { builtInProfiles }

    static func custom(name: String, guidance: String, id: String = UUID().uuidString) -> MeetingProfile? {
        guard let name = normalized(name, maximumLength: maximumNameLength),
              let guidance = normalized(guidance, maximumLength: maximumGuidanceLength)
        else {
            return nil
        }

        return MeetingProfile(id: id, name: name, guidance: guidance, builtIn: nil)
    }

    private init(id: String, name: String, guidance: String, builtIn: BuiltIn?) {
        self.id = id
        self.name = name
        self.guidance = guidance
        self.builtIn = builtIn
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case guidance
        case builtIn
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let legacyRawValue = try? singleValue.decode(String.self) {
            self = switch legacyRawValue {
            case BuiltIn.customerCritical.rawValue:
                .customerCritical
            case BuiltIn.internalTechnical.rawValue:
                .internalTechnical
            default:
                .customerCritical
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let guidance = try container.decode(String.self, forKey: .guidance)
        let builtIn = try container.decodeIfPresent(BuiltIn.self, forKey: .builtIn)

        guard !id.isEmpty,
              let normalizedName = Self.normalized(name, maximumLength: Self.maximumNameLength),
              let normalizedGuidance = Self.normalized(
                  guidance,
                  maximumLength: Self.maximumGuidanceLength
              )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Meeting profile name and guidance must be nonempty and bounded."
            )
        }

        self.init(
            id: id,
            name: normalizedName,
            guidance: normalizedGuidance,
            builtIn: builtIn
        )
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}

@MainActor
final class MeetingProfileSettings: ObservableObject {
    private static let storageKey = "meetingProfile"
    private static let profilesStorageKey = "meetingProfiles"

    @Published var selection: MeetingProfile {
        didSet { defaults.set(selection.id, forKey: Self.storageKey) }
    }

    @Published private(set) var profiles: [MeetingProfile]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedProfiles = Self.loadProfiles(defaults: defaults)
        profiles = loadedProfiles
        let selectedID = defaults.string(forKey: Self.storageKey)
        selection = loadedProfiles.first(where: { $0.id == selectedID }) ?? .customerCritical
    }

    @discardableResult
    func addCustomProfile(name: String, guidance: String) -> MeetingProfile? {
        guard let profile = MeetingProfile.custom(name: name, guidance: guidance),
              !profiles.contains(where: { $0.id == profile.id })
        else {
            return nil
        }

        profiles.append(profile)
        persistProfiles()
        selection = profile
        return profile
    }

    @discardableResult
    func updateCustomProfile(id: String, name: String, guidance: String) -> Bool {
        guard let existingIndex = profiles.firstIndex(where: { $0.id == id }),
              !profiles[existingIndex].isBuiltIn,
              let updated = MeetingProfile.custom(name: name, guidance: guidance, id: id)
        else {
            return false
        }

        profiles[existingIndex] = updated
        if selection.id == id {
            selection = updated
        }
        persistProfiles()
        return true
    }

    func deleteCustomProfile(id: String) {
        guard let profile = profiles.first(where: { $0.id == id }), !profile.isBuiltIn else {
            return
        }

        profiles.removeAll { $0.id == id }
        persistProfiles()
        if selection.id == id {
            selection = .customerCritical
        }
    }

    private static func loadProfiles(defaults: UserDefaults) -> [MeetingProfile] {
        guard let data = defaults.data(forKey: profilesStorageKey),
              let storedProfiles = try? JSONDecoder().decode([MeetingProfile].self, from: data)
        else {
            return MeetingProfile.builtInProfiles
        }

        var seenIDs = Set(MeetingProfile.builtInProfiles.map(\.id))
        let customProfiles = storedProfiles.filter { profile in
            guard !profile.isBuiltIn, !seenIDs.contains(profile.id) else { return false }
            seenIDs.insert(profile.id)
            return true
        }
        return MeetingProfile.builtInProfiles + customProfiles
    }

    private func persistProfiles() {
        let customProfiles = profiles.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(customProfiles) else { return }
        defaults.set(data, forKey: Self.profilesStorageKey)
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
    let latestFinalizedSpeechEndOffset: Duration?

    init(
        audioInput: AudioInputSnapshot,
        finalizedSpeechSegmentCount: Int,
        latestFinalizedSpeechEndOffset: Duration? = nil
    ) {
        self.audioInput = audioInput
        self.finalizedSpeechSegmentCount = finalizedSpeechSegmentCount
        self.latestFinalizedSpeechEndOffset = latestFinalizedSpeechEndOffset
    }

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

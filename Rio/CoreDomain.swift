import Combine
import Foundation

struct MeetingProfile: Codable, Hashable, Identifiable, Sendable {
    // Kept only so older saved meetings and profile snapshots remain decodable.
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
    let insightPace: ListeningCadence
    let technicalVocabulary: String

    var title: String { name }
    var detail: String { guidance }
    var isBuiltIn: Bool { builtIn != nil }
    var isFallback: Bool { id == Self.fallback.id }
    var transcriptionPrompt: String? {
        TranscriptionVocabularyConfiguration.normalized(technicalVocabulary)
    }

    // Used when no user-created profile exists. It is never shown in profile settings.
    static let fallback = MeetingProfile(
        id: "general-meeting",
        name: "General meeting",
        guidance: "Surface concise, evidence-grounded insights from the current meeting.",
        builtIn: nil,
        insightPace: .thirtySeconds,
        technicalVocabulary: ""
    )

    // Legacy snapshots only; these are not shipped or surfaced as profiles.
    static let customerCritical = MeetingProfile(
        id: BuiltIn.customerCritical.rawValue,
        name: "Customer-critical",
        guidance: "Prioritizes cautious, evidence-grounded insights for customer conversations.",
        builtIn: .customerCritical,
        insightPace: .thirtySeconds,
        technicalVocabulary: ""
    )

    static let internalTechnical = MeetingProfile(
        id: BuiltIn.internalTechnical.rawValue,
        name: "Internal technical",
        guidance: "Prioritizes accurate technical speech capture for internal knowledge.",
        builtIn: .internalTechnical,
        insightPace: .thirtySeconds,
        technicalVocabulary: ""
    )

    static func custom(
        name: String,
        guidance: String,
        insightPace: ListeningCadence = .thirtySeconds,
        technicalVocabulary: String = "",
        id: String = UUID().uuidString
    ) -> MeetingProfile? {
        guard let name = normalized(name, maximumLength: maximumNameLength),
              let guidance = normalized(guidance, maximumLength: maximumGuidanceLength),
              let technicalVocabulary = normalizedVocabulary(technicalVocabulary)
        else {
            return nil
        }

        return MeetingProfile(
            id: id,
            name: name,
            guidance: guidance,
            builtIn: nil,
            insightPace: insightPace,
            technicalVocabulary: technicalVocabulary
        )
    }

    private init(
        id: String,
        name: String,
        guidance: String,
        builtIn: BuiltIn?,
        insightPace: ListeningCadence,
        technicalVocabulary: String
    ) {
        self.id = id
        self.name = name
        self.guidance = guidance
        self.builtIn = builtIn
        self.insightPace = insightPace
        self.technicalVocabulary = technicalVocabulary
    }

    func withConfiguration(
        insightPace: ListeningCadence,
        technicalVocabulary: String
    ) -> MeetingProfile? {
        guard let technicalVocabulary = Self.normalizedVocabulary(technicalVocabulary) else {
            return nil
        }

        return MeetingProfile(
            id: id,
            name: name,
            guidance: guidance,
            builtIn: builtIn,
            insightPace: insightPace,
            technicalVocabulary: technicalVocabulary
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case guidance
        case builtIn
        case insightPace
        case technicalVocabulary
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
        let insightPace = try container.decodeIfPresent(ListeningCadence.self, forKey: .insightPace)
            ?? .thirtySeconds
        let technicalVocabulary = try container.decodeIfPresent(String.self, forKey: .technicalVocabulary)
            ?? ""

        guard !id.isEmpty,
              let normalizedName = Self.normalized(name, maximumLength: Self.maximumNameLength),
              let normalizedGuidance = Self.normalized(
                  guidance,
                  maximumLength: Self.maximumGuidanceLength
              ),
              let normalizedTechnicalVocabulary = Self.normalizedVocabulary(technicalVocabulary)
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
            builtIn: builtIn,
            insightPace: insightPace,
            technicalVocabulary: normalizedTechnicalVocabulary
        )
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }

    private static func normalizedVocabulary(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= TranscriptionVocabularyConfiguration.maximumPromptLength else {
            return nil
        }
        return trimmed
    }
}

@MainActor
final class MeetingProfileSettings: ObservableObject {
    private static let storageKey = "meetingProfile"
    private static let profilesStorageKey = "meetingProfiles"
    private static let legacyConfigurationMigrationKey = "meetingProfileConfigurationMigrationCompleted"

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
        selection = loadedProfiles.first(where: { $0.id == selectedID }) ?? .fallback
    }

    @discardableResult
    func addCustomProfile(
        name: String,
        guidance: String,
        insightPace: ListeningCadence = .thirtySeconds,
        technicalVocabulary: String = ""
    ) -> MeetingProfile? {
        guard let profile = MeetingProfile.custom(
            name: name,
            guidance: guidance,
            insightPace: insightPace,
            technicalVocabulary: technicalVocabulary
        ),
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
    func updateCustomProfile(
        id: String,
        name: String,
        guidance: String,
        insightPace: ListeningCadence? = nil,
        technicalVocabulary: String? = nil
    ) -> Bool {
        guard let existingIndex = profiles.firstIndex(where: { $0.id == id }),
              !profiles[existingIndex].isBuiltIn,
              let updated = MeetingProfile.custom(
                  name: name,
                  guidance: guidance,
                  insightPace: insightPace ?? profiles[existingIndex].insightPace,
                  technicalVocabulary: technicalVocabulary ?? profiles[existingIndex].technicalVocabulary,
                  id: id
              )
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

    @discardableResult
    func updateProfileConfiguration(
        id: String,
        insightPace: ListeningCadence,
        technicalVocabulary: String
    ) -> Bool {
        guard let existingIndex = profiles.firstIndex(where: { $0.id == id }),
              let updated = profiles[existingIndex].withConfiguration(
                  insightPace: insightPace,
                  technicalVocabulary: technicalVocabulary
              )
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
            selection = .fallback
        }
    }

    private static func loadProfiles(defaults: UserDefaults) -> [MeetingProfile] {
        guard let data = defaults.data(forKey: profilesStorageKey),
              let storedProfiles = try? JSONDecoder().decode([MeetingProfile].self, from: data)
        else {
            return migrateLegacyConfiguration(
                [],
                defaults: defaults
            )
        }

        var seenIDs = Set<String>()
        let customProfiles = storedProfiles.filter { profile in
            guard !profile.isBuiltIn, !profile.isFallback, !seenIDs.contains(profile.id) else { return false }
            seenIDs.insert(profile.id)
            return true
        }
        return migrateLegacyConfiguration(
            customProfiles,
            defaults: defaults
        )
    }

    private static func migrateLegacyConfiguration(
        _ profiles: [MeetingProfile],
        defaults: UserDefaults
    ) -> [MeetingProfile] {
        guard !defaults.bool(forKey: legacyConfigurationMigrationKey) else {
            return profiles
        }

        let legacyCadence = defaults.object(forKey: ListeningCadenceSettings.storageKey)
            .flatMap { ($0 as? Int).flatMap(ListeningCadence.fromStoredSeconds) }
            ?? .thirtySeconds
        let legacyVocabulary = defaults.string(forKey: TranscriptionVocabularyConfiguration.storageKey) ?? ""
        defaults.set(true, forKey: legacyConfigurationMigrationKey)
        guard legacyCadence != .thirtySeconds || !legacyVocabulary.isEmpty else { return profiles }

        let migratedProfiles = profiles.compactMap {
            $0.withConfiguration(
                insightPace: legacyCadence,
                technicalVocabulary: legacyVocabulary
            )
        }
        if let data = try? JSONEncoder().encode(migratedProfiles) {
            defaults.set(data, forKey: profilesStorageKey)
        }
        return migratedProfiles
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
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

enum ListeningCadence: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case thirtySeconds = 30
    case sixtySeconds = 60
    case ninetySeconds = 90

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) seconds"
    }

    var shortTitle: String {
        "\(rawValue)s"
    }

    var audioBatchDuration: Duration {
        .seconds(Double(rawValue))
    }

    var detail: String {
        switch self {
        case .thirtySeconds:
            "Fastest updates, with about two transcription requests per minute."
        case .sixtySeconds:
            "Fewer requests and more context, with about one transcription request per minute."
        case .ninetySeconds:
            "Fewest requests and most context, but insights can arrive noticeably later."
        }
    }

    static func fromStoredSeconds(_ seconds: Int) -> ListeningCadence? {
        switch seconds {
        case 15, 30:
            .thirtySeconds
        case 45, 60:
            .sixtySeconds
        case 90:
            .ninetySeconds
        default:
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Int.self)
        guard let cadence = Self.fromStoredSeconds(seconds) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported listening cadence: \(seconds) seconds."
            )
        }
        self = cadence
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

@MainActor
final class ListeningCadenceSettings: ObservableObject {
    static let storageKey = "listeningCadenceSeconds"

    @Published var selection: ListeningCadence {
        didSet {
            defaults.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSeconds = defaults.integer(forKey: Self.storageKey)
        selection = ListeningCadence.fromStoredSeconds(storedSeconds) ?? .thirtySeconds
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
    case systemAudioCaptureFailed
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

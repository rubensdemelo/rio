import Combine
import Foundation

struct SavedTranscriptSegment: Codable, Equatable, Sendable {
    let sequenceNumber: UInt64
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let text: String
}

struct SavedMeeting: Codable, Equatable, Identifiable, Sendable {
    static let maximumTranscriptSegmentUTF8ByteCount = 8_192
    static let maximumTranscriptUTF8ByteCount = 1_000_000
    static let maximumTranscriptSegmentCount = 10_000
    static let maximumInsightTextUTF8ByteCount = 8_192
    static let maximumInsightCount = 200

    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let transcriptSegments: [SavedTranscriptSegment]
    let insights: [SavedInsight]
    let incompleteTranscript: Bool
    let profile: MeetingProfile

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        transcriptSegments: [SavedTranscriptSegment],
        insights: [SavedInsight],
        incompleteTranscript: Bool,
        profile: MeetingProfile = .fallback
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptSegments = Self.normalizedTranscript(transcriptSegments)
        self.insights = Self.normalizedInsights(insights)
        self.incompleteTranscript = incompleteTranscript
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case transcriptSegments
        case insights
        case incompleteTranscript
        case profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decode(Date.self, forKey: .endedAt),
            transcriptSegments: try container.decode([SavedTranscriptSegment].self, forKey: .transcriptSegments),
            insights: try container.decode([SavedInsight].self, forKey: .insights),
            incompleteTranscript: try container.decode(Bool.self, forKey: .incompleteTranscript),
            profile: try container.decodeIfPresent(MeetingProfile.self, forKey: .profile) ?? .customerCritical
        )
    }

    private static func normalizedTranscript(
        _ segments: [SavedTranscriptSegment]
    ) -> [SavedTranscriptSegment] {
        var firstSegmentBySequence: [UInt64: SavedTranscriptSegment] = [:]

        for segment in segments {
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard firstSegmentBySequence[segment.sequenceNumber] == nil else {
                continue
            }

            firstSegmentBySequence[segment.sequenceNumber] = SavedTranscriptSegment(
                sequenceNumber: segment.sequenceNumber,
                startOffset: segment.startOffset,
                endOffset: segment.endOffset,
                text: boundedText(
                    segment.text,
                    maximumUTF8ByteCount: maximumTranscriptSegmentUTF8ByteCount
                )
            )
        }

        var totalUTF8ByteCount = 0
        var normalizedSegments: [SavedTranscriptSegment] = []
        for segment in firstSegmentBySequence.values.sorted(by: {
            $0.sequenceNumber < $1.sequenceNumber
        }).prefix(maximumTranscriptSegmentCount) {
            let remainingByteCount = maximumTranscriptUTF8ByteCount - totalUTF8ByteCount
            guard remainingByteCount > 0 else { break }

            let text = boundedText(
                segment.text,
                maximumUTF8ByteCount: min(
                    maximumTranscriptSegmentUTF8ByteCount,
                    remainingByteCount
                )
            )
            guard !text.isEmpty else { break }

            normalizedSegments.append(SavedTranscriptSegment(
                sequenceNumber: segment.sequenceNumber,
                startOffset: segment.startOffset,
                endOffset: segment.endOffset,
                text: text
            ))
            totalUTF8ByteCount += text.utf8.count
        }

        return normalizedSegments
    }

    private static func normalizedInsights(_ insights: [SavedInsight]) -> [SavedInsight] {
        var latestInsightByStableKey: [String: SavedInsight] = [:]
        for insight in insights {
            let bounded = boundedText(
                insight.text,
                maximumUTF8ByteCount: maximumInsightTextUTF8ByteCount
            )
            let normalizedInsight = SavedInsight(
                id: insight.id,
                sessionID: insight.sessionID,
                card: InsightCard(
                    stableKey: insight.stableKey,
                    category: insight.category.domainValue,
                    text: bounded,
                    explicitOwner: nil,
                    state: insight.state.domainValue
                ),
                savedAt: insight.savedAt
            )

            if let existing = latestInsightByStableKey[insight.stableKey], existing.savedAt >= insight.savedAt {
                continue
            }
            latestInsightByStableKey[insight.stableKey] = normalizedInsight
        }

        return latestInsightByStableKey.values
            .sorted {
                if $0.savedAt != $1.savedAt {
                    return $0.savedAt > $1.savedAt
                }
                return $0.stableKey < $1.stableKey
            }
            .prefix(maximumInsightCount)
            .map { $0 }
    }

    private static func boundedText(_ text: String, maximumUTF8ByteCount: Int) -> String {
        guard text.utf8.count > maximumUTF8ByteCount else { return text }

        var result = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in text.unicodeScalars {
            let scalarByteCount = String(scalar).utf8.count
            guard byteCount + scalarByteCount <= maximumUTF8ByteCount else { break }
            result.append(scalar)
            byteCount += scalarByteCount
        }
        return String(result)
    }
}

protocol MeetingHistoryPersisting {
    func load() throws -> [SavedMeeting]
    func save(_ meetings: [SavedMeeting]) throws
}

struct FileMeetingHistoryRepository: MeetingHistoryPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() throws -> [SavedMeeting] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try JSONDecoder().decode([SavedMeeting].self, from: Data(contentsOf: fileURL))
    }

    func save(_ meetings: [SavedMeeting]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(meetings)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("Rio", isDirectory: true)
            .appendingPathComponent("recent-meetings.json")
    }
}

@MainActor
final class MeetingHistoryStore: ObservableObject {
    static let retention: TimeInterval = 48 * 60 * 60

    @Published private(set) var meetings: [SavedMeeting]

    private let repository: any MeetingHistoryPersisting

    init(
        repository: any MeetingHistoryPersisting = FileMeetingHistoryRepository(),
        now: Date = Date()
    ) {
        self.repository = repository
        meetings = []
        load(now: now)
    }

    func load(now: Date = Date()) {
        guard let loadedMeetings = try? repository.load() else {
            meetings = []
            return
        }

        let retainedMeetings = Self.retainedMeetings(from: loadedMeetings, now: now)
        meetings = retainedMeetings
        if retainedMeetings != loadedMeetings {
            try? repository.save(retainedMeetings)
        }
    }

    func record(_ meeting: SavedMeeting, now: Date = Date()) {
        var updatedMeetings = meetings.filter { $0.id != meeting.id }
        updatedMeetings.append(meeting)
        let retainedMeetings = Self.retainedMeetings(from: updatedMeetings, now: now)
        meetings = retainedMeetings
        try? repository.save(retainedMeetings)
    }

    func clear(meetingID: UUID) {
        meetings.removeAll { $0.id == meetingID }
        try? repository.save(meetings)
    }

    func clearAll() {
        meetings = []
        try? repository.save([])
    }

    private static func retainedMeetings(
        from meetings: [SavedMeeting],
        now: Date
    ) -> [SavedMeeting] {
        let earliestRetainedDate = now.addingTimeInterval(-retention)
        return meetings
            .filter { $0.endedAt >= earliestRetainedDate }
            .sorted {
                if $0.endedAt != $1.endedAt {
                    return $0.endedAt > $1.endedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map { $0 }
    }
}

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
                    state: insight.state.domainValue,
                    changedAt: insight.savedAt
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

protocol MeetingHistoryPersisting: Sendable {
    func load() async throws -> [SavedMeeting]
    func save(_ meetings: [SavedMeeting]) async throws
}

enum MeetingHistoryPersistenceIssue: Equatable {
    case loadFailed
    case saveFailed
    case expirySaveFailed
}

struct FileMeetingHistoryRepository: MeetingHistoryPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() async throws -> [SavedMeeting] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try JSONDecoder().decode([SavedMeeting].self, from: Data(contentsOf: fileURL))
    }

    func save(_ meetings: [SavedMeeting]) async throws {
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
@Observable
final class MeetingHistoryStore: RioTerminationHistoryPreparing {
    nonisolated static let retention: TimeInterval = 48 * 60 * 60
    nonisolated static let maximumMeetingCount = 50
    nonisolated static let maximumEncodedByteCount = 8_000_000

    private(set) var meetings: [SavedMeeting]
    private(set) var persistenceIssue: MeetingHistoryPersistenceIssue?
    private(set) var pendingMeeting: SavedMeeting?

    private let repository: any MeetingHistoryPersisting
    @ObservationIgnored private var expiryPersistencePending = false
    // Operations suspend while the repository works off the main actor, so
    // each one waits for the previous one; otherwise a slower save could
    // overwrite a newer history with a snapshot taken before it.
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    init(
        repository: any MeetingHistoryPersisting = FileMeetingHistoryRepository(),
        now: Date = Date()
    ) {
        self.repository = repository
        meetings = []
        persistenceIssue = nil
        pendingMeeting = nil
        lastOperation = Task { await self.performLoad(now: now) }
    }

    func waitForPendingOperations() async {
        await lastOperation?.value
    }

    func load(now: Date = Date()) async {
        _ = try? await serialized { await self.performLoad(now: now) }
    }

    func record(_ meeting: SavedMeeting, now: Date = Date()) async throws {
        try await serialized { try await self.performRecord(meeting, now: now) }
    }

    func retryPendingMeeting(now: Date = Date()) async throws {
        try await serialized {
            guard let pendingMeeting = self.pendingMeeting else { return }
            try await self.performRecord(pendingMeeting, now: now)
        }
    }

    var hasPendingTerminationRecord: Bool {
        pendingMeeting != nil
    }

    func retryPendingTerminationRecord() async throws {
        try await retryPendingMeeting()
    }

    func pruneExpired(now: Date = Date()) async throws {
        try await serialized { try await self.performPruneExpired(now: now) }
    }

    func clear(meetingID: UUID) async throws {
        try await serialized {
            let updatedMeetings = self.meetings.filter { $0.id != meetingID }
            try await self.repository.save(updatedMeetings)
            self.meetings = updatedMeetings
            self.persistenceIssue = self.pendingMeeting == nil ? nil : .saveFailed
        }
    }

    func clearAll() async throws {
        try await serialized {
            try await self.repository.save([])
            self.meetings = []
            self.pendingMeeting = nil
            self.persistenceIssue = nil
        }
    }

    private func serialized<T: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        let previous = lastOperation
        let task = Task {
            await previous?.value
            return try await operation()
        }
        lastOperation = Task { _ = await task.result }
        return try await task.value
    }

    private func performLoad(now: Date) async {
        let loadedMeetings: [SavedMeeting]
        do {
            loadedMeetings = try await repository.load()
        } catch {
            meetings = []
            persistenceIssue = .loadFailed
            return
        }

        let retainedMeetings = await Self.retainedMeetings(from: loadedMeetings, now: now)
        meetings = retainedMeetings
        if retainedMeetings != loadedMeetings {
            do {
                try await repository.save(retainedMeetings)
                expiryPersistencePending = false
                persistenceIssue = pendingMeeting == nil ? nil : .saveFailed
            } catch {
                expiryPersistencePending = true
                persistenceIssue = .expirySaveFailed
            }
        } else if persistenceIssue != .saveFailed {
            persistenceIssue = nil
        }
    }

    private func performRecord(_ meeting: SavedMeeting, now: Date) async throws {
        var updatedMeetings = meetings.filter { $0.id != meeting.id }
        updatedMeetings.append(meeting)
        let retainedMeetings = await Self.retainedMeetings(from: updatedMeetings, now: now)
        do {
            try await repository.save(retainedMeetings)
            meetings = retainedMeetings
            if pendingMeeting?.id == meeting.id {
                pendingMeeting = nil
            }
            persistenceIssue = nil
        } catch {
            if pendingMeeting == nil || pendingMeeting?.id == meeting.id {
                pendingMeeting = meeting
            }
            persistenceIssue = .saveFailed
            throw error
        }
    }

    private func performPruneExpired(now: Date) async throws {
        // Every write already enforced the count and size bounds, and expiry
        // only removes meetings, so the date filter alone keeps them.
        let earliestRetainedDate = now.addingTimeInterval(-Self.retention)
        let retainedMeetings = meetings.filter { $0.endedAt >= earliestRetainedDate }
        guard retainedMeetings != meetings || expiryPersistencePending else { return }

        // Expired content is hidden immediately even if the disk write fails.
        // `persistenceIssue` keeps the UI truthful that removal at rest did not succeed.
        meetings = retainedMeetings
        do {
            try await repository.save(retainedMeetings)
            expiryPersistencePending = false
            if persistenceIssue == .expirySaveFailed {
                persistenceIssue = pendingMeeting == nil ? nil : .saveFailed
            }
        } catch {
            expiryPersistencePending = true
            persistenceIssue = .expirySaveFailed
            throw error
        }
    }

    private nonisolated static func retainedMeetings(
        from meetings: [SavedMeeting],
        now: Date
    ) async -> [SavedMeeting] {
        let earliestRetainedDate = now.addingTimeInterval(-retention)
        var retained = meetings
            .filter { $0.endedAt >= earliestRetainedDate }
            .sorted {
                if $0.endedAt != $1.endedAt {
                    return $0.endedAt > $1.endedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(maximumMeetingCount)
            .map { $0 }

        // The saved file is `[` + the meetings joined by `,` + `]`, so its size
        // follows from encoding each meeting once.
        let encoder = JSONEncoder()
        var meetingByteCounts = retained.map {
            (try? encoder.encode($0).count) ?? maximumEncodedByteCount + 1
        }
        var encodedByteCount = 2 + meetingByteCounts.reduce(0, +)
            + max(0, meetingByteCounts.count - 1)
        while retained.count > 1, encodedByteCount > maximumEncodedByteCount {
            retained.removeLast()
            encodedByteCount -= meetingByteCounts.removeLast() + 1
        }
        if encodedByteCount > maximumEncodedByteCount {
            retained.removeAll()
        }
        return retained
    }
}

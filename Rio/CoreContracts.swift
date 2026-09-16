import Foundation
import Observation

typealias AudioStream = AsyncThrowingStream<AudioChunk, any Error>
typealias FinalizedSpeechStream = AsyncThrowingStream<FinalizedSpeechSegment, any Error>

struct MeetingContextBatch: Sendable, Equatable {
    let segments: [FinalizedSpeechSegment]
    let newSegments: [FinalizedSpeechSegment]
    let currentInsights: [InsightCard]

    init(
        segments: [FinalizedSpeechSegment],
        newSegments: [FinalizedSpeechSegment]? = nil,
        currentInsights: [InsightCard] = []
    ) {
        self.segments = segments
        self.newSegments = newSegments ?? segments
        self.currentInsights = currentInsights
    }
}

protocol AudioCapture: Sendable {
    func start() async throws(PipelineFailure) -> AudioStream
    func stop() async
    func cancel() async
}

protocol TemporarySpeechRecognizer: Sendable {
    func recognize(audio: AudioStream) async throws(PipelineFailure) -> FinalizedSpeechStream
    func stop() async
    func cancel() async
}

protocol RollingMeetingContext: Sendable {
    func append(_ segment: FinalizedSpeechSegment) async throws(PipelineFailure)
    func nextBatch() async throws(PipelineFailure) -> MeetingContextBatch?
    func clear() async
    func cancel() async
}

protocol MeetingContextClock: Sendable {
    func now() async -> Duration
    func sleep(until deadline: Duration) async throws
}

struct ContinuousMeetingContextClock: MeetingContextClock {
    private let clock: ContinuousClock
    private let origin: ContinuousClock.Instant

    init() {
        let clock = ContinuousClock()
        self.clock = clock
        origin = clock.now
    }

    func now() async -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(until deadline: Duration) async throws {
        let current = await now()
        guard current < deadline else {
            return
        }
        try await clock.sleep(for: deadline - current)
    }
}

struct MeetingContextConfiguration: Sendable, Equatable {
    let maximumAge: Duration
    let maximumTokenCount: Int
    let maximumUTF8ByteCount: Int
    let batchTokenThreshold: Int
    let maximumBatchWait: Duration

    init(
        maximumAge: Duration,
        maximumTokenCount: Int,
        maximumUTF8ByteCount: Int,
        batchTokenThreshold: Int,
        maximumBatchWait: Duration
    ) {
        precondition(maximumAge >= .zero)
        precondition(maximumTokenCount > 0)
        precondition(maximumUTF8ByteCount > 0)
        precondition(batchTokenThreshold > 0)
        precondition(maximumBatchWait >= .zero)

        self.maximumAge = maximumAge
        self.maximumTokenCount = maximumTokenCount
        self.maximumUTF8ByteCount = maximumUTF8ByteCount
        self.batchTokenThreshold = batchTokenThreshold
        self.maximumBatchWait = maximumBatchWait
    }
}

actor BoundedRollingMeetingContext: RollingMeetingContext {
    typealias TokenEstimator = @Sendable (String) -> Int

    private struct StoredSegment: Sendable {
        let segment: FinalizedSpeechSegment
        let receivedAt: Duration
        let tokenCount: Int
        let utf8ByteCount: Int
    }

    private let configuration: MeetingContextConfiguration
    private let clock: any MeetingContextClock
    private let tokenEstimator: TokenEstimator

    private var storedSegments: [StoredSegment] = []
    private var totalTokenCount = 0
    private var totalUTF8ByteCount = 0
    private var lastAppendedSequenceNumber: UInt64?
    private var lastAppendedStartOffset: Duration?
    private var lastDeliveredSequenceNumber: UInt64?
    private var isCancelled = false
    private var stateGeneration: UInt64 = 0

    private var nextBatchRequestID: UInt64 = 0
    private var activeBatchRequestID: UInt64?
    private var batchContinuation: CheckedContinuation<MeetingContextBatch?, any Error>?
    private var batchWaitTask: Task<Void, Never>?
    private var batchWaitGeneration: UInt64 = 0
    private var evictionTask: Task<Void, Never>?
    private var evictionGeneration: UInt64 = 0

    init(
        configuration: MeetingContextConfiguration,
        clock: any MeetingContextClock,
        tokenEstimator: @escaping TokenEstimator
    ) {
        self.configuration = configuration
        self.clock = clock
        self.tokenEstimator = tokenEstimator
    }

    func append(_ segment: FinalizedSpeechSegment) async throws(PipelineFailure) {
        guard !isCancelled else {
            throw .cancelled
        }
        guard segment.startOffset <= segment.endOffset,
              lastAppendedSequenceNumber.map({ segment.sequenceNumber > $0 }) ?? true,
              lastAppendedStartOffset.map({ segment.startOffset >= $0 }) ?? true else {
            throw invalidContextState
        }

        let tokenCount = tokenEstimator(segment.text)
        guard tokenCount >= 0 else {
            throw invalidContextState
        }

        let appendGeneration = stateGeneration
        let receivedAt = await clock.now()
        guard !isCancelled, appendGeneration == stateGeneration else {
            throw .cancelled
        }

        lastAppendedSequenceNumber = segment.sequenceNumber
        lastAppendedStartOffset = segment.startOffset
        evictExpiredSegments(at: receivedAt)

        let utf8ByteCount = segment.text.utf8.count
        if tokenCount <= configuration.maximumTokenCount,
           utf8ByteCount <= configuration.maximumUTF8ByteCount {
            storedSegments.append(
                StoredSegment(
                    segment: segment,
                    receivedAt: receivedAt,
                    tokenCount: tokenCount,
                    utf8ByteCount: utf8ByteCount
                )
            )
            totalTokenCount += tokenCount
            totalUTF8ByteCount += utf8ByteCount
            evictForCapacity()
        }

        reevaluateBatchRequest(at: receivedAt)
        scheduleEviction()
    }

    func nextBatch() async throws(PipelineFailure) -> MeetingContextBatch? {
        do {
            return try await nextBatchResult()
        } catch let failure as PipelineFailure {
            throw failure
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw invalidContextState
        }
    }

    func clear() {
        clearStoredState()
        finishBatchRequest(returning: nil)
    }

    func cancel() {
        isCancelled = true
        clearStoredState()
        finishBatchRequest(throwing: PipelineFailure.cancelled)
    }

    private func nextBatchResult() async throws -> MeetingContextBatch? {
        guard !isCancelled else {
            throw PipelineFailure.cancelled
        }
        guard activeBatchRequestID == nil else {
            throw invalidContextState
        }

        nextBatchRequestID += 1
        let requestID = nextBatchRequestID
        activeBatchRequestID = requestID

        let current = await clock.now()
        guard activeBatchRequestID == requestID else {
            if isCancelled {
                throw PipelineFailure.cancelled
            }
            return nil
        }
        guard !isCancelled else {
            activeBatchRequestID = nil
            throw PipelineFailure.cancelled
        }
        guard !Task.isCancelled else {
            activeBatchRequestID = nil
            throw PipelineFailure.cancelled
        }
        evictExpiredSegments(at: current)
        scheduleEviction()

        if batchThresholdReached || maximumWaitReached(at: current),
           let batch = makeBatch() {
            activeBatchRequestID = nil
            return batch
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    activeBatchRequestID = nil
                    continuation.resume(throwing: PipelineFailure.cancelled)
                    return
                }

                batchContinuation = continuation
                scheduleBatchWait()
            }
        } onCancel: {
            Task {
                await self.cancelBatchRequest(requestID)
            }
        }
    }

    private func reevaluateBatchRequest(at current: Duration) {
        guard batchContinuation != nil else {
            return
        }

        if batchThresholdReached || maximumWaitReached(at: current),
           let batch = makeBatch() {
            finishBatchRequest(returning: batch)
        } else {
            scheduleBatchWait()
        }
    }

    private var batchThresholdReached: Bool {
        pendingTokenCount >= configuration.batchTokenThreshold
    }

    private var pendingTokenCount: Int {
        storedSegments.lazy
            .filter { stored in
                self.lastDeliveredSequenceNumber.map {
                    stored.segment.sequenceNumber > $0
                } ?? true
            }
            .reduce(into: 0) { count, stored in
                count += stored.tokenCount
            }
    }

    private var firstPendingSegment: StoredSegment? {
        storedSegments.first { stored in
            lastDeliveredSequenceNumber.map {
                stored.segment.sequenceNumber > $0
            } ?? true
        }
    }

    private func maximumWaitReached(at current: Duration) -> Bool {
        guard let firstPendingSegment else {
            return false
        }
        return firstPendingSegment.receivedAt + configuration.maximumBatchWait <= current
    }

    private func makeBatch() -> MeetingContextBatch? {
        guard firstPendingSegment != nil,
              let newestSequenceNumber = storedSegments.last?.segment.sequenceNumber else {
            return nil
        }

        let newSegments = Array(storedSegments
            .lazy
            .filter { stored in
                self.lastDeliveredSequenceNumber.map {
                    stored.segment.sequenceNumber > $0
                } ?? true
            }
            .map(\.segment))
        lastDeliveredSequenceNumber = newestSequenceNumber
        return MeetingContextBatch(
            segments: storedSegments.map(\.segment),
            newSegments: newSegments
        )
    }

    private func evictExpiredSegments(at current: Duration) {
        while let oldest = storedSegments.first,
              oldest.receivedAt + configuration.maximumAge <= current {
            removeOldestSegment()
        }
    }

    private func evictForCapacity() {
        while !storedSegments.isEmpty,
              totalTokenCount > configuration.maximumTokenCount
                || totalUTF8ByteCount > configuration.maximumUTF8ByteCount {
            removeOldestSegment()
        }
    }

    private func removeOldestSegment() {
        let removed = storedSegments.removeFirst()
        totalTokenCount -= removed.tokenCount
        totalUTF8ByteCount -= removed.utf8ByteCount
    }

    private func scheduleBatchWait() {
        batchWaitTask?.cancel()
        batchWaitTask = nil
        batchWaitGeneration += 1

        guard batchContinuation != nil,
              let firstPendingSegment else {
            return
        }

        let deadline = firstPendingSegment.receivedAt + configuration.maximumBatchWait
        let generation = batchWaitGeneration
        let clock = clock
        batchWaitTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                guard !Task.isCancelled else {
                    return
                }
                await self?.batchWaitElapsed(generation: generation)
            } catch {
                return
            }
        }
    }

    private func batchWaitElapsed(generation: UInt64) async {
        guard generation == batchWaitGeneration,
              batchContinuation != nil,
              !isCancelled else {
            return
        }

        let current = await clock.now()
        guard generation == batchWaitGeneration else {
            return
        }
        evictExpiredSegments(at: current)
        reevaluateBatchRequest(at: current)
        scheduleEviction()
    }

    private func scheduleEviction() {
        evictionTask?.cancel()
        evictionTask = nil
        evictionGeneration += 1

        guard let oldest = storedSegments.first else {
            return
        }

        let deadline = oldest.receivedAt + configuration.maximumAge
        let generation = evictionGeneration
        let clock = clock
        evictionTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                guard !Task.isCancelled else {
                    return
                }
                await self?.evictionWaitElapsed(generation: generation)
            } catch {
                return
            }
        }
    }

    private func evictionWaitElapsed(generation: UInt64) async {
        guard generation == evictionGeneration,
              !isCancelled else {
            return
        }

        let current = await clock.now()
        guard generation == evictionGeneration else {
            return
        }
        evictExpiredSegments(at: current)
        reevaluateBatchRequest(at: current)
        scheduleEviction()
    }

    private func cancelBatchRequest(_ requestID: UInt64) {
        guard activeBatchRequestID == requestID else {
            return
        }
        finishBatchRequest(throwing: PipelineFailure.cancelled)
    }

    private func finishBatchRequest(returning batch: MeetingContextBatch?) {
        let continuation = batchContinuation
        batchContinuation = nil
        activeBatchRequestID = nil
        batchWaitTask?.cancel()
        batchWaitTask = nil
        batchWaitGeneration += 1
        continuation?.resume(returning: batch)
    }

    private func finishBatchRequest(throwing error: any Error) {
        let continuation = batchContinuation
        batchContinuation = nil
        activeBatchRequestID = nil
        batchWaitTask?.cancel()
        batchWaitTask = nil
        batchWaitGeneration += 1
        continuation?.resume(throwing: error)
    }

    private func clearStoredState() {
        stateGeneration += 1
        storedSegments.removeAll(keepingCapacity: false)
        totalTokenCount = 0
        totalUTF8ByteCount = 0
        lastAppendedSequenceNumber = nil
        lastAppendedStartOffset = nil
        lastDeliveredSequenceNumber = nil
        evictionTask?.cancel()
        evictionTask = nil
        evictionGeneration += 1
        batchWaitTask?.cancel()
        batchWaitTask = nil
        batchWaitGeneration += 1
    }

    private var invalidContextState: PipelineFailure {
        .stage(.rollingContext, .invalidState)
    }
}

protocol InsightGenerator: Sendable {
    func generate(from batch: MeetingContextBatch) async throws(PipelineFailure) -> [InsightUpdate]
    func cancel() async
}

enum ActionOwnerGrounding {
    private struct AssignmentActionEvidence {
        let lead: String
        let terms: Set<String>
    }

    private static let directAssignmentPrefixes = [
        "will ", "owns ", "own ", "is responsible for ",
        "is assigned to ", "was assigned to ",
    ]
    private static let negationTerms = [
        " not ", "n't ", " no longer ", " unassigned ", " nobody ",
    ]
    private static let ignoredActionWords: Set<String> = [
        "a", "an", "and", "as", "at", "be", "by", "complete", "for", "from",
        "handle", "is", "it", "of", "on", "own", "owns", "the", "to", "will",
    ]
    private static let nonPersonSubjectTerms: Set<String> = [
        "api", "app", "application", "backend", "build", "cluster", "database",
        "deployment", "environment", "frontend", "migration", "network", "pipeline",
        "platform", "portal", "project", "release", "server", "service", "system",
    ]

    static func validatedOwner(
        _ owner: String?,
        category: InsightCategory,
        actionText: String,
        sourceText: String,
        maximumLength: Int
    ) -> String? {
        guard category == .action,
              let owner else {
            return nil
        }

        let candidate = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.count <= maximumLength,
              !containsControlCharacter(candidate) else {
            return nil
        }

        let actionTerms = significantTerms(in: actionText, excluding: candidate)
        return sourceClauses(sourceText).contains { clause in
            let normalized = " \(clause.lowercased()) "
            guard let evidence = supportedAssignmentActionEvidence(
                for: candidate,
                in: clause
            ),
                  !negationTerms.contains(where: normalized.contains) else {
                return false
            }
            return !actionTerms.isEmpty
                && actionTerms.contains(evidence.lead)
                && actionTerms.isSubset(of: evidence.terms)
        } ? candidate : nil
    }

    static func ownerlessActionText(
        _ text: String,
        claimedOwner: String? = nil
    ) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        typealias Replacement = (
            pattern: String,
            options: NSRegularExpression.Options,
            template: String
        )
        var replacements: [Replacement] = []
        if let candidate = claimedOwner?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty {
            let owner = NSRegularExpression.escapedPattern(for: candidate)
            let ownerReplacements: [Replacement] = [
                (#"^(?:Action:\s*)?\#(owner)\s+(?:to|will|must|should|needs?\s+to|is\s+to|owns|is\s+responsible\s+for|(?:is|was)\s+assigned\s+to|agreed\s+to|volunteered\s+to)\s+"#, [.caseInsensitive], ""),
                (#"^(?:Action:\s*)?\#(owner)\s*(?::|—|-)\s*"#, [.caseInsensitive], ""),
                (#"\s+by\s+\#(owner)([.!]?)$"#, [.caseInsensitive], "$1"),
                (#"\s+(?:owner|owned\s+by|assigned\s+to)\s*:?\s*\#(owner)([.!]?)$"#, [.caseInsensitive], "$1"),
                (#"\s+(?:—|-)\s*\#(owner)([.!]?)$"#, [.caseInsensitive], "$1"),
            ]
            replacements.append(contentsOf: ownerReplacements)
        }

        for replacement in replacements {
            guard let expression = try? NSRegularExpression(
                pattern: replacement.pattern,
                options: replacement.options
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement.template
            )
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = result.first else { return result }
        return first.uppercased() + result.dropFirst()
    }

    static func containsRenderedOwnerAttribution(in text: String) -> Bool {
        let modalSubject = #"[\p{L}][\p{L}'’-]*(?:\s+[\p{L}][\p{L}'’-]*){0,3}"#
        let prefixPattern = #"^(?:Action:\s*)?(\#(modalSubject))\s+(?i:to|will|must|should|needs?\s+to|is\s+to|owns?|leads?|is\s+responsible\s+for|(?:is|was)\s+assigned\s+to|agreed\s+to|volunteered\s+to)\b"#
        let range = NSRange(text.startIndex..., in: text)
        if let expression = try? NSRegularExpression(pattern: prefixPattern),
           let match = expression.firstMatch(in: text, range: range),
           let subjectRange = Range(match.range(at: 1), in: text) {
            if !isNonPersonSubject(String(text[subjectRange])) {
                return true
            }
        }

        let patterns = [
            #"^(?:Action:\s*)?(\#(modalSubject))(?:\s*:\s*|\s+(?:—|-)\s+)\S"#,
            #"\s+(?i:by)\s+(\#(modalSubject))[.!]?$"#,
            #"\s+(?i:owner|owned\s+by|assigned\s+to)\s*:?\s*(\#(modalSubject))[.!]?$"#,
            #"\s+(?:—|-)\s*(\#(modalSubject))[.!]?$"#,
        ]
        return patterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            guard let match = expression.firstMatch(in: text, range: range),
                  let subjectRange = Range(match.range(at: 1), in: text) else {
                return false
            }
            return !isNonPersonSubject(String(text[subjectRange]))
        }
    }

    private static func isNonPersonSubject(_ subject: String) -> Bool {
        let subjectTerms = Set(words(in: subject))
        return !subjectTerms.isEmpty
            && subjectTerms.isSubset(of: nonPersonSubjectTerms)
    }

    private static func sourceClauses(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func significantTerms(in text: String, excluding owner: String) -> Set<String> {
        let ownerTerms = Set(words(in: owner))
        return Set(words(in: text).filter {
            $0.count >= 3 && !ignoredActionWords.contains($0) && !ownerTerms.contains($0)
        })
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func supportedAssignmentActionEvidence(
        for name: String,
        in text: String
    ) -> AssignmentActionEvidence? {
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(
            of: name,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            let startsAtBoundary = match.lowerBound == text.startIndex
                || !text[text.index(before: match.lowerBound)].isLetter
                    && !text[text.index(before: match.lowerBound)].isNumber
            let endsAtBoundary = match.upperBound == text.endIndex
                || !text[match.upperBound].isLetter && !text[match.upperBound].isNumber
            if startsAtBoundary && endsAtBoundary {
                let suffix = String(text[match.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                let normalizedSuffix = suffix.lowercased()
                if let prefix = directAssignmentPrefixes.first(where: normalizedSuffix.hasPrefix) {
                    var action = String(suffix.dropFirst(prefix.count))
                    if let boundary = action.range(
                        of: #"\b[\p{L}'’-]+\s+(?i:will|owns?|is\s+responsible\s+for|(?:is|was)\s+assigned\s+to)\b"#,
                        options: .regularExpression
                    ) {
                        action = String(action[..<boundary.lowerBound])
                    }
                    let terms = Set(words(in: action).filter {
                        $0.count >= 3 && !ignoredActionWords.contains($0)
                    })
                    guard let lead = words(in: action).first(where: {
                        $0.count >= 3 && !ignoredActionWords.contains($0)
                    }) else { return nil }
                    return AssignmentActionEvidence(lead: lead, terms: terms)
                }
            }
            searchRange = match.upperBound..<text.endIndex
        }
        return nil
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// Optional seam for adapters whose model behavior changes by meeting profile.
protocol ProfileConfigurableInsightGenerator: SessionInsightGenerator {
    func configure(profile: MeetingProfile) async
}

struct MeetingHistoryRecord: Sendable, Equatable {
    let meetingID: UUID
    let startedAt: Date
    let endedAt: Date
    let transcript: [FinalizedSpeechSegment]
    let insights: [InsightCard]
    let incompleteTranscript: Bool
    let profile: MeetingProfile

    init(
        meetingID: UUID,
        startedAt: Date,
        endedAt: Date,
        transcript: [FinalizedSpeechSegment],
        insights: [InsightCard],
        incompleteTranscript: Bool,
        profile: MeetingProfile = .fallback
    ) {
        self.meetingID = meetingID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcript = transcript
        self.insights = insights
        self.incompleteTranscript = incompleteTranscript
        self.profile = profile
    }
}

@MainActor
protocol TranscriptCollecting: AnyObject {
    func append(_ segment: FinalizedSpeechSegment)
    func snapshot() -> [FinalizedSpeechSegment]
    func reset()
}

@MainActor
final class InMemoryTranscriptCollector: TranscriptCollecting {
    private(set) var segments: [FinalizedSpeechSegment] = []

    func append(_ segment: FinalizedSpeechSegment) {
        guard !segments.contains(where: { $0.sequenceNumber == segment.sequenceNumber }) else {
            return
        }
        segments.append(segment)
    }

    func snapshot() -> [FinalizedSpeechSegment] {
        segments
    }

    func reset() {
        segments.removeAll(keepingCapacity: false)
    }
}

@MainActor
protocol MeetingHistoryRecording: AnyObject {
    var hasPendingRecord: Bool { get }
    func record(_ meeting: MeetingHistoryRecord) throws
}

extension MeetingHistoryRecording {
    var hasPendingRecord: Bool { false }
}

@MainActor
final class NoopMeetingHistoryRecorder: MeetingHistoryRecording {
    func record(_ meeting: MeetingHistoryRecord) throws {}
}

@MainActor
protocol InsightState: AnyObject {
    var cards: [InsightCard] { get }
    func apply(
        _ updates: [InsightUpdate],
        supportedBy sourceContext: MeetingContextBatch
    ) throws(PipelineFailure)
    func reset()
}

struct InsightStoreConfiguration: Sendable, Equatable {
    let maximumActiveCardCount: Int
    let maximumUpdateCount: Int
    let maximumStableKeyLength: Int
    let maximumTextLength: Int
    let maximumOwnerLength: Int

    init(
        maximumActiveCardCount: Int = 20,
        maximumUpdateCount: Int = 8,
        maximumStableKeyLength: Int = 128,
        maximumTextLength: Int = 500,
        maximumOwnerLength: Int = 120
    ) {
        precondition(maximumActiveCardCount >= 0)
        precondition(maximumUpdateCount >= 0)
        precondition(maximumStableKeyLength > 0)
        precondition(maximumTextLength > 0)
        precondition(maximumOwnerLength > 0)

        self.maximumActiveCardCount = maximumActiveCardCount
        self.maximumUpdateCount = maximumUpdateCount
        self.maximumStableKeyLength = maximumStableKeyLength
        self.maximumTextLength = maximumTextLength
        self.maximumOwnerLength = maximumOwnerLength
    }
}

@Observable
@MainActor
final class InMemoryInsightStore: InsightState {
    private(set) var cards: [InsightCard] = []

    private let configuration: InsightStoreConfiguration
    private let now: () -> Date

    init(
        configuration: InsightStoreConfiguration = InsightStoreConfiguration(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.now = now
    }

    func apply(
        _ updates: [InsightUpdate],
        supportedBy sourceContext: MeetingContextBatch
    ) throws(PipelineFailure) {
        let validatedUpdates = try validate(updates, supportedBy: sourceContext)
        var nextCards = cards
        let changedAt = now()

        for update in validatedUpdates {
            apply(update, changedAt: changedAt, to: &nextCards)
        }

        cards = nextCards
    }

    func reset() {
        cards.removeAll(keepingCapacity: false)
    }

    private func validate(
        _ updates: [InsightUpdate],
        supportedBy sourceContext: MeetingContextBatch
    ) throws(PipelineFailure) -> [InsightUpdate] {
        guard updates.count <= configuration.maximumUpdateCount else {
            throw invalidGeneratedOutput
        }

        let sourceText = sourceContext.segments.map(\.text).joined(separator: "\n")
        var stableKeys = Set<String>()
        var validatedUpdates: [InsightUpdate] = []
        validatedUpdates.reserveCapacity(updates.count)

        for update in updates {
            let stableKey = normalizedStableKey(update.stableKey)
            var text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !stableKey.isEmpty,
                  stableKey.count <= configuration.maximumStableKeyLength,
                  !containsControlCharacter(stableKey),
                  stableKeys.insert(stableKey).inserted,
                  !text.isEmpty,
                  text.count <= configuration.maximumTextLength,
                  !containsControlCharacter(text) else {
                throw invalidGeneratedOutput
            }

            validate(update.operation)
            validate(update.category)

            let owner = ActionOwnerGrounding.validatedOwner(
                update.explicitOwner,
                category: update.category,
                actionText: update.text,
                sourceText: sourceText,
                maximumLength: configuration.maximumOwnerLength
            )

            if update.category == .action {
                text = ActionOwnerGrounding.ownerlessActionText(
                    text,
                    claimedOwner: update.explicitOwner
                )
                guard !text.isEmpty,
                      !ActionOwnerGrounding.containsRenderedOwnerAttribution(in: text) else {
                    throw invalidGeneratedOutput
                }
            }
            validatedUpdates.append(
                InsightUpdate(
                    stableKey: stableKey,
                    operation: update.operation,
                    category: update.category,
                    text: text,
                    explicitOwner: owner
                )
            )
        }

        return validatedUpdates
    }

    private func apply(
        _ update: InsightUpdate,
        changedAt: Date,
        to cards: inout [InsightCard]
    ) {
        let existingIndex = cards.firstIndex { $0.stableKey == update.stableKey }

        switch update.operation {
        case .add:
            if let existingIndex {
                guard canActivateCard(at: existingIndex, in: cards) else {
                    return
                }
                cards[existingIndex] = card(
                    from: update,
                    state: .updated,
                    changedAt: changedAt
                )
            } else {
                guard activeCardCount(in: cards) < configuration.maximumActiveCardCount else {
                    return
                }
                removeOldestResolvedCardIfNeeded(from: &cards)
                cards.append(card(from: update, state: .new, changedAt: changedAt))
            }
        case .update:
            guard let existingIndex,
                  canActivateCard(at: existingIndex, in: cards) else {
                return
            }
            cards[existingIndex] = card(
                from: update,
                state: .updated,
                changedAt: changedAt
            )
        case .resolve:
            guard let existingIndex else {
                return
            }
            cards[existingIndex] = card(
                from: update,
                state: .resolved,
                changedAt: changedAt
            )
        }
    }

    private func card(
        from update: InsightUpdate,
        state: InsightCardState,
        changedAt: Date
    ) -> InsightCard {
        InsightCard(
            stableKey: update.stableKey,
            category: update.category,
            text: update.text,
            explicitOwner: update.explicitOwner,
            state: state,
            changedAt: changedAt
        )
    }

    private func canActivateCard(at index: Int, in cards: [InsightCard]) -> Bool {
        cards[index].state != .resolved
            || activeCardCount(in: cards) < configuration.maximumActiveCardCount
    }

    private func activeCardCount(in cards: [InsightCard]) -> Int {
        cards.lazy.filter { $0.state != .resolved }.count
    }

    private func removeOldestResolvedCardIfNeeded(from cards: inout [InsightCard]) {
        guard cards.count >= configuration.maximumActiveCardCount,
              let oldestResolvedIndex = cards.firstIndex(where: { $0.state == .resolved }) else {
            return
        }
        cards.remove(at: oldestResolvedIndex)
    }

    private func normalizedStableKey(_ stableKey: String) -> String {
        stableKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func validate(_ operation: InsightOperation) {
        switch operation {
        case .add, .update, .resolve:
            break
        }
    }

    private func validate(_ category: InsightCategory) {
        switch category {
        case .important, .decision, .action, .question, .risk:
            break
        }
    }

    private var invalidGeneratedOutput: PipelineFailure {
        .stage(.insightState, .invalidState)
    }
}

@MainActor
protocol SessionLifecycle: AnyObject {
    var status: SessionStatus { get }
    var readiness: SessionReadiness? { get }
    func checkAvailability() async -> Availability
    func checkReadiness() async -> SessionReadiness
    func start() async throws(PipelineFailure)
    func pause() async
    func resume() async throws(PipelineFailure)
    func stop() async
    func cancel() async
    func feedbackSnapshot() async -> SessionFeedbackSnapshot
}

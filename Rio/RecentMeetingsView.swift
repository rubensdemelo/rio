import AppKit
import SwiftUI

enum RecentMeetingDetailSection: String, CaseIterable, Identifiable {
    case insights
    case transcript

    var id: Self { self }

    /// Technical meetings open on the transcript, where exact terms and error
    /// codes are; other meetings open on their insights.
    static func preferred(for profile: MeetingProfile) -> Self {
        profile == .internalTechnical ? .transcript : .insights
    }

    var title: String {
        switch self {
        case .insights: "Insights"
        case .transcript: "Transcript"
        }
    }
}

struct RecentTranscriptSegment: Equatable, Identifiable {
    let sequenceNumber: UInt64
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let text: String

    init(
        sequenceNumber: UInt64,
        startOffset: TimeInterval = 0,
        endOffset: TimeInterval = 0,
        text: String
    ) {
        self.sequenceNumber = sequenceNumber
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.text = text
    }

    var id: UInt64 { sequenceNumber }

    var timestamp: String {
        Duration.seconds(max(0, Int(startOffset))).elapsedTimestamp
    }
}

extension Duration {
    var elapsedTimestamp: String {
        formatted(.time(pattern: self >= .seconds(3_600)
            ? .hourMinuteSecond
            : .minuteSecond(padMinuteToLength: 2)))
    }
}

struct RecentMeetingDetailPresentation: Equatable {
    let insights: [InsightCard]
    let orderedTranscriptSegments: [RecentTranscriptSegment]

    init(insights: [InsightCard], transcriptSegments: [RecentTranscriptSegment]) {
        self.insights = insights
        orderedTranscriptSegments = transcriptSegments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    func transcriptSegments(matching query: String) -> [RecentTranscriptSegment] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return orderedTranscriptSegments }
        return orderedTranscriptSegments.filter {
            $0.text.localizedStandardContains(normalizedQuery)
        }
    }

    var transcriptText: String {
        orderedTranscriptSegments
            .map(\.text)
            .joined(separator: "\n")
    }
}

/// The meeting history UI expects the history agent to provide:
/// `MeetingHistoryStore.meetings`, `MeetingHistoryStore.clear(meetingID:)`,
/// `MeetingHistoryStore.clearAll()`, and `SavedMeeting` values with `id`.
/// The clear operations throw if the history cannot be saved. Saved meetings
/// expose `startedAt`, `endedAt`, `insights`, and `transcriptSegments`.
/// Transcript segments expose `sequenceNumber` and `text`.
struct RecentMeetingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingHistoryStore.self) private var meetingHistory
    @State private var selectedMeetingID: UUID?
    @State private var selectedSection: RecentMeetingDetailSection = .insights
    @State private var meetingPendingDeletion: SavedMeeting?
    @State private var isConfirmingClear = false
    @State private var historyDeletionErrorMessage: String?

    private var meetings: [SavedMeeting] {
        meetingHistory.meetings.sorted { $0.startedAt > $1.startedAt }
    }

    private var selectedMeeting: SavedMeeting? {
        guard let selectedMeetingID else { return meetings.first }
        return meetings.first { $0.id == selectedMeetingID } ?? meetings.first
    }

    var body: some View {
        HStack(spacing: 0) {
            meetingList

            Divider()

            if let selectedMeeting {
                meetingDetail(selectedMeeting)
            } else {
                ContentUnavailableView(
                    "No recent meetings",
                    systemImage: "clock",
                    description: Text("Completed meetings are kept on this Mac for two days.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 500, idealHeight: 620)
        .onAppear(perform: selectFirstMeetingIfNeeded)
        .task {
            await meetingHistory.load()
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didWakeNotification
            )
        ) { _ in
            Task { await meetingHistory.load() }
        }
        .onChange(of: meetingHistory.meetings) { _, _ in
            selectFirstMeetingIfNeeded()
        }
        .onChange(of: selectedMeetingID) { _, _ in
            if let selectedMeeting {
                selectedSection = .preferred(for: selectedMeeting.profile)
            }
        }
        .confirmationDialog(
            "Delete this meeting?",
            item: $meetingPendingDeletion,
            titleVisibility: .visible
        ) { meeting in
            Button("Delete", role: .destructive) {
                delete(meeting)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Clear all recent meetings?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    do {
                        try await meetingHistory.clearAll()
                        selectedMeetingID = nil
                    } catch {
                        historyDeletionErrorMessage = "Your saved meetings are still available. Try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved transcripts and insights from this Mac.")
        }
        .alert(
            "Couldn't delete saved meetings",
            item: $historyDeletionErrorMessage
        ) { _ in
        } message: { message in
            Text(message)
        }
    }

    private func delete(_ meeting: SavedMeeting) {
        Task {
            do {
                try await meetingHistory.clear(meetingID: meeting.id)
                if selectedMeetingID == meeting.id {
                    selectedMeetingID = nil
                }
            } catch {
                historyDeletionErrorMessage = "Your saved meetings are still available. Try again."
            }
        }
    }

    private var meetingList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent meetings")
                    .font(.headline)
                Spacer()
                if !meetings.isEmpty {
                    Button("Clear All", role: .destructive) {
                        isConfirmingClear = true
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let issue = meetingHistory.persistenceIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        historyIssueMessage(issue),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)

                    if meetingHistory.pendingMeeting != nil {
                        Button("Retry Save") {
                            Task { try? await meetingHistory.retryPendingMeeting() }
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
            }

            if meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings",
                    systemImage: "clock",
                    description: Text("Saved meetings remain available for two days.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(meetings, selection: $selectedMeetingID) { meeting in
                    MeetingHistoryRow(meeting: meeting)
                        .contextMenu {
                            Button("Delete Meeting", role: .destructive) {
                                meetingPendingDeletion = meeting
                            }
                        }
                        .tag(meeting.id)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 250)
    }

    private func historyIssueMessage(
        _ issue: MeetingHistoryPersistenceIssue
    ) -> String {
        switch issue {
        case .loadFailed:
            "Rio couldn’t read saved meetings. The history file was left unchanged."
        case .saveFailed:
            "The latest meeting isn’t saved yet. Retry before quitting."
        case .expirySaveFailed:
            "Expired meetings are hidden, but Rio couldn’t remove them from disk yet."
        }
    }

    @ViewBuilder
    private func meetingDetail(_ meeting: SavedMeeting) -> some View {
        let presentation = RecentMeetingDetailPresentation(
            insights: meeting.insights.map(\.card),
            transcriptSegments: meeting.transcriptSegments.map {
                RecentTranscriptSegment(
                    sequenceNumber: $0.sequenceNumber,
                    startOffset: $0.startOffset,
                    endOffset: $0.endOffset,
                    text: $0.text
                )
            }
        )

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.startedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.title2.weight(.semibold))
                    Text(meetingDuration(for: meeting))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        meeting.profile.title,
                        systemImage: meeting.profile == .internalTechnical
                            ? "wrench.and.screwdriver"
                            : "person.2"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if meeting.incompleteTranscript {
                        Label("Transcript incomplete", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    meetingPendingDeletion = meeting
                } label: {
                    Label("Delete Meeting", systemImage: "trash")
                }
                .help("Delete this meeting's transcript and insights")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Picker("Meeting detail", selection: $selectedSection) {
                ForEach(RecentMeetingDetailSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedSection {
                case .insights:
                    insightsContent(presentation.insights)
                case .transcript:
                    // The search query lives in this view, so typing redraws only
                    // the transcript, and a different meeting starts a fresh query.
                    RecentMeetingTranscriptView(presentation: presentation)
                        .id(meeting.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
    }

    @ViewBuilder
    private func insightsContent(_ insights: [InsightCard]) -> some View {
        if insights.isEmpty {
            ContentUnavailableView(
                "No insights",
                systemImage: "lightbulb",
                description: Text("Rio did not save any insights for this meeting.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(insights, id: \.stableKey) { card in
                        InsightCardView(card: card)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func selectFirstMeetingIfNeeded() {
        guard let selectedMeetingID,
              meetings.contains(where: { $0.id == selectedMeetingID }) else {
            selectedMeetingID = meetings.first?.id
            return
        }
    }

    private func meetingDuration(for meeting: SavedMeeting) -> String {
        let seconds = max(0, Int(meeting.endedAt.timeIntervalSince(meeting.startedAt)))
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
        )
    }
}

private struct RecentMeetingTranscriptView: View {
    let presentation: RecentMeetingDetailPresentation
    @State private var query = ""

    var body: some View {
        if presentation.orderedTranscriptSegments.isEmpty {
            ContentUnavailableView(
                "No transcript",
                systemImage: "text.quote",
                description: Text("No finalized meeting text was saved.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let matches = presentation.transcriptSegments(matching: query)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search transcript", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search saved transcript")

                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matches) { segment in
                                HStack(alignment: .top, spacing: 14) {
                                    Text(segment.timestamp)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58, alignment: .trailing)
                                        .accessibilityLabel("Meeting time \(segment.timestamp)")
                                    Text(segment.text)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    .clipShape(.rect(cornerRadius: 10))
                }
            }
        }
    }
}

enum MeetingHistoryRowPresentation {
    static func transcriptChunkSummary(count: Int, locale: Locale) -> AttributedString {
        AttributedString(localized: "^[\(count) transcript chunk](inflect: true)", locale: locale)
    }
}

private struct MeetingHistoryRow: View {
    let meeting: SavedMeeting
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(meeting.startedAt, format: .dateTime.month().day().hour().minute())
                .font(.body.weight(.medium))
            HStack(spacing: 8) {
                Text(meeting.endedAt, format: .dateTime.hour().minute())
                Text("•")
                Text(MeetingHistoryRowPresentation.transcriptChunkSummary(
                    count: meeting.transcriptSegments.count,
                    locale: locale
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if meeting.incompleteTranscript {
                Text("Transcript incomplete")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }
}

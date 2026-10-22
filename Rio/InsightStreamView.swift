import SwiftUI

struct LiveInsightPresentation: Equatable {
    let cards: [InsightCard]

    init(cards: [InsightCard]) {
        self.cards = cards.enumerated()
            .sorted { left, right in
                if left.element.changedAt != right.element.changedAt {
                    return left.element.changedAt > right.element.changedAt
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}

struct InsightStreamView: View {
    let cards: [InsightCard]

    var body: some View {
        let orderedCards = LiveInsightPresentation(cards: cards).cards

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Insights")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("Newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(orderedCards.enumerated(), id: \.element.stableKey) { index, card in
                            VStack(spacing: 0) {
                                InsightCardView(card: card)
                                if index != orderedCards.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                            .id(card.stableKey)
                        }
                    }
                }
                .onAppear {
                    scrollToNewest(of: orderedCards, using: proxy)
                }
                .onChange(of: orderedCards.map(\.changedAt)) { _, _ in
                    scrollToNewest(of: orderedCards, using: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting insights")
    }

    private func scrollToNewest(of orderedCards: [InsightCard], using proxy: ScrollViewProxy) {
        guard let newestCard = orderedCards.first else {
            return
        }
        proxy.scrollTo(newestCard.stableKey, anchor: .top)
    }
}

struct InsightCardView: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(card.category.displayName, systemImage: card.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(
                    card.changedAt,
                    format: .dateTime
                        .year()
                        .month(.abbreviated)
                        .day()
                        .hour()
                        .minute()
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Text(card.text)
                .font(.body)
                .foregroundStyle(card.state == .resolved ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityDescription)
    }
}

private extension InsightCategory {
    var displayName: String {
        switch self {
        case .important: "Important"
        case .decision: "Decision"
        case .action: "Action"
        case .question: "Question"
        case .risk: "Risk"
        }
    }

    var symbolName: String {
        switch self {
        case .important: "star.fill"
        case .decision: "checkmark.circle.fill"
        case .action: "arrow.right.circle.fill"
        case .question: "questionmark.circle.fill"
        case .risk: "exclamationmark.triangle.fill"
        }
    }

}

private extension InsightCardState {
    var accessibilityName: String {
        switch self {
        case .new: "New"
        case .updated: "Updated"
        case .resolved: "Resolved"
        }
    }
}

extension InsightCard {
    var accessibilityDescription: String {
        [
            category.displayName,
            state.accessibilityName,
            changedAt.formatted(date: .abbreviated, time: .shortened),
            text,
        ]
        .joined(separator: ", ")
    }
}

import SwiftUI

@MainActor
final class RioApplicationTerminationCoordinator {
    typealias Preparation = @MainActor () async -> Bool

    private let preparation: Preparation
    private var task: Task<Void, Never>?

    init(preparation: @escaping Preparation) {
        self.preparation = preparation
    }

    func request(reply: @escaping @MainActor (Bool) -> Void) {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let shouldTerminate = await preparation()
            task = nil
            reply(shouldTerminate)
        }
    }
}

@MainActor
protocol RioTerminationSessionPreparing: AnyObject {
    func prepareForTermination() async
}

@MainActor
protocol RioTerminationHistoryPreparing: AnyObject {
    var hasPendingTerminationRecord: Bool { get }
    func retryPendingTerminationRecord() async throws
}

@MainActor
final class RioTerminationPreparation {
    private weak var session: (any RioTerminationSessionPreparing)?
    private weak var history: (any RioTerminationHistoryPreparing)?

    init(
        session: any RioTerminationSessionPreparing,
        history: any RioTerminationHistoryPreparing
    ) {
        self.session = session
        self.history = history
    }

    func prepare() async -> Bool {
        guard let session, let history else { return true }
        await session.prepareForTermination()
        if history.hasPendingTerminationRecord {
            do {
                try await history.retryPendingTerminationRecord()
            } catch {
                return false
            }
        }
        return !history.hasPendingTerminationRecord
    }
}

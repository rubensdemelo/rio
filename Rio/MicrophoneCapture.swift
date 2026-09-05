import Foundation

enum MicrophonePermission: Sendable, Equatable {
    case undetermined
    case denied
    case granted
}

final class AudioInputLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var lastLevel: Float = 0
    private var lastUpdate = Date.distantPast
    private var lastSignal = Date.distantPast
    private var hasReceivedAudio = false

    func update(level: Float) {
        // Telemetry must never make the real-time capture callback wait on UI polling.
        guard lock.try() else { return }
        defer { lock.unlock() }

        let now = Date()
        lastLevel = min(1, max(0, level))
        lastUpdate = now
        hasReceivedAudio = true
        if level >= AudioChunk.signalThreshold {
            lastSignal = now
        }
    }

    func snapshot() -> AudioInputSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard hasReceivedAudio else { return .inactive }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(lastUpdate))
        let decayedLevel = lastLevel * Float(exp(-elapsed * 8))
        return AudioInputSnapshot(
            level: decayedLevel,
            hasReceivedAudio: true,
            isMuted: now.timeIntervalSince(lastSignal) >= 2
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastLevel = 0
        lastUpdate = .distantPast
        lastSignal = .distantPast
        hasReceivedAudio = false
    }
}

enum BoundedAudioEnqueueResult: Sendable, Equatable {
    case accepted
    case dropped
    case terminated
}

struct BoundedAudioEnqueueOutcome: Sendable, Equatable {
    let result: BoundedAudioEnqueueResult
    let queueDepth: Int
}

final class BoundedQueue<Element: Sendable>: @unchecked Sendable {
    private let capacity: Int
    private let onDrop: @Sendable () -> Void
    private let lock = NSLock()
    private var storage: [Element?]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var terminated = false
    private var terminalFailure: PipelineFailure?

    private let wakeStream: AsyncStream<Void>
    private let wakeContinuation: AsyncStream<Void>.Continuation

    init(
        capacity: Int,
        onDrop: @escaping @Sendable () -> Void = {}
    ) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.onDrop = onDrop
        storage = Array(repeating: nil, count: capacity)

        var continuation: AsyncStream<Void>.Continuation?
        wakeStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            continuation = $0
        }
        wakeContinuation = continuation!
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func enqueue(_ element: Element) -> BoundedAudioEnqueueOutcome {
        // The realtime producer never waits for the consumer. Contention drops the newest chunk.
        guard lock.try() else {
            onDrop()
            return BoundedAudioEnqueueOutcome(result: .dropped, queueDepth: 0)
        }

        guard !terminated else {
            lock.unlock()
            return BoundedAudioEnqueueOutcome(result: .terminated, queueDepth: 0)
        }
        guard count < capacity else {
            let queueDepth = count
            lock.unlock()
            onDrop()
            return BoundedAudioEnqueueOutcome(result: .dropped, queueDepth: queueDepth)
        }

        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count += 1
        let queueDepth = count
        lock.unlock()
        wakeContinuation.yield(())
        return BoundedAudioEnqueueOutcome(result: .accepted, queueDepth: queueDepth)
    }

    func makeStream(
        onOutputDrop: @escaping @Sendable () -> Void,
        onTermination: @escaping @Sendable () -> Void
    ) -> AsyncThrowingStream<Element, any Error> {
        let stream = AsyncThrowingStream<Element, any Error>(
            bufferingPolicy: .bufferingOldest(capacity)
        ) { continuation in
            let pump = Task { [self] in
                for await _ in wakeStream {
                    drain(into: continuation, onOutputDrop: onOutputDrop)
                }

                drain(into: continuation, onOutputDrop: onOutputDrop)
                continuation.finish(throwing: terminalFailureSnapshot())
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                pump.cancel()
                self?.finish(throwing: .cancelled)
                onTermination()
            }
        }
        return stream
    }

    func finish(throwing failure: PipelineFailure? = nil) {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }

        terminated = true
        terminalFailure = failure
        clearStorageLocked()
        lock.unlock()

        wakeContinuation.finish()
    }

    private func drain(
        into continuation: AsyncThrowingStream<Element, any Error>.Continuation,
        onOutputDrop: @Sendable () -> Void
    ) {
        while let chunk = dequeue() {
            if case .dropped = continuation.yield(chunk) {
                onOutputDrop()
            }
        }
    }

    private func dequeue() -> Element? {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else {
            return nil
        }

        let chunk = storage[readIndex]
        storage[readIndex] = nil
        readIndex = (readIndex + 1) % capacity
        count -= 1
        return chunk
    }

    private func clearStorageLocked() {
        for index in storage.indices {
            storage[index] = nil
        }
        count = 0
        readIndex = 0
        writeIndex = 0
    }

    private func terminalFailureSnapshot() -> PipelineFailure? {
        lock.lock()
        defer { lock.unlock() }
        return terminalFailure
    }
}

typealias BoundedAudioQueue = BoundedQueue<AudioChunk>

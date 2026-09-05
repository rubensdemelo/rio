import XCTest

final class MicrophoneCaptureTests: XCTestCase {
    func testBoundedQueueDropsNewestBufferAtCapacity() {
        let queue = BoundedAudioQueue(capacity: 2)
        defer { queue.finish() }

        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 1)).result, .accepted)
        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 2)).result, .accepted)
        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 3)).result, .dropped)
        XCTAssertEqual(queue.pendingCount, 2)

        queue.finish()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 4)).result, .terminated)
    }

    func testBoundedQueueReportsCapacityLossWithoutBlockingTheProducer() {
        let dropCounter = LockedDropCounter()
        let queue = BoundedAudioQueue(
            capacity: 1,
            onDrop: { dropCounter.increment() }
        )
        defer { queue.finish() }

        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 1)).result, .accepted)
        XCTAssertEqual(queue.enqueue(makeChunk(sequenceNumber: 2)).result, .dropped)
        XCTAssertEqual(dropCounter.value, 1)
    }

    private func makeChunk(sequenceNumber: UInt64) -> AudioChunk {
        AudioChunk(
            sequenceNumber: sequenceNumber,
            duration: .milliseconds(20),
            sampleRate: 48_000,
            channelCount: 1,
            samples: [0.0, 0.1]
        )
    }
}

private final class LockedDropCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

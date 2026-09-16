import CoreAudio
import Foundation
import Synchronization
import XCTest

final class SystemAudioCaptureTests: XCTestCase {
    func testSystemAudioSampleDecoderDecodesFloatPCM() {
        let source: [Float] = [-0.5, 0, 0.5]
        let bytes = source.withUnsafeBytes { Data($0) }

        let decoded = bytes.withUnsafeBytes {
            SystemAudioSampleDecoder.decode(
                bytes: $0,
                bitsPerChannel: 32,
                formatFlags: kAudioFormatFlagIsFloat
            )
        }

        XCTAssertEqual(decoded, source)
    }

    func testRawBufferPoolExhaustionAndReleaseReuse() {
        let pool = CoreAudioRawBufferPool(
            capacity: 1,
            bufferCount: 1,
            byteCapacity: 16
        )

        let first = copy(samples: [0.1, 0.2], into: pool, sequenceNumber: 4)
        XCTAssertNotNil(first)
        XCTAssertEqual(pool.availableSlotCount, 0)
        XCTAssertNil(copy(samples: [0.3], into: pool, sequenceNumber: 5))

        first?.release()
        XCTAssertEqual(pool.availableSlotCount, 1)

        let reused = copy(samples: [0.4, 0.5], into: pool, sequenceNumber: 6)
        XCTAssertEqual(reused?.sequenceNumber, 6)
        XCTAssertEqual(samples(from: reused), [0.4, 0.5])
        reused?.release()
        XCTAssertEqual(pool.availableSlotCount, 1)
    }

    func testRawBufferPoolRejectsOversizedInputWithoutLosingSlot() {
        let pool = CoreAudioRawBufferPool(
            capacity: 1,
            bufferCount: 1,
            byteCapacity: MemoryLayout<Float>.size
        )

        XCTAssertNil(copy(samples: [0.1, 0.2], into: pool, sequenceNumber: 0))
        XCTAssertEqual(pool.availableSlotCount, 1)
        let accepted = copy(samples: [0.3], into: pool, sequenceNumber: 1)
        XCTAssertNotNil(accepted)
        accepted?.release()
    }

    func testCallbackPreservesSequenceOrdering() async throws {
        let rawQueue = BoundedQueue<CoreAudioRawBuffer>(capacity: 3)
        let pool = CoreAudioRawBufferPool(
            capacity: 3,
            bufferCount: 1,
            byteCapacity: 16
        )
        let callbackState = CoreAudioCaptureCallbackState(
            rawQueue: rawQueue,
            rawBufferPool: pool,
            onBufferUnavailable: {}
        )
        // Queue all callbacks before starting the consumer so this ordering test
        // cannot turn a deliberate producer-side contention drop into a hang.
        receive(samples: [0.1], with: callbackState)
        receive(samples: [0.2], with: callbackState)
        receive(samples: [0.3], with: callbackState)

        let stream = rawQueue.makeStream(onOutputDrop: {}, onTermination: {})
        let collector = Task {
            var sequences: [UInt64] = []
            for try await rawBuffer in stream {
                sequences.append(rawBuffer.sequenceNumber)
                rawBuffer.release()
                if sequences.count == 3 {
                    return sequences
                }
            }
            return sequences
        }

        let sequences = try await collector.value
        XCTAssertEqual(sequences, [0, 1, 2])
        rawQueue.finish()
        XCTAssertEqual(pool.availableSlotCount, 3)
    }

    func testCallbackSignalsPoolPressureAndStopsAcceptingDuringTeardown() {
        let overloadCount = Atomic<Int>(0)
        let rawQueue = BoundedQueue<CoreAudioRawBuffer>(capacity: 2)
        let pool = CoreAudioRawBufferPool(
            capacity: 1,
            bufferCount: 1,
            byteCapacity: 16
        )
        let callbackState = CoreAudioCaptureCallbackState(
            rawQueue: rawQueue,
            rawBufferPool: pool,
            onBufferUnavailable: { overloadCount.add(1, ordering: .relaxed) }
        )

        receive(samples: [0.1], with: callbackState)
        receive(samples: [0.2], with: callbackState)
        XCTAssertEqual(overloadCount.load(ordering: .relaxed), 1)
        XCTAssertEqual(rawQueue.pendingCount, 1)

        callbackState.stopAccepting()
        receive(samples: [0.3], with: callbackState)
        XCTAssertEqual(overloadCount.load(ordering: .relaxed), 1)
        XCTAssertEqual(rawQueue.pendingCount, 1)
        rawQueue.finish()
    }

    func testStoppingPoolPreservesOwnedBufferUntilConsumerReleasesIt() {
        let pool = CoreAudioRawBufferPool(
            capacity: 1,
            bufferCount: 1,
            byteCapacity: 16
        )
        let owned = copy(samples: [0.25, 0.75], into: pool, sequenceNumber: 0)

        pool.stopAccepting()

        XCTAssertFalse(pool.isAcceptingBuffers)
        XCTAssertNil(copy(samples: [1], into: pool, sequenceNumber: 1))
        XCTAssertEqual(samples(from: owned), [0.25, 0.75])
        owned?.release()
        XCTAssertEqual(pool.availableSlotCount, 1)
    }

    private func copy(
        samples: [Float],
        into pool: CoreAudioRawBufferPool,
        sequenceNumber: UInt64
    ) -> CoreAudioRawBuffer? {
        withAudioBufferList(samples: samples) {
            pool.copy($0, sequenceNumber: sequenceNumber)
        }
    }

    private func receive(
        samples: [Float],
        with callbackState: CoreAudioCaptureCallbackState
    ) {
        withAudioBufferList(samples: samples) {
            callbackState.receive($0)
        }
    }

    private func samples(from rawBuffer: CoreAudioRawBuffer?) -> [Float]? {
        rawBuffer?.withUnsafeBytes(at: 0) { bytes in
            SystemAudioSampleDecoder.decode(
                bytes: bytes,
                bitsPerChannel: 32,
                formatFlags: kAudioFormatFlagIsFloat
            )
        }
    }

    private func withAudioBufferList<Result>(
        samples: [Float],
        _ body: (UnsafePointer<AudioBufferList>) -> Result
    ) -> Result {
        var samples = samples
        return samples.withUnsafeMutableBytes { bytes in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            return withUnsafePointer(to: &bufferList, body)
        }
    }
}

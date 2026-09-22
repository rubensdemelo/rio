import CoreAudio
import Foundation
import Synchronization
import XCTest

final class SystemAudioCaptureTests: XCTestCase {
    func testVerificationCommandReportsSuccessfulCancelledCaptureCycle() async {
        let capture = VerificationAudioCapture()

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=2",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture,
            maximumCallbackGap: .milliseconds(750)
        )

        XCTAssertEqual(report.failureCategory, .none)
        XCTAssertEqual(report.cyclesRequested, 2)
        XCTAssertEqual(report.cyclesCompleted, 2)
        XCTAssertEqual(report.chunksObserved, 20)
        XCTAssertEqual(report.signalChunksObserved, 20)
        XCTAssertEqual(report.audioMillisecondsObserved, 2_000)
        XCTAssertLessThanOrEqual(report.maximumCallbackGapMilliseconds, 750)
        let cancelCount = await capture.cancelCount()
        XCTAssertEqual(cancelCount, 2)
    }

    func testVerificationCommandRejectsOutOfRangeOptions() async {
        let capture = VerificationAudioCapture()

        for arguments in [
            [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=0",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=2",
                "--capture-seconds=1801",
                "--capture-run-token=test-run-token-0001",
            ],
            [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
            ],
            [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=unsafe/token/value",
            ],
        ] {
            let report = await SystemAudioCaptureVerificationCommand.run(
                arguments: arguments,
                capture: capture
            )

            XCTAssertEqual(report.failureCategory, .invalidArguments)
            XCTAssertEqual(report.cyclesCompleted, 0)
        }
        let cancelCount = await capture.cancelCount()
        XCTAssertEqual(cancelCount, 0)
    }

    func testVerificationCommandRejectsNonCancellationTermination() async {
        let capture = VerificationAudioCapture(
            cancelFailure: .stage(.audioCapture, .failed)
        )

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture
        )

        XCTAssertEqual(report.failureCategory, .unexpectedFailure)
        XCTAssertEqual(report.cyclesCompleted, 0)
        XCTAssertEqual(report.chunksObserved, 10)
        XCTAssertEqual(report.signalChunksObserved, 10)
        XCTAssertEqual(report.audioMillisecondsObserved, 1_000)
    }

    func testVerificationCommandRejectsSilentOnlyCapture() async {
        let capture = VerificationAudioCapture(inputLevel: 0)

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture
        )

        XCTAssertEqual(report.failureCategory, .noSignal)
        XCTAssertEqual(report.cyclesCompleted, 0)
        XCTAssertEqual(report.chunksObserved, 10)
        XCTAssertEqual(report.signalChunksObserved, 0)
        XCTAssertEqual(report.audioMillisecondsObserved, 1_000)
    }

    func testVerificationCommandRejectsOneSignalChunkThenStall() async {
        let capture = VerificationAudioCapture(
            chunkCount: 1,
            chunkDuration: .milliseconds(20)
        )

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture
        )

        XCTAssertEqual(report.failureCategory, .insufficientDuration)
        XCTAssertEqual(report.cyclesCompleted, 0)
        XCTAssertEqual(report.chunksObserved, 1)
        XCTAssertEqual(report.signalChunksObserved, 1)
        XCTAssertEqual(report.audioMillisecondsObserved, 20)
    }

    func testVerificationCommandRejectsCallbackStallAfterEnoughAudio() async {
        let capture = VerificationAudioCapture(emissionInterval: .zero)

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture,
            maximumCallbackGap: .milliseconds(50)
        )

        XCTAssertEqual(report.failureCategory, .callbackStalled)
        XCTAssertEqual(report.cyclesCompleted, 0)
        XCTAssertEqual(report.audioMillisecondsObserved, 1_000)
        XCTAssertGreaterThan(report.maximumCallbackGapMilliseconds, 50)
    }

    func testVerificationCommandRejectsDelayedFirstCallback() async {
        let capture = VerificationAudioCapture(
            chunkCount: 16,
            initialEmissionDelay: .milliseconds(200),
            emissionInterval: .milliseconds(50)
        )

        let report = await SystemAudioCaptureVerificationCommand.run(
            arguments: [
                "Rio",
                "--verify-system-audio-capture",
                "--capture-cycles=1",
                "--capture-seconds=1",
                "--capture-run-token=test-run-token-0001",
            ],
            capture: capture,
            maximumCallbackGap: .milliseconds(120)
        )

        XCTAssertEqual(report.failureCategory, .callbackStalled)
        XCTAssertEqual(report.cyclesCompleted, 0)
        XCTAssertGreaterThanOrEqual(report.audioMillisecondsObserved, 800)
        XCTAssertGreaterThan(report.maximumCallbackGapMilliseconds, 120)
    }

    func testVerificationReportJSONContainsOnlyContentFreeMetrics() throws {
        let report = SystemAudioCaptureVerificationReport(
            cyclesRequested: 2,
            cyclesCompleted: 2,
            captureSeconds: 3,
            chunksObserved: 42,
            signalChunksObserved: 21,
            audioMillisecondsObserved: 840,
            maximumCallbackGapMilliseconds: 40,
            elapsedMilliseconds: 6_010,
            failureCategory: .none
        )

        let data = try XCTUnwrap(
            SystemAudioCaptureVerificationCommand.encodedJSON(report)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            Set([
                "cyclesRequested",
                "cyclesCompleted",
                "captureSeconds",
                "chunksObserved",
                "signalChunksObserved",
                "audioMillisecondsObserved",
                "maximumCallbackGapMilliseconds",
                "elapsedMilliseconds",
                "failureCategory",
            ])
        )
    }

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

    func testRawBufferDecoderPreservesCaptureCancellationFailure() async throws {
        let rawQueue = BoundedQueue<CoreAudioRawBuffer>(capacity: 1)
        let destination = BoundedAudioQueue(capacity: 1)
        let output = destination.makeStream(
            onOutputDrop: {},
            onTermination: {}
        )
        let task = CoreAudioRawBufferDecodingTask.make(
            rawQueue: rawQueue,
            destination: destination,
            format: AudioStreamBasicDescription(
                mSampleRate: 48_000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
                mChannelsPerFrame: 1,
                mBitsPerChannel: 32,
                mReserved: 0
            ),
            inputLevelMonitor: AudioInputLevelMonitor(),
            onContinuityLoss: {}
        )
        let pool = CoreAudioRawBufferPool(
            capacity: 1,
            bufferCount: 1,
            byteCapacity: 16
        )
        let rawBuffer = try XCTUnwrap(
            copy(samples: [0.25, -0.25], into: pool, sequenceNumber: 0)
        )
        XCTAssertEqual(rawQueue.enqueue(rawBuffer).result, .accepted)
        var iterator = output.makeAsyncIterator()
        let firstChunk = try await iterator.next()
        XCTAssertNotNil(firstChunk)

        rawQueue.finish(throwing: .cancelled)

        do {
            _ = try await iterator.next()
            XCTFail("Expected capture cancellation to terminate decoder output")
        } catch let failure as PipelineFailure {
            XCTAssertEqual(failure, .cancelled)
        } catch {
            XCTFail("Expected PipelineFailure.cancelled, got \(error)")
        }
        await task.value
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

private actor VerificationAudioCapture: AudioCapture {
    private let cancelFailure: PipelineFailure
    private let inputLevel: Float
    private let chunkCount: Int
    private let chunkDuration: Duration
    private let initialEmissionDelay: Duration
    private let emissionInterval: Duration
    private var continuation: AudioStream.Continuation?
    private var producerTask: Task<Void, Never>?
    private var cancellations = 0

    init(
        cancelFailure: PipelineFailure = .cancelled,
        inputLevel: Float = 0.25,
        chunkCount: Int = 10,
        chunkDuration: Duration = .milliseconds(100),
        initialEmissionDelay: Duration = .zero,
        emissionInterval: Duration = .milliseconds(50)
    ) {
        self.cancelFailure = cancelFailure
        self.inputLevel = inputLevel
        self.chunkCount = chunkCount
        self.chunkDuration = chunkDuration
        self.initialEmissionDelay = initialEmissionDelay
        self.emissionInterval = emissionInterval
    }

    func start() async throws(PipelineFailure) -> AudioStream {
        let stream = AudioStream { continuation in
            self.continuation = continuation
        }
        let producerContinuation = continuation
        producerTask = Task {
            if initialEmissionDelay > .zero {
                do {
                    try await Task.sleep(for: initialEmissionDelay)
                } catch {
                    return
                }
            }
            for sequenceNumber in 0..<chunkCount {
                if sequenceNumber > 0, emissionInterval > .zero {
                    do {
                        try await Task.sleep(for: emissionInterval)
                    } catch {
                        return
                    }
                }
                producerContinuation?.yield(
                    AudioChunk(
                        sequenceNumber: UInt64(sequenceNumber),
                        duration: chunkDuration,
                        sampleRate: 48_000,
                        channelCount: 2,
                        samples: [inputLevel, inputLevel],
                        inputLevel: inputLevel
                    )
                )
            }
        }
        return stream
    }

    func stop() async {
        producerTask?.cancel()
        producerTask = nil
        continuation?.finish()
        continuation = nil
    }

    func cancel() async {
        cancellations += 1
        producerTask?.cancel()
        producerTask = nil
        continuation?.finish(throwing: cancelFailure)
        continuation = nil
    }

    func cancelCount() -> Int { cancellations }
}

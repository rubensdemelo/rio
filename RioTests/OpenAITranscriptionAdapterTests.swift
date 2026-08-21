import Foundation
import XCTest

final class OpenAITranscriptionAdapterTests: XCTestCase {
    func testWAVEncoderCreatesPCM16WaveData() {
        let data = WAVEncoder.encode(
            interleavedSamples: [-1, 0, 1],
            sampleRate: 16_000,
            channelCount: 1
        )

        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(data.count, 50)
    }

    func testTranscriptionSendsInMemoryWAVAndEmitsFinalizedText() async throws {
        let client = RecordingTranscriptionHTTPClient(text: " meeting decision ")
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            batchDuration: .seconds(1)
        )
        let stream = try await adapter.recognize(audio: audioStream())
        var segments: [FinalizedSpeechSegment] = []
        for try await segment in stream {
            segments.append(segment)
        }

        XCTAssertEqual(segments.map(\.text), ["meeting decision"])
        XCTAssertEqual(segments.first?.startOffset, .zero)
        XCTAssertEqual(segments.first?.endOffset, .seconds(1))
        let recordedRequest = await client.request()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        XCTAssertTrue(request.httpBody?.range(of: Data("name=\"model\"\r\n\r\ngpt-transcribe\r\n".utf8)) != nil)
        XCTAssertTrue(request.httpBody?.range(of: Data("name=\"language\"\r\n\r\nen\r\n".utf8)) != nil)
        XCTAssertTrue(request.httpBody?.range(of: Data("RIFF".utf8)) != nil)
        XCTAssertNil(request.httpBody?.range(of: Data("meeting decision".utf8)))
    }

    func testTranscriptionSendsConfiguredTechnicalVocabularyOnlyAsPrompt() async throws {
        let client = RecordingTranscriptionHTTPClient(text: "technical term")
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            batchDuration: .seconds(1),
            transcriptionPromptProvider: { "Db2, IRLM, DASD" }
        )
        let stream = try await adapter.recognize(audio: audioStream())

        for try await _ in stream {}

        let request = await client.request()
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertNotNil(body.range(of: Data("name=\"prompt\"\r\n\r\nDb2, IRLM, DASD\r\n".utf8)))
    }

    func testMissingAPIKeyIsReportedBeforeAudioCapture() async {
        let adapter = OpenAITranscriptionAdapter(
            configuration: nil,
            configurationProvider: { nil }
        )
        let availability = await adapter.availability()
        XCTAssertEqual(availability, .unavailable(.openAIAPIKeyMissing))
        do {
            try await adapter.prepare()
            XCTFail("A missing key must block transcription")
        } catch let failure {
            XCTAssertEqual(failure, .unavailable(.openAIAPIKeyMissing))
        }
    }

    func testBatchDurationCanBeConfiguredBeforeTheNextRequest() async throws {
        let client = RecordingTranscriptionHTTPClient(text: "configured")
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            batchDuration: .seconds(1)
        )
        await adapter.configure(batchDuration: .seconds(2))

        let stream = try await adapter.recognize(audio: AudioStream { continuation in
            continuation.yield(
                AudioChunk(
                    sequenceNumber: 0,
                    duration: .seconds(1),
                    sampleRate: 16_000,
                    channelCount: 1,
                    samples: Array(repeating: 0.1, count: 16_000)
                )
            )
            continuation.yield(
                AudioChunk(
                    sequenceNumber: 1,
                    duration: .seconds(1),
                    sampleRate: 16_000,
                    channelCount: 1,
                    samples: Array(repeating: 0.1, count: 16_000)
                )
            )
            continuation.finish()
        })

        for try await _ in stream {}

        let recordedRequest = await client.request()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: Data("RIFF".utf8)))
        XCTAssertGreaterThan(body.count, 64_000)
    }

    func testProfileConfigurationCanClearTheLegacyVocabularyProvider() async throws {
        let client = RecordingTranscriptionHTTPClient(text: "configured")
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            transcriptionPromptProvider: { "legacy vocabulary" }
        )
        await adapter.configure(batchDuration: .seconds(1), transcriptionPrompt: nil)

        let stream = try await adapter.recognize(audio: audioStream())
        for try await _ in stream {}

        let request = await client.request()
        let body = try XCTUnwrap(request?.httpBody)
        XCTAssertNil(body.range(of: Data("name=\"prompt\"".utf8)))
    }

    func testBackpressureStopsBeforeCreatingASilentTranscriptGap() async throws {
        let client = BlockingTranscriptionHTTPClient()
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            batchDuration: .seconds(1)
        )
        var audioContinuation: AudioStream.Continuation?
        let audio = AudioStream { audioContinuation = $0 }
        let stream = try await adapter.recognize(audio: audio)
        let collection = Task {
            do {
                var segments: [FinalizedSpeechSegment] = []
                for try await segment in stream {
                    segments.append(segment)
                }
                return Result<[FinalizedSpeechSegment], PipelineFailure>.success(segments)
            } catch let failure as PipelineFailure {
                return .failure(failure)
            } catch {
                return .failure(.stage(.speechRecognition, .failed))
            }
        }

        audioContinuation?.yield(chunk(sequenceNumber: 0))
        audioContinuation?.yield(chunk(sequenceNumber: 1))
        await client.waitForFirstRequest()
        for sequenceNumber in 2..<5 {
            audioContinuation?.yield(chunk(sequenceNumber: UInt64(sequenceNumber)))
        }
        audioContinuation?.finish()
        await client.releaseFirstRequest()

        switch await collection.value {
        case .success(let segments):
            XCTFail("Backpressure must be explicit instead of returning a gapped transcript: \(segments.map(\.startOffset))")
        case .failure(let failure):
            XCTAssertEqual(failure, .stage(.speechRecognition, .overloaded))
        }
    }

    func testPauseAndResumePreserveSegmentOrderingAndElapsedOffsetsWithinSession() async throws {
        let client = RecordingTranscriptionHTTPClient(text: "continued")
        let adapter = OpenAITranscriptionAdapter(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client,
            batchDuration: .seconds(1)
        )

        let firstStream = try await adapter.recognize(audio: audioStream())
        let firstSegments = try await collect(firstStream)
        await adapter.pause()
        let resumedStream = try await adapter.recognize(audio: audioStream())
        let resumedSegments = try await collect(resumedStream)

        XCTAssertEqual(firstSegments.first?.sequenceNumber, 0)
        XCTAssertEqual(firstSegments.first?.startOffset, .zero)
        XCTAssertEqual(resumedSegments.first?.sequenceNumber, 1)
        XCTAssertEqual(resumedSegments.first?.startOffset, .seconds(1))

        await adapter.stop()
        let nextSessionStream = try await adapter.recognize(audio: audioStream())
        let nextSessionSegments = try await collect(nextSessionStream)
        XCTAssertEqual(nextSessionSegments.first?.sequenceNumber, 0)
        XCTAssertEqual(nextSessionSegments.first?.startOffset, .zero)
        await adapter.stop()
    }

    private func audioStream() -> AudioStream {
        AudioStream { continuation in
            continuation.yield(
                AudioChunk(
                    sequenceNumber: 0,
                    duration: .seconds(1),
                    sampleRate: 16_000,
                    channelCount: 1,
                    samples: Array(repeating: 0.1, count: 16_000)
                )
            )
            continuation.finish()
        }
    }

    private func chunk(sequenceNumber: UInt64) -> AudioChunk {
        AudioChunk(
            sequenceNumber: sequenceNumber,
            duration: .seconds(1),
            sampleRate: 16_000,
            channelCount: 1,
            samples: Array(repeating: 0.1, count: 16_000)
        )
    }

    private func collect(_ stream: FinalizedSpeechStream) async throws -> [FinalizedSpeechSegment] {
        var segments: [FinalizedSpeechSegment] = []
        for try await segment in stream {
            segments.append(segment)
        }
        return segments
    }
}

private actor RecordingTranscriptionHTTPClient: OpenAIHTTPClient {
    private var recordedRequest: URLRequest?
    private let text: String

    init(text: String) {
        self.text = text
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequest = request
        return (
            try JSONSerialization.data(withJSONObject: ["text": text]),
            HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func request() -> URLRequest? { recordedRequest }
}

private actor BlockingTranscriptionHTTPClient: OpenAIHTTPClient {
    private var requestCount = 0
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isFirstRequestReleased = false

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let requestNumber = requestCount
        if requestNumber == 1 {
            let waiters = firstRequestWaiters
            firstRequestWaiters.removeAll()
            waiters.forEach { $0.resume() }
            if !isFirstRequestReleased {
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
            }
        }
        try Task.checkCancellation()
        return (
            try JSONSerialization.data(withJSONObject: ["text": "chunk-\(requestNumber)"]),
            HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func waitForFirstRequest() async {
        guard requestCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        isFirstRequestReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

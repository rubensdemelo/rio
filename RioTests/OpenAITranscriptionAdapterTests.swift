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

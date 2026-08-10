import Foundation

private struct WAVAudioBatch: Sendable {
    let sampleRate: Int
    let channelCount: Int
    let samples: [Float]
    let startOffset: Duration
    let endOffset: Duration

    var wavData: Data {
        WAVEncoder.encode(
            interleavedSamples: samples,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}

enum WAVEncoder {
    static func encode(
        interleavedSamples: [Float],
        sampleRate: Int,
        channelCount: Int
    ) -> Data {
        precondition(sampleRate > 0)
        precondition(channelCount > 0)

        let byteCount = interleavedSamples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + byteCount)
        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + byteCount), to: &data)
        data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(channelCount), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * channelCount * MemoryLayout<Int16>.size), to: &data)
        append(UInt16(channelCount * MemoryLayout<Int16>.size), to: &data)
        append(UInt16(16), to: &data)
        data.append("data".data(using: .ascii)!)
        append(UInt32(byteCount), to: &data)

        for sample in interleavedSamples {
            let normalized = min(1, max(-1, sample))
            let pcm = normalized <= -1
                ? Int16.min
                : Int16((normalized * Float(Int16.max)).rounded())
            append(UInt16(bitPattern: pcm), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

private enum OpenAITranscriptionRequest {
    static func make(
        configuration: OpenAIAPIConfiguration,
        audio: Data
    ) -> URLRequest {
        let boundary = "RioBoundary-\(UUID().uuidString)"
        var body = Data()
        appendField("model", value: configuration.transcriptionModel, boundary: boundary, to: &body)
        appendField("response_format", value: "json", boundary: boundary, to: &body)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"meeting.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    private static func appendField(
        _ name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append(value.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
    }
}

private struct OpenAITranscriptionResponse: Decodable, Sendable {
    let text: String
}

private actor OpenAITranscriptionQueue {
    private let configuration: OpenAIAPIConfiguration
    private let client: any OpenAIHTTPClient
    private let continuation: FinalizedSpeechStream.Continuation
    private var pending: [WAVAudioBatch] = []
    private var worker: Task<Void, Never>?
    private var acceptsInput = true
    private var nextSequenceNumber: UInt64 = 0

    init(
        configuration: OpenAIAPIConfiguration,
        client: any OpenAIHTTPClient,
        continuation: FinalizedSpeechStream.Continuation
    ) {
        self.configuration = configuration
        self.client = client
        self.continuation = continuation
    }

    func enqueue(_ batch: WAVAudioBatch) {
        guard acceptsInput else { return }
        if pending.count == 2 {
            pending.removeFirst()
        }
        pending.append(batch)
        startNextIfNeeded()
    }

    func finishInput() {
        acceptsInput = false
        startNextIfNeeded()
    }

    func cancel() {
        acceptsInput = false
        pending.removeAll()
        worker?.cancel()
        worker = nil
        continuation.finish(throwing: PipelineFailure.cancelled)
    }

    private func startNextIfNeeded() {
        guard worker == nil else { return }
        guard !pending.isEmpty else {
            if !acceptsInput {
                continuation.finish()
            }
            return
        }

        let batch = pending.removeFirst()
        let configuration = configuration
        let client = client
        let worker = Task { [weak self] in
            do {
                let request = OpenAITranscriptionRequest.make(
                    configuration: configuration,
                    audio: batch.wavData
                )
                let (data, response) = try await client.data(for: request)
                guard (200...299).contains(response.statusCode) else {
                    throw OpenAIHTTPError.unexpectedStatus(response.statusCode)
                }
                let output = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
                try Task.checkCancellation()
                await self?.completed(batch: batch, text: output.text)
            } catch {
                await self?.failed(error)
            }
        }
        self.worker = worker
    }

    private func completed(batch: WAVAudioBatch, text: String) {
        worker = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            continuation.yield(
                FinalizedSpeechSegment(
                    sequenceNumber: nextSequenceNumber,
                    text: trimmed,
                    startOffset: batch.startOffset,
                    endOffset: batch.endOffset
                )
            )
            nextSequenceNumber &+= 1
        }
        startNextIfNeeded()
    }

    private func failed(_ error: any Error) {
        worker = nil
        acceptsInput = false
        pending.removeAll()
        if error is CancellationError {
            continuation.finish(throwing: PipelineFailure.cancelled)
            return
        }
        if let error = error as? OpenAIHTTPError,
           case .unexpectedStatus(let status) = error,
           status == 401 || status == 403 {
            continuation.finish(throwing: PipelineFailure.unavailable(.openAIAPIKeyInvalid))
            return
        }
        continuation.finish(throwing: PipelineFailure.stage(.speechRecognition, .failed))
    }
}

actor OpenAITranscriptionAdapter: SessionSpeechRecognizer {
    private let configurationProvider: @Sendable () -> OpenAIAPIConfiguration?
    private let client: any OpenAIHTTPClient
    private var batchDuration: Duration
    private var processingTask: Task<Void, Never>?
    private var queue: OpenAITranscriptionQueue?

    init(
        configuration: OpenAIAPIConfiguration? = nil,
        configurationProvider: @escaping @Sendable () -> OpenAIAPIConfiguration? = {
            OpenAIAPIConfiguration.stored()
        },
        client: any OpenAIHTTPClient = URLSessionOpenAIHTTPClient(),
        batchDuration: Duration = .seconds(15)
    ) {
        self.configurationProvider = { configuration ?? configurationProvider() }
        self.client = client
        self.batchDuration = batchDuration
    }

    func configure(batchDuration: Duration) async {
        guard batchDuration > .zero, processingTask == nil, queue == nil else { return }
        self.batchDuration = batchDuration
    }

    func availability() async -> Availability {
        configurationProvider() == nil ? .unavailable(.openAIAPIKeyMissing) : .available
    }

    func prepare() async throws(PipelineFailure) {
        guard configurationProvider() != nil else {
            throw .unavailable(.openAIAPIKeyMissing)
        }
    }

    func recognize(audio: AudioStream) async throws(PipelineFailure) -> FinalizedSpeechStream {
        guard processingTask == nil, queue == nil else {
            throw .stage(.speechRecognition, .invalidState)
        }
        guard let configuration = configurationProvider() else {
            throw .unavailable(.openAIAPIKeyMissing)
        }

        var outputContinuation: FinalizedSpeechStream.Continuation?
        let output = FinalizedSpeechStream(bufferingPolicy: .bufferingOldest(16)) { continuation in
            outputContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.cancel() }
            }
        }
        guard let outputContinuation else {
            throw .stage(.speechRecognition, .failed)
        }

        let queue = OpenAITranscriptionQueue(
            configuration: configuration,
            client: client,
            continuation: outputContinuation
        )
        self.queue = queue
        processingTask = Task { [weak self] in
            await self?.collect(audio: audio, queue: queue)
        }
        return output
    }

    func stop() async {
        await cancel()
    }

    func cancel() async {
        processingTask?.cancel()
        processingTask = nil
        await queue?.cancel()
        queue = nil
    }

    private func collect(audio: AudioStream, queue: OpenAITranscriptionQueue) async {
        var batch: WAVAudioBatch?
        var nextOffset = Duration.zero
        do {
            for try await chunk in audio {
                try Task.checkCancellation()
                guard let sampleRate = Int(exactly: chunk.sampleRate),
                      sampleRate > 0,
                      chunk.channelCount > 0,
                      chunk.samples.count.isMultiple(of: chunk.channelCount) else {
                    throw PipelineFailure.stage(.speechRecognition, .invalidState)
                }

                if let current = batch,
                   (current.sampleRate != sampleRate || current.channelCount != chunk.channelCount || current.endOffset - current.startOffset >= batchDuration) {
                    await queue.enqueue(current)
                    batch = nil
                }

                let startOffset = nextOffset
                nextOffset += chunk.duration
                if let current = batch {
                    let samples = current.samples + chunk.samples
                    batch = WAVAudioBatch(
                        sampleRate: current.sampleRate,
                        channelCount: current.channelCount,
                        samples: samples,
                        startOffset: current.startOffset,
                        endOffset: nextOffset
                    )
                } else {
                    batch = WAVAudioBatch(
                        sampleRate: sampleRate,
                        channelCount: chunk.channelCount,
                        samples: chunk.samples,
                        startOffset: startOffset,
                        endOffset: nextOffset
                    )
                }
            }
            if let batch {
                await queue.enqueue(batch)
            }
            await queue.finishInput()
        } catch is CancellationError {
            await queue.cancel()
        } catch {
            await queue.cancel()
        }
        processingTask = nil
    }
}

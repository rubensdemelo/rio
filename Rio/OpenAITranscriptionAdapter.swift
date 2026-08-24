import Foundation

private final class WAVAudioBatch: @unchecked Sendable {
    let sequenceNumber: UInt64
    let sampleRate: Int
    let channelCount: Int
    private(set) var samples: [Float]
    let startOffset: Duration
    private(set) var endOffset: Duration

    init(
        sequenceNumber: UInt64,
        sampleRate: Int,
        channelCount: Int,
        samples: [Float],
        startOffset: Duration,
        endOffset: Duration
    ) {
        self.sequenceNumber = sequenceNumber
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    var wavData: Data {
        WAVEncoder.encode(
            interleavedSamples: samples,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    func append(_ samples: [Float], endingAt endOffset: Duration) {
        self.samples.append(contentsOf: samples)
        self.endOffset = endOffset
    }

    func canAppend(sampleCount: Int) -> Bool {
        WAVEncoder.canEncode(sampleCount: samples.count + sampleCount)
    }
}

enum WAVEncoder {
    // Leave headroom below the transcription endpoint's 25 MB file limit.
    static let maximumFileByteCount = 24_000_000

    static func canEncode(sampleCount: Int) -> Bool {
        sampleCount >= 0
            && sampleCount <= (maximumFileByteCount - 44) / MemoryLayout<Int16>.size
    }

    static func encode(
        interleavedSamples: [Float],
        sampleRate: Int,
        channelCount: Int
    ) -> Data {
        precondition(sampleRate > 0)
        precondition(channelCount > 0)
        precondition(canEncode(sampleCount: interleavedSamples.count))

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
    static let timeoutInterval: TimeInterval = 120

    static func make(
        configuration: OpenAIAPIConfiguration,
        audio: Data,
        prompt: String?,
        keywordHints: [String]
    ) -> URLRequest {
        let boundary = "RioBoundary-\(UUID().uuidString)"
        var body = Data()
        appendField("model", value: configuration.transcriptionModel, boundary: boundary, to: &body)
        appendField("language", value: "en", boundary: boundary, to: &body)
        if configuration.transcriptionModel == OpenAIAPIConfiguration.defaultTranscriptionModel {
            appendField("chunking_strategy", value: "auto", boundary: boundary, to: &body)
            for keyword in keywordHints {
                appendField("keywords[]", value: keyword, boundary: boundary, to: &body)
            }
        }
        if let prompt {
            appendField("prompt", value: prompt, boundary: boundary, to: &body)
        }
        appendField("response_format", value: "json", boundary: boundary, to: &body)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"meeting.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
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

private enum TranscriptionRequestContext {
    static let maximumPreviousTextLength = 1_000

    static func keywordHints(from technicalVocabulary: String?) -> [String] {
        guard let technicalVocabulary else { return [] }

        var seen: Set<String> = []
        return technicalVocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .compactMap { rawTerm in
                let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { return nil }
                let key = term.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                guard seen.insert(key).inserted else { return nil }
                return term
            }
    }

    static func prompt(
        technicalVocabulary: String?,
        previousFinalizedText: String?
    ) -> String? {
        guard let previousFinalizedText else { return technicalVocabulary }
        let previousContext = String(previousFinalizedText.suffix(maximumPreviousTextLength))
        guard let technicalVocabulary else {
            return "Previous finalized transcript context:\n\(previousContext)"
        }
        return """
        Technical vocabulary:
        \(technicalVocabulary)

        Previous finalized transcript context:
        \(previousContext)
        """
    }
}

private enum TranscriptionRetryPolicy {
    static let maximumRetryCount = 2

    static func delay(forRetry retry: Int) -> Duration {
        retry == 1 ? .milliseconds(250) : .milliseconds(750)
    }

    static func shouldRetry(_ error: any Error) -> Bool {
        if let error = error as? URLError {
            return error.code != .cancelled
        }
        guard let error = error as? OpenAIHTTPError else { return false }
        switch error {
        case .invalidResponse, .malformedResponse:
            return true
        case .unexpectedStatus(let status):
            return status == 408 || status == 409 || status == 429 || (500...599).contains(status)
        case .incompleteResponse, .refusedResponse, .missingOutputText:
            return false
        }
    }
}

private struct OpenAITranscriptionResponse: Decodable, Sendable {
    let text: String
}

private actor OpenAITranscriptionQueue {
    private static let maximumPendingBatchCount = 2

    private let configuration: OpenAIAPIConfiguration
    private let client: any OpenAIHTTPClient
    private let continuation: FinalizedSpeechStream.Continuation
    private let technicalVocabulary: String?
    private let keywordHints: [String]
    private var pending: [WAVAudioBatch] = []
    private var worker: Task<Void, Never>?
    private var acceptsInput = true
    private var isTerminated = false
    private var previousFinalizedText: String?

    init(
        configuration: OpenAIAPIConfiguration,
        client: any OpenAIHTTPClient,
        continuation: FinalizedSpeechStream.Continuation,
        technicalVocabulary: String?
    ) {
        self.configuration = configuration
        self.client = client
        self.continuation = continuation
        self.technicalVocabulary = technicalVocabulary
        keywordHints = TranscriptionRequestContext.keywordHints(from: technicalVocabulary)
    }

    func enqueue(_ batch: WAVAudioBatch) {
        guard acceptsInput, !isTerminated else { return }
        guard pending.count < Self.maximumPendingBatchCount else {
            terminate(throwing: .stage(.speechRecognition, .overloaded))
            return
        }
        pending.append(batch)
        startNextIfNeeded()
    }

    func finishInput() {
        guard !isTerminated else { return }
        acceptsInput = false
        startNextIfNeeded()
    }

    func cancel() {
        terminate(throwing: .cancelled)
    }

    private func startNextIfNeeded() {
        guard !isTerminated, worker == nil else { return }
        guard !pending.isEmpty else {
            if !acceptsInput {
                isTerminated = true
                continuation.finish()
            }
            return
        }

        let batch = pending.removeFirst()
        let configuration = configuration
        let client = client
        let requestPrompt = TranscriptionRequestContext.prompt(
            technicalVocabulary: technicalVocabulary,
            previousFinalizedText: previousFinalizedText
        )
        let keywordHints = keywordHints
        let worker = Task { [weak self] in
            var retryCount = 0
            while true {
                do {
                    let request = OpenAITranscriptionRequest.make(
                        configuration: configuration,
                        audio: batch.wavData,
                        prompt: requestPrompt,
                        keywordHints: keywordHints
                    )
                    let (data, response) = try await client.data(for: request)
                    guard (200...299).contains(response.statusCode) else {
                        throw OpenAIHTTPError.unexpectedStatus(response.statusCode)
                    }
                    let output: OpenAITranscriptionResponse
                    do {
                        output = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
                    } catch {
                        throw OpenAIHTTPError.malformedResponse
                    }
                    try Task.checkCancellation()
                    await self?.completed(batch: batch, text: output.text)
                    return
                } catch {
                    guard TranscriptionRetryPolicy.shouldRetry(error),
                          retryCount < TranscriptionRetryPolicy.maximumRetryCount else {
                        await self?.failed(error)
                        return
                    }
                    retryCount += 1
                    do {
                        try await Task.sleep(
                            for: TranscriptionRetryPolicy.delay(forRetry: retryCount)
                        )
                    } catch {
                        await self?.failed(error)
                        return
                    }
                }
            }
        }
        self.worker = worker
    }

    private func completed(batch: WAVAudioBatch, text: String) {
        guard !isTerminated else { return }
        worker = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let result = continuation.yield(
                FinalizedSpeechSegment(
                    sequenceNumber: batch.sequenceNumber,
                    text: trimmed,
                    startOffset: batch.startOffset,
                    endOffset: batch.endOffset
                )
            )
            switch result {
            case .enqueued:
                previousFinalizedText = trimmed
            case .dropped:
                terminate(throwing: .stage(.speechRecognition, .overloaded))
                return
            case .terminated:
                terminate(throwing: .cancelled)
                return
            @unknown default:
                terminate(throwing: .stage(.speechRecognition, .failed))
                return
            }
        }
        startNextIfNeeded()
    }
    private func failed(_ error: any Error) {
        guard !isTerminated else { return }
        worker = nil
        if error is CancellationError {
            terminate(throwing: .cancelled)
            return
        }
        if let error = error as? OpenAIHTTPError,
           case .unexpectedStatus(let status) = error,
           status == 401 || status == 403 {
            terminate(throwing: .unavailable(.openAIAPIKeyInvalid))
            return
        }
        terminate(throwing: .stage(.speechRecognition, .failed))
    }

    private func terminate(throwing failure: PipelineFailure) {
        guard !isTerminated else { return }
        isTerminated = true
        acceptsInput = false
        pending.removeAll()
        worker?.cancel()
        worker = nil
        continuation.finish(throwing: failure)
    }
}

actor OpenAITranscriptionAdapter: SessionSpeechRecognizer {
    private let configurationProvider: @Sendable () -> OpenAIAPIConfiguration?
    private let transcriptionPromptProvider: @Sendable () -> String?
    private let client: any OpenAIHTTPClient
    private var batchDuration: Duration
    private var configuredTranscriptionPrompt: String?
    private var hasConfiguredTranscriptionPrompt = false
    private var processingTask: Task<Void, Never>?
    private var queue: OpenAITranscriptionQueue?
    private var nextBatchSequenceNumber: UInt64 = 0
    private var nextAudioOffset = Duration.zero

    init(
        configuration: OpenAIAPIConfiguration? = nil,
        configurationProvider: @escaping @Sendable () -> OpenAIAPIConfiguration? = {
            OpenAIAPIConfiguration.stored()
        },
        client: any OpenAIHTTPClient = URLSessionOpenAIHTTPClient(),
        batchDuration: Duration = .seconds(30),
        transcriptionPromptProvider: @escaping @Sendable () -> String? = {
            TranscriptionVocabularyConfiguration.storedPrompt()
        }
    ) {
        self.configurationProvider = { configuration ?? configurationProvider() }
        self.transcriptionPromptProvider = transcriptionPromptProvider
        self.client = client
        self.batchDuration = batchDuration
    }

    func configure(batchDuration: Duration, transcriptionPrompt: String?) async {
        guard batchDuration > .zero, processingTask == nil, queue == nil else { return }
        self.batchDuration = batchDuration
        configuredTranscriptionPrompt = transcriptionPrompt
        hasConfiguredTranscriptionPrompt = true
    }

    func configure(batchDuration: Duration) async {
        await configure(batchDuration: batchDuration, transcriptionPrompt: nil)
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
            continuation.onTermination = { @Sendable [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.cancel() }
            }
        }
        guard let outputContinuation else {
            throw .stage(.speechRecognition, .failed)
        }

        let queue = OpenAITranscriptionQueue(
            configuration: configuration,
            client: client,
            continuation: outputContinuation,
            technicalVocabulary: hasConfiguredTranscriptionPrompt
                ? configuredTranscriptionPrompt
                : transcriptionPromptProvider()
        )
        self.queue = queue
        processingTask = Task { [weak self] in
            await self?.collect(audio: audio, queue: queue)
        }
        return output
    }

    func stop() async {
        await endRecognition(resetSession: true)
    }

    func pause() async {
        await endRecognition(resetSession: false)
    }

    func cancel() async {
        await endRecognition(resetSession: true)
    }

    private func endRecognition(resetSession: Bool) async {
        processingTask?.cancel()
        processingTask = nil
        await queue?.cancel()
        queue = nil
        if resetSession {
            nextBatchSequenceNumber = 0
            nextAudioOffset = .zero
        }
    }

    private func collect(audio: AudioStream, queue: OpenAITranscriptionQueue) async {
        var batch: WAVAudioBatch?
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
                   (current.sampleRate != sampleRate
                    || current.channelCount != chunk.channelCount
                    || current.endOffset - current.startOffset >= batchDuration
                    || !current.canAppend(sampleCount: chunk.samples.count)) {
                    await queue.enqueue(current)
                    batch = nil
                }

                guard WAVEncoder.canEncode(sampleCount: chunk.samples.count) else {
                    throw PipelineFailure.stage(.speechRecognition, .overloaded)
                }

                let startOffset = nextAudioOffset
                nextAudioOffset += chunk.duration
                if let current = batch {
                    current.append(chunk.samples, endingAt: nextAudioOffset)
                } else {
                    batch = WAVAudioBatch(
                        sequenceNumber: nextBatchSequenceNumber,
                        sampleRate: sampleRate,
                        channelCount: chunk.channelCount,
                        samples: chunk.samples,
                        startOffset: startOffset,
                        endOffset: nextAudioOffset
                    )
                    nextBatchSequenceNumber &+= 1
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

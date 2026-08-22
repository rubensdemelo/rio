import Foundation
import Network
import XCTest

final class OpenAIInsightAdapterTests: XCTestCase {
    func testCustomMeetingProfileGuidanceIsIncludedInInsightInstructions() throws {
        let profile = try XCTUnwrap(
            MeetingProfile.custom(
                name: "Incident review",
                guidance: "Prioritize symptoms, failed checks, and diagnostic questions."
            )
        )

        let instructions = OpenAIInsightPrompt.instructions(for: profile)

        XCTAssertTrue(instructions.contains("Incident review"))
        XCTAssertTrue(instructions.contains("Prioritize symptoms, failed checks, and diagnostic questions."))
    }

    func testMissingKeyIsUnavailable() async {
        let generator = OpenAIInsightGenerator(
            configuration: nil,
            configurationProvider: { nil }
        )
        let availability = await generator.availability()

        XCTAssertEqual(
            availability,
            .unavailable(.openAIAPIKeyMissing)
        )

        do {
            try await generator.startSession(localeIdentifier: "en-US")
            XCTFail("A missing API key must prevent listening")
        } catch let failure {
            XCTAssertEqual(failure, .unavailable(.openAIAPIKeyMissing))
        }
    }

    func testRequestUsesResponsesAPIAndKeepsInstructionsSeparateFromMeetingText() async throws {
        let meetingText = "Synthetic meeting phrase: Alex owns migration follow-up."
        let client = RecordingOpenAIHTTPClient(responseData: makeAPIResponseData())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )
        let batch = makeBatch(text: meetingText)

        try await generator.startSession(localeIdentifier: "en-US")
        _ = try await generator.generate(from: batch)

        let requests = await client.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, OpenAIAPIConfiguration.defaultModel)
        XCTAssertEqual(body["instructions"] as? String, OpenAIInsightPrompt.instructions)
        XCTAssertFalse((body["instructions"] as? String ?? "").contains(meetingText))
        XCTAssertTrue((body["input"] as? String ?? "").contains("<NEW_FINALIZED_TEXT>"))
        XCTAssertTrue((body["input"] as? String ?? "").contains(meetingText))

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
    }

    func testLongMeetingRequestDistinguishesNewSpeechAndSuppliesCurrentInsightState() async throws {
        let client = RecordingOpenAIHTTPClient(responseData: makeAPIResponseData())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )
        let earlier = FinalizedSpeechSegment(
            sequenceNumber: 40,
            text: "Checkout latency rose after the release.",
            startOffset: .seconds(1_800),
            endOffset: .seconds(1_830)
        )
        let latest = FinalizedSpeechSegment(
            sequenceNumber: 41,
            text: "Payment latency has not been checked.",
            startOffset: .seconds(1_830),
            endOffset: .seconds(1_860)
        )
        let existing = InsightCard(
            stableKey: "checkout-latency",
            category: .important,
            text: "Checkout latency rose after the release.",
            explicitOwner: nil,
            state: .new
        )
        let batch = MeetingContextBatch(
            segments: [earlier, latest],
            newSegments: [latest],
            currentInsights: [existing]
        )

        try await generator.startSession(localeIdentifier: "en-US")
        _ = try await generator.generate(from: batch)

        let requests = await client.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertTrue(input.contains("<RECENT_CONTEXT>"))
        XCTAssertTrue(input.contains("<NEW_FINALIZED_TEXT>"))
        XCTAssertTrue(input.contains("<CURRENT_INSIGHTS>"))
        XCTAssertTrue(input.contains("checkout-latency"))
        XCTAssertTrue(input.contains(latest.text))
    }

    func testInternalTechnicalProfileUsesTechnicalKnowledgeInstructions() async throws {
        let client = RecordingOpenAIHTTPClient(responseData: makeAPIResponseData())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        await generator.configure(profile: .internalTechnical)
        try await generator.startSession(localeIdentifier: "en-US")
        _ = try await generator.generate(from: makeBatch(text: "The API returns HTTP 503."))

        let requests = await client.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("internal technical"))
        XCTAssertTrue(instructions.contains("technical facts"))
        XCTAssertFalse(instructions.contains("customer-critical"))
    }

    func testFallbackProfileUsesGeneralMeetingInstructions() async throws {
        let client = RecordingOpenAIHTTPClient(responseData: makeAPIResponseData())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        await generator.configure(profile: .fallback)
        try await generator.startSession(localeIdentifier: "en-US")
        _ = try await generator.generate(from: makeBatch(text: "The API returns HTTP 503."))

        let requests = await client.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("general meeting guidance"))
        XCTAssertFalse(instructions.contains("custom meeting profile"))
    }

    func testTranslationPreservesExplicitOwnersOnlyWhenSupportedByMeetingText() async throws {
        let client = RecordingOpenAIHTTPClient(
            responseData: makeAPIResponseData(
                updates: [
                    [
                        "stableKey": "action-1",
                        "operation": "add",
                        "category": "action",
                        "text": "Complete the migration follow-up.",
                        "explicitOwner": "Alex",
                    ],
                    [
                        "stableKey": "decision-1",
                        "operation": "add",
                        "category": "decision",
                        "text": "Use the migration plan.",
                        "explicitOwner": "Invented Owner",
                    ],
                ]
            )
        )
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        let updates = try await generator.generate(
            from: makeBatch(text: "Alex owns the migration follow-up.")
        )

        XCTAssertEqual(updates[0].explicitOwner, "Alex")
        XCTAssertNil(updates[1].explicitOwner)
    }

    func testInvalidKeyBecomesAnActionableUnavailableState() async throws {
        let client = RecordingOpenAIHTTPClient(statusCode: 401, responseData: Data())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "invalid"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("An unauthorized response must fail")
        } catch let failure {
            XCTAssertEqual(failure, .unavailable(.openAIAPIKeyInvalid))
        }
    }

    func testHTTPClientPreservesUnauthorizedResponseWhenTransportAlsoTimesOut() async throws {
        let server = try EarlyUnauthorizedHTTPServer()
        let url = try await server.start()
        defer { server.stop() }
        let client = URLSessionOpenAIHTTPClient(
            session: URLSession(configuration: .ephemeral)
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.25
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(repeating: 0, count: 1_048_576)

        do {
            _ = try await client.data(for: request)
            XCTFail("The unauthorized response must fail")
        } catch let error as OpenAIHTTPError {
            guard case .unexpectedStatus(let statusCode) = error else {
                return XCTFail("Expected the HTTP rejection, received \(error)")
            }
            XCTAssertEqual(statusCode, 401)
        } catch {
            XCTFail("The timeout hid the HTTP rejection: \(error)")
        }
    }

    func testOpenAIFailureDiagnosticContainsOnlySanitizedNonContentMetadata() throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.setValue("Bearer sk-synthetic-secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("synthetic meeting audio".utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: "HTTP/3",
            headerFields: ["x-request-id": "req_synthetic"]
        )!
        let responseData = try JSONSerialization.data(withJSONObject: [
            "error": [
                "type": "invalid_request_error",
                "code": "invalid_api_key",
                "message": "The key sk-synthetic-secret was rejected for synthetic meeting audio.",
            ],
        ])

        let diagnostic = OpenAIRequestDiagnostics.failure(
            request: request,
            response: response,
            responseData: responseData,
            transportError: URLError(.timedOut)
        )

        XCTAssertEqual(diagnostic.endpoint, "audio_transcriptions")
        XCTAssertEqual(diagnostic.statusCode, 401)
        XCTAssertEqual(diagnostic.transport, "url")
        XCTAssertEqual(diagnostic.transportCode, URLError.timedOut.rawValue)
        XCTAssertEqual(diagnostic.requestID, "req_synthetic")
        XCTAssertEqual(diagnostic.apiErrorType, "invalid_request_error")
        XCTAssertEqual(diagnostic.apiErrorCode, "invalid_api_key")
        XCTAssertFalse(String(describing: diagnostic).contains("sk-synthetic-secret"))
        XCTAssertFalse(String(describing: diagnostic).contains("synthetic meeting audio"))
    }

    func testRateLimitBecomesAnActionableInsightFailure() async throws {
        let client = RecordingOpenAIHTTPClient(statusCode: 429, responseData: Data())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("A rate-limited response must fail")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .stage(.insightGeneration, .rateLimited)
            )
        }
    }

    func testRejectedRequestPreservesTheHTTPStatusCategory() async throws {
        let client = RecordingOpenAIHTTPClient(statusCode: 400, responseData: Data())
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("A rejected response must fail")
        } catch let failure {
            XCTAssertEqual(
                failure,
                .stage(.insightGeneration, .requestRejected(statusCode: 400))
            )
        }
    }

    func testMalformedGeneratedOutputIsRejected() async throws {
        let client = RecordingOpenAIHTTPClient(
            responseData: makeAPIResponseData(
                updates: [[
                    "stableKey": " ",
                    "operation": "add",
                    "category": "important",
                    "text": "Useful point",
                    "explicitOwner": "",
                ]]
            )
        )
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("Malformed output must be rejected")
        } catch let failure {
            XCTAssertEqual(failure, .stage(.insightGeneration, .responseInvalid))
        }
    }

    func testIncompleteResponsesResultCanBeRetried() async throws {
        let client = RecordingOpenAIHTTPClient(
            responseData: makeIncompleteAPIResponseData()
        )
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("An incomplete response must be exposed as a retryable failure")
        } catch let failure {
            XCTAssertEqual(failure, .stage(.insightGeneration, .failed))
        }
    }

    func testRefusalResponseCanBeRetried() async throws {
        let client = RecordingOpenAIHTTPClient(
            responseData: makeRefusalAPIResponseData()
        )
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("A refusal response must be exposed as a retryable failure")
        } catch let failure {
            XCTAssertEqual(failure, .stage(.insightGeneration, .failed))
        }
    }

    func testUnknownResponseStatusCanBeRetried() async throws {
        let client = RecordingOpenAIHTTPClient(
            responseData: makeAPIResponseData(status: "cancelled")
        )
        let generator = OpenAIInsightGenerator(
            configuration: OpenAIAPIConfiguration(apiKey: "test-key"),
            client: client
        )

        try await generator.startSession(localeIdentifier: "en-US")
        do {
            _ = try await generator.generate(from: makeBatch(text: "Synthetic meeting text"))
            XCTFail("An unrecognized response status must be exposed as a retryable failure")
        } catch let failure {
            XCTAssertEqual(failure, .stage(.insightGeneration, .failed))
        }
    }

    private func makeBatch(text: String) -> MeetingContextBatch {
        MeetingContextBatch(
            segments: [
                FinalizedSpeechSegment(
                    sequenceNumber: 1,
                    text: text,
                    startOffset: .zero,
                    endOffset: .seconds(1)
                ),
            ]
        )
    }

    private func makeAPIResponseData(
        updates: [[String: String]] = [],
        status: String? = nil
    ) -> Data {
        let structuredOutput = try! JSONSerialization.data(
            withJSONObject: ["updates": updates]
        )
        let outputText = String(decoding: structuredOutput, as: UTF8.self)
        var response: [String: Any] = [
            "output": [[
                "content": [[
                    "type": "output_text",
                    "text": outputText,
                ]],
            ]],
        ]
        if let status {
            response["status"] = status
        }
        return try! JSONSerialization.data(withJSONObject: response)
    }

    private func makeIncompleteAPIResponseData() -> Data {
        try! JSONSerialization.data(
            withJSONObject: [
                "status": "incomplete",
                "incomplete_details": ["reason": "max_output_tokens"],
                "output": [],
            ]
        )
    }

    private func makeRefusalAPIResponseData() -> Data {
        try! JSONSerialization.data(
            withJSONObject: [
                "status": "completed",
                "output": [[
                    "content": [[
                        "type": "refusal",
                        "refusal": "Synthetic refusal",
                    ]],
                ]],
            ]
        )
    }
}

private final class EarlyUnauthorizedHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "rio.tests.unauthorized-http-server")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var startContinuation: CheckedContinuation<URL, any Error>?

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        let activeConnections = lock.withLock {
            let active = connections
            connections.removeAll()
            return active
        }
        activeConnections.forEach { $0.cancel() }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else { return }
            resumeStart(with: .success(
                URL(string: "http://127.0.0.1:\(port.rawValue)/v1/audio/transcriptions")!
            ))
        case .failed(let error):
            resumeStart(with: .failure(error))
        default:
            break
        }
    }

    private func resumeStart(with result: Result<URL, any Error>) {
        let continuation = lock.withLock {
            defer { startContinuation = nil }
            return startContinuation
        }
        continuation?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock {
            connections.append(connection)
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            [weak self, weak connection] _, _, _, _ in
            guard let self, let connection else { return }
            let body = """
            {"error":{"type":"invalid_request_error","code":"invalid_api_key","message":"Synthetic secret-bearing message that diagnostics must ignore."}}
            """
            let response = """
            HTTP/1.1 401 Unauthorized\r
            Content-Type: application/json\r
            Content-Length: \(body.utf8.count + 32)\r
            x-request-id: req_synthetic\r
            Connection: keep-alive\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                _ = self
            })
        }
    }
}

private actor RecordingOpenAIHTTPClient: OpenAIHTTPClient {
    private let statusCode: Int
    private let responseData: Data
    private var recordedRequests: [URLRequest] = []

    init(statusCode: Int = 200, responseData: Data) {
        self.statusCode = statusCode
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

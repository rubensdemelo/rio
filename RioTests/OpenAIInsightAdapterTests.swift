import Foundation
import XCTest

final class OpenAIInsightAdapterTests: XCTestCase {
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
        XCTAssertTrue((body["input"] as? String ?? "").contains("<MEETING_TEXT>"))
        XCTAssertTrue((body["input"] as? String ?? "").contains(meetingText))

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
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

import Foundation
import XCTest

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testFailureDiagnosticsUseOnlyStructuredCodes() {
        XCTAssertEqual(
            RioFailureDiagnostic(.unavailable(.systemAudioPermissionDenied)),
            RioFailureDiagnostic(
                stage: "availability",
                reason: "system_audio_permission_denied",
                statusCode: 0
            )
        )
        XCTAssertEqual(
            RioFailureDiagnostic(
                .stage(.insightGeneration, .requestRejected(statusCode: 429))
            ),
            RioFailureDiagnostic(
                stage: "insight_generation",
                reason: "request_rejected",
                statusCode: 429
            )
        )
        XCTAssertEqual(
            RioFailureDiagnostic(.cancelled),
            RioFailureDiagnostic(
                stage: "session_lifecycle",
                reason: "cancelled",
                statusCode: 0
            )
        )
    }

    func testDiagnosticsViewModelLoadsAndFormatsEntriesWithoutAddingContent() async {
        let first = RioDiagnosticEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            category: "openai",
            level: "error",
            message: "OpenAI request failed endpoint=audio_transcriptions http_status=429"
        )
        let second = RioDiagnosticEntry(
            date: Date(timeIntervalSince1970: 1_700_000_001),
            category: "session",
            level: "error",
            message: "Session failed stage=speech_recognition reason=failed http_status=0"
        )
        let model = RioDiagnosticsViewModel(
            reader: StubRioDiagnosticsReader(entries: [second, first])
        )

        await model.reload()

        XCTAssertEqual(model.entries, [second, first])
        XCTAssertFalse(model.couldNotReadLog)
        XCTAssertTrue(model.copyText.contains("[error] [openai]"))
        XCTAssertTrue(model.copyText.contains("[error] [session]"))
        XCTAssertFalse(model.copyText.contains("transcript text"))
    }

    func testDiagnosticsViewModelReportsReaderFailureWithoutErrorDetails() async {
        let model = RioDiagnosticsViewModel(
            reader: StubRioDiagnosticsReader(shouldFail: true)
        )

        await model.reload()

        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.couldNotReadLog)
        XCTAssertTrue(model.copyText.isEmpty)
    }
}

private struct StubRioDiagnosticsReader: RioDiagnosticsReading {
    let entries: [RioDiagnosticEntry]
    let shouldFail: Bool

    init(
        entries: [RioDiagnosticEntry] = [],
        shouldFail: Bool = false
    ) {
        self.entries = entries
        self.shouldFail = shouldFail
    }

    func recentEntries() async throws -> [RioDiagnosticEntry] {
        if shouldFail {
            throw StubDiagnosticsError.unavailable
        }
        return entries
    }
}

private enum StubDiagnosticsError: Error {
    case unavailable
}

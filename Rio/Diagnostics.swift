import AppKit
import Foundation
import OSLog
import SwiftUI

struct RioDiagnosticEntry: Identifiable, Sendable, Equatable {
    let date: Date
    let category: String
    let level: String
    let message: String

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)|\(category)|\(level)|\(message)"
    }
}

protocol RioDiagnosticsReading: Sendable {
    func recentEntries() async throws -> [RioDiagnosticEntry]
}

struct SystemRioDiagnosticsReader: RioDiagnosticsReading, Sendable {
    static let maximumEntryCount = 200

    func recentEntries() async throws -> [RioDiagnosticEntry] {
        try await Task.detached(priority: .utility) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let predicate = NSPredicate(
                format: "subsystem == %@",
                RioDiagnosticsLogger.subsystem
            )
            let entries = try store.getEntries(
                with: [.reverse],
                matching: predicate
            )

            return entries
                .lazy
                .compactMap { entry -> RioDiagnosticEntry? in
                    guard let logEntry = entry as? OSLogEntryLog else { return nil }
                    return RioDiagnosticEntry(
                        date: logEntry.date,
                        category: logEntry.category,
                        level: logEntry.level.diagnosticName,
                        message: logEntry.composedMessage
                    )
                }
                .prefix(Self.maximumEntryCount)
                .map { $0 }
        }.value
    }
}

@MainActor
protocol SessionFailureRecording {
    func record(_ failure: PipelineFailure)
}

@MainActor
struct UnifiedSessionFailureRecorder: SessionFailureRecording {
    func record(_ failure: PipelineFailure) {
        RioDiagnosticsLogger.logSessionFailure(failure)
    }
}

struct RioFailureDiagnostic: Sendable, Equatable {
    let stage: String
    let reason: String
    let statusCode: Int

    init(stage: String, reason: String, statusCode: Int) {
        self.stage = stage
        self.reason = reason
        self.statusCode = statusCode
    }

    init(_ failure: PipelineFailure) {
        switch failure {
        case .unavailable(let reason):
            stage = "availability"
            self.reason = reason.diagnosticName
            statusCode = 0
        case .stage(let stage, let reason):
            self.stage = stage.diagnosticName
            self.reason = reason.diagnosticName
            if case .requestRejected(let statusCode) = reason {
                self.statusCode = statusCode
            } else {
                statusCode = 0
            }
        case .cancelled:
            stage = "session_lifecycle"
            reason = "cancelled"
            statusCode = 0
        }
    }
}

enum RioDiagnosticsLogger {
    static let subsystem = "com.rio.app"
    private static let sessionLogger = Logger(subsystem: subsystem, category: "session")

    static func logSessionFailure(_ failure: PipelineFailure) {
        let diagnostic = RioFailureDiagnostic(failure)
        sessionLogger.error(
            "Session failed stage=\(diagnostic.stage, privacy: .public) reason=\(diagnostic.reason, privacy: .public) http_status=\(diagnostic.statusCode)"
        )
    }
}

@MainActor
final class RioDiagnosticsViewModel: ObservableObject {
    @Published private(set) var entries: [RioDiagnosticEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var couldNotReadLog = false

    private let reader: any RioDiagnosticsReading

    init(reader: any RioDiagnosticsReading = SystemRioDiagnosticsReader()) {
        self.reader = reader
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await reader.recentEntries()
            couldNotReadLog = false
        } catch {
            entries = []
            couldNotReadLog = true
        }
    }

    var copyText: String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.level)] [\(entry.category)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    func copyAll() {
        guard !entries.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
    }
}

struct RioDiagnosticsView: View {
    @StateObject private var model: RioDiagnosticsViewModel

    init(reader: any RioDiagnosticsReading = SystemRioDiagnosticsReader()) {
        _model = StateObject(
            wrappedValue: RioDiagnosticsViewModel(reader: reader)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics")
                        .font(.title2.weight(.bold))
                    Text("Privacy-safe Rio logs from this app launch.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Console") {
                    DiagnosticsConsoleOpener.open()
                }
                Button("Copy All") {
                    model.copyAll()
                }
                .disabled(model.entries.isEmpty)
                Button("Refresh") {
                    Task { await model.reload() }
                }
                .disabled(model.isLoading)
            }

            Text(
                "Diagnostics never include API keys, audio, transcript text, prompts, or insight text. For entries from an earlier Rio launch, open Console and search for subsystem com.rio.app."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Group {
                if model.isLoading && model.entries.isEmpty {
                    ProgressView("Reading diagnostics…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.couldNotReadLog {
                    ContentUnavailableView(
                        "Diagnostics unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            "Rio could not read its current log. Open Console and search for subsystem com.rio.app."
                        )
                    )
                } else if model.entries.isEmpty {
                    ContentUnavailableView(
                        "No diagnostics",
                        systemImage: "checkmark.circle",
                        description: Text("No Rio diagnostic entries were recorded during this launch.")
                    )
                } else {
                    List(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.date, style: .time)
                                Text(entry.category)
                                Text(entry.level)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(entry.message)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .task {
            await model.reload()
        }
    }
}

private enum DiagnosticsConsoleOpener {
    static func open() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        )
    }
}

private extension OSLogEntryLog.Level {
    var diagnosticName: String {
        switch self {
        case .undefined: "default"
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        @unknown default: "unknown"
        }
    }
}

private extension PipelineStage {
    var diagnosticName: String {
        switch self {
        case .audioCapture: "audio_capture"
        case .speechRecognition: "speech_recognition"
        case .rollingContext: "rolling_context"
        case .insightGeneration: "insight_generation"
        case .insightState: "insight_state"
        case .sessionLifecycle: "session_lifecycle"
        }
    }
}

private extension PipelineFailureReason {
    var diagnosticName: String {
        switch self {
        case .failed: "failed"
        case .interrupted: "interrupted"
        case .overloaded: "overloaded"
        case .invalidState: "invalid_state"
        case .network: "network"
        case .rateLimited: "rate_limited"
        case .serviceUnavailable: "service_unavailable"
        case .requestRejected: "request_rejected"
        case .responseInvalid: "response_invalid"
        }
    }
}

private extension UnavailableReason {
    var diagnosticName: String {
        switch self {
        case .microphonePermissionUndetermined: "microphone_permission_undetermined"
        case .microphonePermissionDenied: "microphone_permission_denied"
        case .audioInputUnavailable: "audio_input_unavailable"
        case .systemAudioPermissionDenied: "system_audio_permission_denied"
        case .systemAudioCaptureFailed: "system_audio_capture_failed"
        case .systemAudioUnavailable: "system_audio_unavailable"
        case .openAIAPIKeyMissing: "openai_api_key_missing"
        case .openAIAPIKeyInvalid: "openai_api_key_invalid"
        }
    }
}

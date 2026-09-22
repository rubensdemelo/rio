import AppKit
import Darwin
import SwiftUI

@MainActor
final class RioAppDelegate: NSObject, NSApplicationDelegate {
    static var terminationPreparation: RioApplicationTerminationCoordinator.Preparation = {
        true
    }

    private lazy var terminationCoordinator = RioApplicationTerminationCoordinator(
        preparation: Self.terminationPreparation
    )
    private var terminationApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(RioLaunchPresentation.activationPolicy)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationApproved else { return .terminateNow }
        terminationCoordinator.request { [weak self, weak sender] shouldTerminate in
            if shouldTerminate {
                self?.terminationApproved = true
            }
            sender?.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }
}

@main
enum RioMain {
    static func main() {
        if CommandLine.arguments.contains(
            SystemAudioCaptureVerificationCommand.launchArgument
        ) {
            let arguments = CommandLine.arguments
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            DispatchQueue.main.async {
                Task.detached {
                    let report = await SystemAudioCaptureVerificationCommand.run(
                        arguments: arguments,
                        capture: CoreAudioSystemAudioCapture()
                    )
                    if let data = SystemAudioCaptureVerificationCommand.encodedJSON(report) {
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write(Data("\n".utf8))
                    }
                    Darwin.exit(report.succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
            application.run()
            Darwin.exit(EXIT_FAILURE)
        }

        RioApp.main()
    }
}

struct RioApp: App {
    @NSApplicationDelegateAdaptor(RioAppDelegate.self) private var appDelegate
    @StateObject private var sessionController: LiveSessionController
    @StateObject private var providerSettings: OpenAIProviderSettings
    @StateObject private var meetingHistory: MeetingHistoryStore
    @StateObject private var panelRouter: RioPanelRouter
    @StateObject private var meetingProfileSettings: MeetingProfileSettings

    init() {
        if CommandLine.arguments.contains(RioKeychainAccessVerifier.launchArgument) {
            let succeeded = RioKeychainAccessVerifier.verify()
            let message = succeeded
                ? RioKeychainAccessVerifier.successMessage
                : RioKeychainAccessVerifier.failureMessage
            FileHandle.standardOutput.write(Data("\(message)\n".utf8))
            Darwin.exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        try? LegacyInsightHistoryFile.remove()
        let meetingHistory = MeetingHistoryStore()
        let meetingProfileSettings = MeetingProfileSettings()
        let apiKeyStore = OpenAIAPIKeyStoreFactory.makeRuntimeStore()
        let sessionController = RioCompositionRoot.makeLiveController(
            meetingHistory: meetingHistory,
            meetingProfileSettings: meetingProfileSettings,
            apiKeyStore: apiKeyStore
        )
        let terminationPreparation = RioTerminationPreparation(
            session: sessionController,
            history: meetingHistory
        )
        RioAppDelegate.terminationPreparation = { [terminationPreparation] in
            await terminationPreparation.prepare()
        }
        _sessionController = StateObject(wrappedValue: sessionController)
        let providerSettings = OpenAIProviderSettings(keyStore: apiKeyStore)
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _meetingHistory = StateObject(wrappedValue: meetingHistory)
        let panelRouter = RioPanelRouter()
        _panelRouter = StateObject(wrappedValue: panelRouter)
        _meetingProfileSettings = StateObject(wrappedValue: meetingProfileSettings)

        // Start independently of the menu's presentation lifecycle so an open,
        // idle menu-bar app continues enforcing the at-rest retention window.
        Task { @MainActor [weak meetingHistory] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let meetingHistory else { return }
                try? meetingHistory.pruneExpired()
            }
        }

        Task { @MainActor in
            await sessionController.checkReadiness()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RioMenuBarContent(
                controller: sessionController,
                providerSettings: providerSettings,
                panelRouter: panelRouter
            )
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            ) { _ in
                meetingHistory.load()
            }
        } label: {
            Image("RioMenuBarIcon")
                .accessibilityLabel("Rio")
        }
        .menuBarExtraStyle(.menu)

        Window("Rio", id: "main") {
            RioView(controller: sessionController)
                .environmentObject(providerSettings)
                .environmentObject(panelRouter)
                .environmentObject(meetingProfileSettings)
        }
        .defaultSize(width: 640, height: 240)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

        Window("Recent Meetings", id: "recent-meetings") {
            RecentMeetingsView()
                .environmentObject(meetingHistory)
        }
        .defaultSize(width: 760, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

        Window("Meeting Profiles", id: "profiles") {
            MeetingProfileSettingsView()
                .environmentObject(meetingProfileSettings)
        }
        .defaultSize(width: 760, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

        Window("Diagnostics", id: "diagnostics") {
            RioDiagnosticsView()
        }
        .defaultSize(width: 760, height: 520)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

    }
}

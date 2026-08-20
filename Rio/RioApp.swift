import AppKit
import SwiftUI

@main
struct RioApp: App {
    @StateObject private var sessionController: LiveSessionController
    @StateObject private var providerSettings: OpenAIProviderSettings
    @StateObject private var meetingHistory: MeetingHistoryStore
    @StateObject private var panelRouter: RioPanelRouter
    @StateObject private var meetingProfileSettings: MeetingProfileSettings

    init() {
        let meetingHistory = MeetingHistoryStore()
        let meetingProfileSettings = MeetingProfileSettings()
        let sessionController = RioCompositionRoot.makeLiveController(
            meetingHistory: meetingHistory,
            meetingProfileSettings: meetingProfileSettings
        )
        _sessionController = StateObject(wrappedValue: sessionController)
        _providerSettings = StateObject(wrappedValue: OpenAIProviderSettings())
        _meetingHistory = StateObject(wrappedValue: meetingHistory)
        _panelRouter = StateObject(wrappedValue: RioPanelRouter())
        _meetingProfileSettings = StateObject(wrappedValue: meetingProfileSettings)

        Task { @MainActor in
            await sessionController.checkReadiness()
        }
    }

    var body: some Scene {
        Window("Rio", id: "main") {
            RioView(controller: sessionController)
                .environmentObject(providerSettings)
                .environmentObject(panelRouter)
                .environmentObject(meetingProfileSettings)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 560, height: 96)
        .windowResizability(.contentSize)

        Window("Recent Meetings", id: "recent-meetings") {
            RecentMeetingsView()
                .environmentObject(meetingHistory)
                .background(FloatingWindowBehavior())
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentSize)

        MenuBarExtra("Rio", image: "RioMenuBarIcon") {
            RioMenuBarMenu(controller: sessionController)
                .environmentObject(panelRouter)
                .environmentObject(providerSettings)
                .environmentObject(meetingProfileSettings)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Makes the recent-meetings companion behave like a floating meeting window.
private struct FloatingWindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenAuxiliary)
    }
}

private struct RioMenuBarMenu<Controller: SessionShellControlling>: View {
    @ObservedObject private var controller: Controller
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var panelRouter: RioPanelRouter
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings
    @EnvironmentObject private var meetingProfileSettings: MeetingProfileSettings

    init(controller: Controller) {
        self.controller = controller
    }

    var body: some View {
        Button {
            Task { await controller.performPrimaryAction() }
        } label: {
            Label(
                controller.primaryActionTitle,
                systemImage: controller.status == .listening || controller.status == .processing
                    ? "stop.fill"
                    : "record.circle"
            )
        }
        .disabled(
            controller.isPerformingPrimaryAction
                || controller.status == .checkingAvailability
                || (isStartAction && (
                    !providerSettings.isConfigured
                        || !controller.isReadyToStartListening
                ))
        )

        Picker("Meeting profile", selection: $meetingProfileSettings.selection) {
            ForEach(meetingProfileSettings.profiles) { profile in
                Text(profile.title).tag(profile)
            }
        }
        .disabled(!isStartAction)

        Button("Configure Meeting Profiles…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            panelRouter.showProfiles()
        }

        Divider()

        Button("Recent Meetings") {
            openWindow(id: "recent-meetings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Provider & API Key") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            panelRouter.showProvider()
        }

        Divider()

        Button("Open Rio") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Rio") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var isStartAction: Bool {
        switch controller.status {
        case .stopped, .interrupted, .unavailable:
            true
        case .checkingAvailability, .listening, .processing, .paused:
            false
        }
    }
}

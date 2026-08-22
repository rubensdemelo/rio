import AppKit
import SwiftUI

final class RioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Rio" })?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct RioApp: App {
    @NSApplicationDelegateAdaptor(RioAppDelegate.self) private var appDelegate
    @StateObject private var sessionController: LiveSessionController
    @StateObject private var providerSettings: OpenAIProviderSettings
    @StateObject private var meetingHistory: MeetingHistoryStore
    @StateObject private var panelRouter: RioPanelRouter
    @StateObject private var meetingProfileSettings: MeetingProfileSettings
    @StateObject private var statusItemController: RioStatusItemController

    init() {
        let meetingHistory = MeetingHistoryStore()
        let meetingProfileSettings = MeetingProfileSettings()
        let sessionController = RioCompositionRoot.makeLiveController(
            meetingHistory: meetingHistory,
            meetingProfileSettings: meetingProfileSettings
        )
        _sessionController = StateObject(wrappedValue: sessionController)
        let providerSettings = OpenAIProviderSettings()
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _meetingHistory = StateObject(wrappedValue: meetingHistory)
        let panelRouter = RioPanelRouter()
        _panelRouter = StateObject(wrappedValue: panelRouter)
        _meetingProfileSettings = StateObject(wrappedValue: meetingProfileSettings)
        _statusItemController = StateObject(
            wrappedValue: RioStatusItemController(
                controller: sessionController,
                providerSettings: providerSettings,
                meetingProfileSettings: meetingProfileSettings,
                panelRouter: panelRouter
            )
        )

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
        .defaultSize(width: 640, height: 240)
        .windowResizability(.contentMinSize)

        Window("Recent Meetings", id: "recent-meetings") {
            RecentMeetingsView()
                .environmentObject(meetingHistory)
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)

        Window("Meeting Profiles", id: "profiles") {
            MeetingProfileSettingsView()
                .environmentObject(meetingProfileSettings)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)

    }
}

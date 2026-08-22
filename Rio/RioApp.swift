import AppKit
import SwiftUI

final class RioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(RioLaunchPresentation.activationPolicy)
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

    init() {
        let meetingHistory = MeetingHistoryStore()
        let meetingProfileSettings = MeetingProfileSettings()
        let apiKeyStore = OpenAIAPIKeyStoreFactory.makeRuntimeStore()
        let sessionController = RioCompositionRoot.makeLiveController(
            meetingHistory: meetingHistory,
            meetingProfileSettings: meetingProfileSettings,
            apiKeyStore: apiKeyStore
        )
        _sessionController = StateObject(wrappedValue: sessionController)
        let providerSettings = OpenAIProviderSettings(keyStore: apiKeyStore)
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _meetingHistory = StateObject(wrappedValue: meetingHistory)
        let panelRouter = RioPanelRouter()
        _panelRouter = StateObject(wrappedValue: panelRouter)
        _meetingProfileSettings = StateObject(wrappedValue: meetingProfileSettings)

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

    }
}

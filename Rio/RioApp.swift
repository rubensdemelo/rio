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
        .defaultSize(width: 640, height: 480)
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

@MainActor
final class RioStatusItemController: NSObject, ObservableObject, NSMenuDelegate {
    private let controller: LiveSessionController
    private let providerSettings: OpenAIProviderSettings
    private let meetingProfileSettings: MeetingProfileSettings
    private let panelRouter: RioPanelRouter
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private lazy var startItem = NSMenuItem(
        title: "Start Listening",
        action: #selector(startListening),
        keyEquivalent: ""
    )

    init(
        controller: LiveSessionController,
        providerSettings: OpenAIProviderSettings,
        meetingProfileSettings: MeetingProfileSettings,
        panelRouter: RioPanelRouter
    ) {
        self.controller = controller
        self.providerSettings = providerSettings
        self.meetingProfileSettings = meetingProfileSettings
        self.panelRouter = panelRouter
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let rioImage = NSImage(named: "RioMenuBarIcon") ?? NSApp.applicationIconImage {
            rioImage.isTemplate = true
            rioImage.accessibilityDescription = "Rio"
            statusItem.button?.image = rioImage
        }
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Rio"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        menu.delegate = self
        menu.autoenablesItems = false
        updateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    @objc private func statusItemClicked() {
        updateMenu()
        guard let button = statusItem.button else {
            return
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
            in: button
        )
    }

    private func updateMenu() {
        menu.removeAllItems()

        let openItem = NSMenuItem(
            title: "Open Rio",
            action: #selector(openRio),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        startItem.title = controller.primaryActionTitle
        startItem.image = NSImage(
            systemSymbolName: controller.status == .listening || controller.status == .processing
                ? "stop.fill"
                : "record.circle",
            accessibilityDescription: nil
        )
        startItem.target = self
        startItem.isEnabled = !controller.isPerformingPrimaryAction
            && controller.status != .checkingAvailability
            && (!isStartAction || (providerSettings.isConfigured && controller.isReadyToStartListening))
        menu.addItem(startItem)

        let profileItem = NSMenuItem(
            title: meetingProfileSettings.profiles.isEmpty
                ? "Meeting Profile: General meeting guidance"
                : "Meeting Profile: \(meetingProfileSettings.selection.title)",
            action: nil,
            keyEquivalent: ""
        )
        profileItem.isEnabled = false
        menu.addItem(profileItem)

        let manageProfilesItem = NSMenuItem(
            title: "Manage Profiles…",
            action: #selector(manageProfiles),
            keyEquivalent: ""
        )
        manageProfilesItem.target = self
        menu.addItem(manageProfilesItem)

        let recentItem = NSMenuItem(
            title: "Recent Meetings",
            action: #selector(openRecentMeetings),
            keyEquivalent: ""
        )
        recentItem.target = self
        menu.addItem(recentItem)

        let providerItem = NSMenuItem(
            title: "Provider & API Key…",
            action: #selector(openProviderSettings),
            keyEquivalent: ""
        )
        providerItem.target = self
        menu.addItem(providerItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Rio", action: #selector(quitRio), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func startListening() {
        Task { @MainActor in
            await controller.performPrimaryAction()
            updateMenu()
        }
    }

    @objc private func openRio() {
        activateMainWindow()
    }

    @objc private func manageProfiles() {
        NotificationCenter.default.post(name: .rioOpenProfiles, object: nil)
        activateMainWindow()
    }

    @objc private func openRecentMeetings() {
        NotificationCenter.default.post(name: .rioOpenRecentMeetings, object: nil)
        activateMainWindow()
    }

    @objc private func openProviderSettings() {
        activateMainWindow()
        panelRouter.showProvider()
    }

    @objc private func quitRio() {
        NSApplication.shared.terminate(nil)
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.title == "Rio" }) else {
            return
        }
        window.makeKeyAndOrderFront(nil)
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

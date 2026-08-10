import AppKit
import SwiftUI

@main
struct RioApp: App {
    @StateObject private var sessionController: LiveSessionController
    @StateObject private var providerSettings: OpenAIProviderSettings
    @StateObject private var insightHistory: InsightHistoryStore
    @StateObject private var panelRouter: RioPanelRouter
    @StateObject private var listeningCadenceSettings: ListeningCadenceSettings

    init() {
        let insightHistory = InsightHistoryStore()
        let listeningCadenceSettings = ListeningCadenceSettings()
        _sessionController = StateObject(
            wrappedValue: RioCompositionRoot.makeLiveController(
                insightHistory: insightHistory,
                listeningCadenceSettings: listeningCadenceSettings
            )
        )
        _providerSettings = StateObject(wrappedValue: OpenAIProviderSettings())
        _insightHistory = StateObject(wrappedValue: insightHistory)
        _panelRouter = StateObject(wrappedValue: RioPanelRouter())
        _listeningCadenceSettings = StateObject(wrappedValue: listeningCadenceSettings)
    }

    var body: some Scene {
        Window("Rio", id: "main") {
            RioView(controller: sessionController)
                .environmentObject(providerSettings)
                .environmentObject(insightHistory)
                .environmentObject(panelRouter)
                .environmentObject(listeningCadenceSettings)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 560, height: 96)
        .windowResizability(.contentSize)

        MenuBarExtra("Rio", image: "RioMenuBarIcon") {
            RioMenuBarMenu(controller: sessionController)
                .environmentObject(panelRouter)
                .environmentObject(providerSettings)
                .environmentObject(listeningCadenceSettings)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct RioMenuBarMenu<Controller: SessionShellControlling>: View {
    @ObservedObject private var controller: Controller
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var panelRouter: RioPanelRouter
    @EnvironmentObject private var providerSettings: OpenAIProviderSettings

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
                || (isStartAction && !providerSettings.isConfigured)
        )

        Divider()

        Button("Recent Insights") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            panelRouter.showRecentInsights()
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

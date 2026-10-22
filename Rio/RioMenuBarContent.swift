import AppKit
import SwiftUI

enum RioLaunchPresentation {
    static let activationPolicy: NSApplication.ActivationPolicy = .regular
}

enum RioWindow: String {
    case main
    case diagnostics
    case profiles
    case recentMeetings = "recent-meetings"
}

@MainActor
struct RioMenuWindowRouter {
    let openWindow: (String) -> Void
    let activate: () -> Void

    func open(_ window: RioWindow) {
        openWindow(window.rawValue)
        activate()
    }
}

@MainActor
@Observable
final class RioPanelRouter {
    enum Panel: String, Identifiable {
        case provider

        var id: String { rawValue }
    }

    var presentedPanel: Panel?

    func showProvider() {
        presentedPanel = .provider
    }

}

enum SystemSettingsOpener {
    static let microphoneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!

    static let systemAudioRecordingURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    static func openMicrophone() {
        guard !NSWorkspace.shared.open(microphoneURL) else {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }

    static func openSystemAudioRecording() {
        guard !NSWorkspace.shared.open(systemAudioRecordingURL) else {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}

struct RioMenuBarContent<Controller: SessionShellControlling>: View {
    private let controller: Controller
    private let providerSettings: OpenAIProviderSettings
    private let panelRouter: RioPanelRouter
    @Environment(\.openWindow) private var openWindow

    init(
        controller: Controller,
        providerSettings: OpenAIProviderSettings,
        panelRouter: RioPanelRouter
    ) {
        self.controller = controller
        self.providerSettings = providerSettings
        self.panelRouter = panelRouter
    }

    var body: some View {
        Button("Open Rio") {
            windowRouter.open(.main)
        }

        Button {
            Task { await controller.performPrimaryAction() }
        } label: {
            Label(controller.primaryActionTitle, systemImage: primaryActionSystemImage)
        }
        .disabled(!primaryActionIsEnabled)

        if !providerSettings.isConfigured {
            Text("Add an OpenAI API key to start listening")
        } else if isStartAction && !controller.isReadyToStartListening {
            Text("Open Rio to finish listening setup")
        }

        Button("Manage Profiles…") {
            windowRouter.open(.profiles)
        }

        Button("Recent Meetings") {
            windowRouter.open(.recentMeetings)
        }

        Button("Provider & API Key…") {
            panelRouter.showProvider()
            windowRouter.open(.main)
        }

        Button("Diagnostics…") {
            windowRouter.open(.diagnostics)
        }

        Divider()

        Button("Quit Rio") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var windowRouter: RioMenuWindowRouter {
        RioMenuWindowRouter(
            openWindow: { openWindow(id: $0) },
            activate: { NSApp.activate() }
        )
    }

    private var primaryActionIsEnabled: Bool {
        !controller.isPerformingPrimaryAction
            && controller.status != .checkingAvailability
            && (!isStartAction || (providerSettings.isConfigured && controller.isReadyToStartListening))
    }

    private var primaryActionSystemImage: String {
        isStartAction ? "record.circle" : "stop.fill"
    }

    private var isStartAction: Bool {
        controller.isStartAction
    }
}

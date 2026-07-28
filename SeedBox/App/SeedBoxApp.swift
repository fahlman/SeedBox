import AppKit
import SwiftUI

@main
struct SeedBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(AppStrings.App.name, id: "mod-manager") {
            ModManagerWindow()
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .defaultLaunchBehavior(.presented)
        .commandsRemoved()
        .commands {
            SeedBoxCommands()
        }

        Window(AppStrings.Help.windowTitle, id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

        Settings {
            SettingsSceneView()
        }
    }
}

/// Shared constants for the optional menu bar companion.
enum MenuBarCompanion {
    static let enabledDefaultsKey = "seedbox.menuBarCompanionEnabled"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashDiagnosticsCollector.shared.start()
        menuBarController.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

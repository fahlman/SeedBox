import AppKit
import SwiftUI

@main
struct SeedBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var menuBarCompanion = MenuBarCompanionState()

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

        MenuBarExtra(
            AppStrings.App.name,
            systemImage: "puzzlepiece.extension.fill",
            isInserted: $menuBarCompanion.isEnabled
        ) {
            MenuBarContentView(viewModel: .shared)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsSceneView(menuBarCompanion: menuBarCompanion)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashDiagnosticsCollector.shared.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

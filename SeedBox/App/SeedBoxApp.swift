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
        .defaultLaunchBehavior(.presented)
        .commandsRemoved()
        .commands {
            SeedBoxCommands()
        }

        Settings {
            SettingsSceneView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserNotificationModFolderChangeNotifier.shared.requestAuthorization()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

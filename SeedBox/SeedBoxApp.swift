import AppKit
import SwiftUI

@main
struct SeedBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Seed Box", id: SeedBoxSceneID.modManagerWindow) {
            ModManagerWindow()
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsSceneView()
        }

        .commands {
            SeedBoxCommands()
        }
    }
}

enum SeedBoxSceneID {
    static let modManagerWindow = "mod-manager"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserNotificationModFolderChangeNotifier.shared.requestAuthorization()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

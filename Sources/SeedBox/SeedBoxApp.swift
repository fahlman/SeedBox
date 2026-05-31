import AppKit
import SwiftUI

@main
struct SeedBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = LauncherViewModel()

    var body: some Scene {
        WindowGroup {
            LauncherView(viewModel: viewModel)
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView(viewModel: viewModel)
        }

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Status") {
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        }
    }
}

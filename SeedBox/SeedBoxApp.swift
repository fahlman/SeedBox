import AppKit
import SwiftUI

@main
struct SeedBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = ModManagerViewModel()

    var body: some Scene {
        WindowGroup {
            ModManagerView(viewModel: viewModel)
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView(viewModel: viewModel)
        }

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Status") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

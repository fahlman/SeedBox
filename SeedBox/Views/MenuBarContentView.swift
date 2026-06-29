import AppKit
import SwiftUI

/// Contents of the optional menu bar companion: a concise status summary and
/// quick actions that route into the main app. It reads the same shared state
/// as the main window and duplicates no business logic.
struct MenuBarContentView: View {
    var viewModel: ModManagerViewModel
    @Environment(\.openWindow) private var openWindow

    @MainActor
    private var status: MenuBarStatus {
        MenuBarStatus.make(from: viewModel.state)
    }

    var body: some View {
        statusSection

        Divider()

        Button(AppStrings.MenuBar.openSeedBox) {
            openMainWindow()
        }

        Divider()

        Button(AppStrings.MenuBar.openProblems) { open(.problems) }
        Button(AppStrings.MenuBar.openWarnings) { open(.warnings) }
        Button(AppStrings.MenuBar.openErrors) { open(.errors) }
        Button(AppStrings.MenuBar.openRestoreHistory) { open(.restoreHistory) }

        if status.checksForUpdates {
            Divider()
            Button(AppStrings.MenuBar.checkForUpdates) {
                Task { await viewModel.checkForModUpdates() }
            }
        }
    }

    @MainActor @ViewBuilder
    private var statusSection: some View {
        let status = self.status
        if status.hasFolderAccess {
            if let name = status.selectedSetName {
                Text(AppStrings.MenuBar.currentSet(name))
            }
            if status.hasErrors {
                Text(AppStrings.MenuBar.errors(status.errorsCount))
            }
            if status.hasWarnings {
                Text(AppStrings.MenuBar.warnings(status.warningsCount))
            }
            if status.checksForUpdates, status.hasUpdates {
                Text(AppStrings.MenuBar.updates(status.updatesCount))
            }
            if status.hasLastSessionIssues {
                Text(AppStrings.MenuBar.lastSessionProblems)
            }
        } else {
            Text(AppStrings.MenuBar.noFolder)
        }
    }

    @MainActor
    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "mod-manager")
    }

    @MainActor
    private func open(_ route: SeedBoxRoute) {
        openMainWindow()
        SeedBoxShortcutRouter.shared.request(route: route)
    }
}

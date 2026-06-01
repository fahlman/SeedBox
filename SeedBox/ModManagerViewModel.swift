import AppKit
import Foundation

@MainActor
final class ModManagerViewModel: ObservableObject {
    @Published var macOSDirectoryPath: String {
        didSet {
            persistAndRefresh()
        }
    }

    @Published private(set) var status: InstallationStatus
    @Published private(set) var mods: [ModInfo]
    @Published private(set) var activityMessage: String
    @Published private(set) var hasSavedFolderAccess: Bool

    private let defaults: UserDefaults
    private let folderAccess: SecurityScopedFolderAccess
    private var lastFolderAccessError: String?

    private enum Keys {
        static let macOSDirectoryPath = "macOSDirectoryPath"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderAccess = SecurityScopedFolderAccess(defaults: defaults)

        let detectedDirectory = StardewInstallLocator.locateInstalledMacOSDirectory()
        let savedDirectoryPath = defaults.string(forKey: Keys.macOSDirectoryPath)
        let initialDirectoryPath = savedDirectoryPath ?? detectedDirectory.path

        macOSDirectoryPath = initialDirectoryPath
        mods = []
        activityMessage = ""
        hasSavedFolderAccess = folderAccess.hasBookmark

        status = StardewInstall(
            macOSDirectory: URL(fileURLWithPath: initialDirectoryPath, isDirectory: true)
        )
        .status()

        refresh()
    }

    var install: StardewInstall {
        StardewInstall(
            macOSDirectory: URL(fileURLWithPath: macOSDirectoryPath, isDirectory: true)
        )
    }

    var modFolderName: String {
        StardewInstall.modFolderName
    }

    func refresh() {
        status = withFolderAccess {
            install.status()
        } ?? install.status()
        reloadMods()
    }

    func chooseInstallFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Stardew Valley"
        panel.message = "Select the Stardew Valley folder, app bundle, or Contents/MacOS folder."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true

        let currentURL = URL(fileURLWithPath: macOSDirectoryPath, isDirectory: true)
        panel.directoryURL = currentURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            try folderAccess.saveBookmark(for: selectedURL)
            hasSavedFolderAccess = folderAccess.hasBookmark
            record("Saved folder access for \(selectedURL.path).")
        } catch {
            record("Could not save folder access: \(error.localizedDescription)")
        }

        let resolvedURL = StardewInstallLocator.resolveMacOSDirectory(from: selectedURL)
        macOSDirectoryPath = resolvedURL.path
        record("Selected \(resolvedURL.path).")
    }

    func revealInstallFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([install.macOSDirectory])
    }

    func revealMod(_ mod: ModInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([mod.url])
    }

    func createModFolder() {
        do {
            try folderAccess.withAccess {
                try install.createModDirectory()
            }
            record("Created \(install.modDirectoryURL.path).")
            refresh()
        } catch {
            record("Could not create mod folder: \(error.localizedDescription)")
        }
    }

    func addMods() {
        let panel = NSOpenPanel()
        panel.title = "Add Mods"
        panel.message = "Choose one or more unzipped mod folders."
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else {
            return
        }

        do {
            let installedURLs = try folderAccess.withAccess {
                try ModLibrary.installMods(
                    from: panel.urls,
                    into: install
                )
            }
            record("Added \(installedURLs.count) mod folder\(installedURLs.count == 1 ? "" : "s").")
            refresh()
        } catch {
            record("Could not add mods: \(error.localizedDescription)")
        }
    }

    func setMod(_ mod: ModInfo, enabled: Bool) {
        do {
            _ = try folderAccess.withAccess {
                try ModLibrary.setEnabled(mod, enabled: enabled)
            }
            record("\(enabled ? "Enabled" : "Disabled") \(mod.displayName).")
            refresh()
        } catch {
            record("Could not update \(mod.displayName): \(error.localizedDescription)")
        }
    }

    func deleteMod(_ mod: ModInfo) {
        let alert = NSAlert()
        alert.messageText = "Delete \(mod.displayName)?"
        alert.informativeText = "This moves the mod folder to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try folderAccess.withAccess {
                try ModLibrary.trash(mod)
            }
            record("Moved \(mod.displayName) to the Trash.")
            refresh()
        } catch {
            record("Could not delete \(mod.displayName): \(error.localizedDescription)")
        }
    }

    private func persistAndRefresh() {
        defaults.set(macOSDirectoryPath, forKey: Keys.macOSDirectoryPath)
        refresh()
    }

    private func reloadMods() {
        guard status.modDirectoryExists else {
            mods = []
            return
        }

        do {
            mods = try folderAccess.withAccess {
                try ModLibrary.scan(install: install)
            }
        } catch {
            mods = []
            record("Could not read mods: \(error.localizedDescription)")
        }
    }

    private func withFolderAccess<T>(_ operation: () throws -> T) -> T? {
        do {
            let result = try folderAccess.withAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch {
            let message = error.localizedDescription
            if lastFolderAccessError != message {
                record("Could not restore saved folder access: \(message)")
                lastFolderAccessError = message
            }
            return nil
        }
    }

    private func record(_ message: String) {
        activityMessage = message
    }
}

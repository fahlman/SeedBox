import AppKit
import Foundation
import SeedBoxCore

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var macOSDirectoryPath: String {
        didSet {
            persistAndRefresh()
        }
    }

    @Published private(set) var status: InstallationStatus
    @Published private(set) var mods: [ModInfo]
    @Published private(set) var output: String
    @Published private(set) var isRunning: Bool
    @Published private(set) var hasSavedFolderAccess: Bool

    private let defaults: UserDefaults
    private let folderAccess: SecurityScopedFolderAccess
    private var process: Process?
    private var outputPipe: Pipe?
    private var activeFolderAccess: SecurityScopedAccessToken?
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
        output = ""
        isRunning = false
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

    var launchButtonTitle: String {
        isRunning ? "Running" : "Launch"
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
            appendOutput("Saved folder access for \(selectedURL.path)\n")
        } catch {
            appendOutput("Could not save folder access: \(error.localizedDescription)\n")
        }

        let resolvedURL = StardewInstallLocator.resolveMacOSDirectory(from: selectedURL)
        macOSDirectoryPath = resolvedURL.path
        appendOutput("Selected \(resolvedURL.path)\n")
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
            appendOutput("Created \(install.modDirectoryURL.path)\n")
            refresh()
        } catch {
            appendOutput("Could not create mod folder: \(error.localizedDescription)\n")
        }
    }

    func linkVanillaMods() {
        do {
            let result = try folderAccess.withAccess {
                try ModFolderSeeder.linkVanillaMods(into: install)
            }
            appendOutput("Linked vanilla mods: \(result.summary)\n")
            refresh()
        } catch {
            appendOutput("Could not link vanilla mods: \(error.localizedDescription)\n")
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
            appendOutput("Added \(installedURLs.count) mod folder\(installedURLs.count == 1 ? "" : "s").\n")
            refresh()
        } catch {
            appendOutput("Could not add mods: \(error.localizedDescription)\n")
        }
    }

    func setMod(_ mod: ModInfo, enabled: Bool) {
        do {
            _ = try folderAccess.withAccess {
                try ModLibrary.setEnabled(mod, enabled: enabled)
            }
            appendOutput("\(enabled ? "Enabled" : "Disabled") \(mod.displayName).\n")
            refresh()
        } catch {
            appendOutput("Could not update \(mod.displayName): \(error.localizedDescription)\n")
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
            appendOutput("Moved \(mod.displayName) to the Trash.\n")
            refresh()
        } catch {
            appendOutput("Could not delete \(mod.displayName): \(error.localizedDescription)\n")
        }
    }

    func launch() {
        guard !isRunning else {
            return
        }

        do {
            activeFolderAccess = try folderAccess.beginAccess()

            let request = try SMAPILauncher.request(for: install)
            let launchedProcess = request.makeProcess()
            let pipe = Pipe()

            launchedProcess.standardOutput = pipe
            launchedProcess.standardError = pipe

            outputPipe = pipe
            process = launchedProcess
            isRunning = true

            appendOutput("$ \(request.commandLinePreview)\n")

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }

                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor [weak self] in
                    self?.appendOutput(text)
                }
            }

            launchedProcess.terminationHandler = { [weak self] process in
                Task { @MainActor [weak self] in
                    self?.finishRunning(exitCode: process.terminationStatus)
                }
            }

            try launchedProcess.run()
        } catch {
            cleanupProcess()
            appendOutput("Launch failed: \(error.localizedDescription)\n")
        }
    }

    func stop() {
        guard let process, process.isRunning else {
            return
        }

        appendOutput("Stopping SMAPI...\n")
        process.terminate()
    }

    private func finishRunning(exitCode: Int32) {
        appendOutput("\nSMAPI exited with code \(exitCode).\n")
        cleanupProcess()
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        activeFolderAccess?.stop()
        activeFolderAccess = nil
        isRunning = false
        refresh()
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
            appendOutput("Could not read mods: \(error.localizedDescription)\n")
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
                appendOutput("Could not restore saved folder access: \(message)\n")
                lastFolderAccessError = message
            }
            return nil
        }
    }

    private func appendOutput(_ text: String) {
        output += text

        let maximumLength = 80_000
        if output.count > maximumLength {
            output.removeFirst(output.count - maximumLength)
        }
    }
}

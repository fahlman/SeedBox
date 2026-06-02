import AppKit
import Foundation

@MainActor
final class ModManagerViewModel: ObservableObject {
    @Published private(set) var state: ModManagerState

    private let folderAccess: SecurityScopedFolderAccess
    private let modSetDirectory: URL
    private let preferences: ModManagerPreferences
    private let service: ModManagerService
    private var lastFolderAccessError: String?

    init(
        defaults: UserDefaults = .standard,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory()
    ) {
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        let preferences = ModManagerPreferences(defaults: defaults)
        self.folderAccess = folderAccess
        self.modSetDirectory = modSetDirectory
        self.preferences = preferences
        service = ModManagerService(
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory
        )
        state = Self.initialState(
            preferences: preferences,
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory
        )
    }

    var install: StardewInstall {
        StardewInstall(
            modsDirectory: URL(fileURLWithPath: state.modsDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )
    }

    var modFolderName: String {
        StardewInstall.modFolderName
    }

    var mods: [ModInfo] {
        state.mods
    }

    var selectedModSetID: String {
        state.selectedModSetID
    }

    func refresh() async {
        state = await service.refreshedState(from: state)
        persistPreferences()
    }

    func chooseModsFolder(_ selectedURL: URL) async {
        state = await service.chooseModsFolder(selectedURL, from: state)
        persistPreferences()
    }

    func recordModsFolderSelectionError(_ error: Error) {
        record("Could not choose Mods folder: \(error.localizedDescription)")
    }

    func revealModsFolder() {
        guard guardCanRevealMods() else {
            return
        }

        do {
            try performWithFolderAccess {
                NSWorkspace.shared.activateFileViewerSelecting([install.modDirectoryURL])
            }
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not reveal Mods folder: \(error.localizedDescription)")
        }
    }

    func revealMod(_ mod: ModInfo) {
        guard guardCanRevealMods() else {
            return
        }

        do {
            try performWithFolderAccess {
                NSWorkspace.shared.activateFileViewerSelecting([mod.url])
            }
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not reveal \(mod.displayName): \(error.localizedDescription)")
        }
    }

    func createModFolder() async {
        state = await service.createModFolder(from: state)
        persistPreferences()
    }

    func addMods(from selectedURLs: [URL]) async {
        state = await service.addMods(from: selectedURLs, in: state)
        persistPreferences()
    }

    func recordAddModsSelectionError(_ error: Error) {
        record("Could not choose mods: \(error.localizedDescription)")
    }

    func setMod(_ mod: ModInfo, enabled: Bool) async {
        state = await service.setMod(mod, enabled: enabled, in: state)
        persistPreferences()
    }

    func deleteMod(_ mod: ModInfo) async {
        state = await service.deleteMod(mod, in: state)
        persistPreferences()
    }

    func createModSet(named name: String, from sourceSet: ModSet? = nil) async {
        state = await service.createModSet(named: name, from: sourceSet, in: state)
        persistPreferences()
    }

    func duplicateSelectedModSet(named name: String) async {
        state = await service.duplicateSelectedModSet(named: name, in: state)
        persistPreferences()
    }

    func renameSelectedModSet(to requestedName: String) async {
        state = await service.renameSelectedModSet(to: requestedName, in: state)
        persistPreferences()
    }

    func selectModSet(id: String) async {
        state = await service.selectModSet(id: id, in: state)
        persistPreferences()
    }

    func deleteModSet(_ set: ModSet) async {
        state = await service.deleteModSet(set, in: state)
        persistPreferences()
    }

    private func guardCanRevealMods() -> Bool {
        switch state.readiness {
        case .needsFolderAccess:
            record("Choose the Mods folder before managing mods.")
            return false
        case .missingModsFolder:
            record("The Mods folder is missing. Choose it again from Settings.")
            return false
        case .ready:
            return true
        }
    }

    private func performWithFolderAccess<T>(_ operation: () throws -> T) throws -> T {
        do {
            let result = try folderAccess.withAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch let error as SecurityScopedFolderAccessError {
            recordFolderAccessProblem(error)
            throw error
        }
    }

    private func recordFolderAccessProblem(_ error: SecurityScopedFolderAccessError) {
        folderAccess.clearBookmark()
        state.hasSavedFolderAccess = false

        let message = "Choose the Mods folder again. \(error.localizedDescription)"
        if lastFolderAccessError != message {
            record(message)
            lastFolderAccessError = message
        }
    }

    private func record(_ message: String) {
        state.activityMessage = message
    }

    private func persistPreferences() {
        preferences.save(state)
    }

    private static func initialState(
        preferences: ModManagerPreferences,
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL
    ) -> ModManagerState {
        let defaultModsPath = StardewInstall.defaultModsDirectory().path
        let bookmarkedDirectoryPath = try? folderAccess.resolveBookmarkURL()?.path
        let savedDirectoryPath = preferences.modsDirectoryPath
        let initialDirectoryPath = bookmarkedDirectoryPath ?? savedDirectoryPath ?? defaultModsPath
        let install = StardewInstall(
            modsDirectory: URL(fileURLWithPath: initialDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )

        return ModManagerState(
            modsDirectoryPath: initialDirectoryPath,
            status: install.status(),
            hasSavedFolderAccess: folderAccess.hasBookmark,
            mods: [],
            modSets: [],
            selectedModSetID: preferences.selectedModSetID,
            appliedModSetID: nil,
            activityMessage: ""
        )
    }
}

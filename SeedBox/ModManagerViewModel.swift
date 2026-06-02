import AppKit
import Foundation

@MainActor
final class ModManagerViewModel: ObservableObject {
    @Published var modsDirectoryPath: String {
        didSet {
            persistAndRefresh()
        }
    }

    @Published private(set) var status: InstallationStatus
    @Published private(set) var mods: [ModInfo]
    @Published private(set) var activityMessage: String
    @Published private(set) var hasSavedFolderAccess: Bool
    @Published private(set) var isSMAPILikelyMissing: Bool
    @Published private(set) var modSets: [ModSet]
    @Published var selectedModSetID: String {
        didSet {
            defaults.set(selectedModSetID, forKey: Keys.selectedModSetID)
        }
    }

    private let defaults: UserDefaults
    private let folderAccess: SecurityScopedFolderAccess
    private var lastFolderAccessError: String?

    private enum Keys {
        static let modsDirectoryPath = "modsDirectoryPath"
        static let selectedModSetID = "selectedModSetID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        self.folderAccess = folderAccess

        let defaultModsPath = StardewInstall.defaultModsDirectory().path
        let bookmarkedDirectoryPath = try? folderAccess.resolveBookmarkURL()?.path
        let savedDirectoryPath = defaults.string(forKey: Keys.modsDirectoryPath)
        let initialDirectoryPath = bookmarkedDirectoryPath ?? savedDirectoryPath ?? defaultModsPath

        modsDirectoryPath = initialDirectoryPath
        mods = []
        activityMessage = ""
        hasSavedFolderAccess = folderAccess.hasBookmark
        isSMAPILikelyMissing = false
        modSets = []
        selectedModSetID = defaults.string(forKey: Keys.selectedModSetID) ?? ModSetStore.defaultSetID

        status = StardewInstall(
            modsDirectory: URL(fileURLWithPath: initialDirectoryPath, isDirectory: true)
        )
        .status()

        refresh()
    }

    var install: StardewInstall {
        StardewInstall(
            modsDirectory: URL(fileURLWithPath: modsDirectoryPath, isDirectory: true)
        )
    }

    var modFolderName: String {
        StardewInstall.modFolderName
    }

    var selectedModSetName: String {
        selectedModSet?.name ?? ModSetStore.defaultSetName
    }

    var canManageMods: Bool {
        hasSavedFolderAccess && status.canManageMods
    }

    var canDeleteSelectedModSet: Bool {
        guard let selectedModSet else {
            return false
        }
        return !selectedModSet.isDefault
    }

    var canEditSelectedModSet: Bool {
        canDeleteSelectedModSet
    }

    var selectedModSetForActions: ModSet? {
        selectedModSet
    }

    var selectedEditableModSet: ModSet? {
        guard canEditSelectedModSet else {
            return nil
        }
        return selectedModSet
    }

    var selectedDeletableModSet: ModSet? {
        guard canDeleteSelectedModSet else {
            return nil
        }
        return selectedModSet
    }

    func refresh() {
        hasSavedFolderAccess = folderAccess.hasBookmark
        if hasSavedFolderAccess {
            status = withFolderAccess {
                install.status()
            } ?? install.status()
        } else {
            status = install.status()
        }
        refreshSMAPIHint()
        reloadMods()
        reloadModSets()
    }

    func chooseModsFolder(_ selectedURL: URL) {
        let token = SecurityScopedAccessToken(url: selectedURL)
        defer {
            token.stop()
        }
        let resolvedURL = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedURL.lastPathComponent == StardewInstall.modFolderName else {
            record("Choose the folder named \(StardewInstall.modFolderName).")
            return
        }

        do {
            try folderAccess.saveBookmark(for: resolvedURL)
            hasSavedFolderAccess = folderAccess.hasBookmark
            lastFolderAccessError = nil
            record("Saved folder access for \(resolvedURL.path).")
        } catch {
            record("Could not save folder access: \(error.localizedDescription)")
            return
        }

        modsDirectoryPath = resolvedURL.path
        record("Selected \(resolvedURL.path).")
    }

    func recordModsFolderSelectionError(_ error: Error) {
        record("Could not choose Mods folder: \(error.localizedDescription)")
    }

    func revealModsFolder() {
        guard guardCanManageMods() else {
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
        guard guardCanManageMods() else {
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

    func createModFolder() {
        guard hasSavedFolderAccess else {
            record("Choose the Mods folder before creating it.")
            return
        }

        do {
            try performWithFolderAccess {
                try install.createModDirectory()
            }
            record("Created \(install.modDirectoryURL.path).")
            refresh()
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not create mod folder: \(error.localizedDescription)")
        }
    }

    func addMods(from selectedURLs: [URL]) {
        guard guardCanManageMods() else {
            return
        }

        guard !selectedURLs.isEmpty else {
            record("Choose one or more unzipped mod folders.")
            return
        }

        let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
        }

        do {
            let installedURLs = try performWithFolderAccess {
                try ModLibrary.installMods(
                    from: selectedURLs,
                    into: install
                )
            }
            let changeMessage = "Added \(installedURLs.count) mod folder\(installedURLs.count == 1 ? "" : "s")."
            record(changeMessage)
            refresh()
            saveCurrentStateToSelectedModSetIfEditable(
                recordingSuccess: "\(changeMessage) Updated \(selectedModSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not add mods: \(error.localizedDescription)")
        }
    }

    func recordAddModsSelectionError(_ error: Error) {
        record("Could not choose mods: \(error.localizedDescription)")
    }

    func setMod(_ mod: ModInfo, enabled: Bool) {
        guard guardCanManageMods() else {
            return
        }

        do {
            _ = try performWithFolderAccess {
                try ModLibrary.setEnabled(mod, enabled: enabled)
            }
            let changeMessage = "\(enabled ? "Enabled" : "Disabled") \(mod.displayName)."
            record(changeMessage)
            refresh()
            saveCurrentStateToSelectedModSetIfEditable(
                recordingSuccess: "\(changeMessage) Updated \(selectedModSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not update \(mod.displayName): \(error.localizedDescription)")
        }
    }

    func deleteMod(_ mod: ModInfo) {
        guard guardCanManageMods() else {
            return
        }

        do {
            try performWithFolderAccess {
                try ModLibrary.trash(mod)
            }
            let changeMessage = "Moved \(mod.displayName) to the Trash."
            record(changeMessage)
            refresh()
            saveCurrentStateToSelectedModSetIfEditable(
                recordingSuccess: "\(changeMessage) Updated \(selectedModSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not delete \(mod.displayName): \(error.localizedDescription)")
        }
    }

    func createModSet(named name: String, from sourceSet: ModSet? = nil) {
        guard guardCanManageMods() else {
            return
        }

        let source = sourceSet ?? ModSetStore.snapshotSet(
            id: "current",
            name: "Current",
            from: mods
        )

        do {
            let newSet = try ModSetStore.createSet(
                named: name,
                from: source,
                existingSets: modSets
            )

            try ModSetStore.saveSet(
                newSet,
                install: install
            )

            selectedModSetID = newSet.id
            record("Created mod set \(newSet.name).")
            refresh()
        } catch {
            record("Could not create mod set: \(error.localizedDescription)")
        }
    }

    func duplicateSelectedModSet(named name: String) {
        guard let selectedSet = selectedModSet else {
            return
        }

        createModSet(named: name, from: selectedSet)
    }

    func renameSelectedModSet(to requestedName: String) {
        guard guardCanManageMods() else {
            return
        }

        guard var selectedSet = selectedModSet else {
            return
        }
        guard !selectedSet.isDefault else {
            record("Default set name cannot be changed.")
            return
        }

        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            record("Set name cannot be empty.")
            return
        }

        let hasConflict = modSets.contains { set in
            set.id != selectedSet.id
                && set.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == trimmedName.lowercased()
        }
        if hasConflict {
            record("A mod set named \(trimmedName) already exists.")
            return
        }

        selectedSet.name = trimmedName

        do {
            try ModSetStore.saveSet(
                selectedSet,
                install: install
            )
            record("Renamed set to \(trimmedName).")
            refresh()
        } catch {
            record("Could not rename mod set: \(error.localizedDescription)")
        }
    }

    func applySelectedModSet() {
        guard guardCanManageMods() else {
            return
        }

        guard let selectedSet = selectedModSet else {
            record("Could not apply set: selection is missing.")
            return
        }

        do {
            let changedCount = try performWithFolderAccess {
                try ModSetStore.applySet(
                    selectedSet,
                    install: install
                )
            }

            record("Applied \(selectedSet.name) (\(changedCount) change\(changedCount == 1 ? "" : "s")).")
            refresh()
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record("Could not apply set: \(error.localizedDescription)")
        }
    }

    func deleteModSet(_ set: ModSet) {
        guard guardCanManageMods() else {
            return
        }

        do {
            try ModSetStore.deleteSet(
                set,
                install: install
            )

            if selectedModSetID == set.id {
                selectedModSetID = ModSetStore.defaultSetID
            }

            record("Deleted mod set \(set.name).")
            refresh()
        } catch {
            record("Could not delete mod set: \(error.localizedDescription)")
        }
    }

    private func saveCurrentStateToSelectedModSet(recordingSuccess successMessage: String? = nil) {
        guard guardCanManageMods() else {
            return
        }

        guard var selectedSet = selectedModSet else {
            return
        }
        guard !selectedSet.isDefault else {
            record("Default set cannot be changed.")
            return
        }

        selectedSet.disabledFolderNames = ModSetStore.snapshotSet(
            id: selectedSet.id,
            name: selectedSet.name,
            from: mods
        )
        .disabledFolderNames

        do {
            try ModSetStore.saveSet(
                selectedSet,
                install: install
            )
            record(successMessage ?? "Updated \(selectedSet.name).")
            refresh()
        } catch {
            record("Could not save mod set: \(error.localizedDescription)")
        }
    }

    private func persistAndRefresh() {
        defaults.set(modsDirectoryPath, forKey: Keys.modsDirectoryPath)
        refresh()
    }

    private func refreshSMAPIHint() {
        isSMAPILikelyMissing = false
    }

    private func reloadMods() {
        guard canManageMods else {
            mods = []
            return
        }

        do {
            mods = try performWithFolderAccess {
                try ModLibrary.scan(install: install)
            }
        } catch is SecurityScopedFolderAccessError {
            mods = []
        } catch {
            mods = []
            record("Could not read mods: \(error.localizedDescription)")
        }
    }

    private func reloadModSets() {
        guard canManageMods else {
            modSets = []
            selectedModSetID = ModSetStore.defaultSetID
            return
        }

        do {
            let loadedSets = try ModSetStore.loadSets(
                install: install,
                currentMods: mods
            )

            modSets = loadedSets
            if !loadedSets.contains(where: { $0.id == selectedModSetID }) {
                selectedModSetID = ModSetStore.defaultSetID
            }
        } catch {
            modSets = []
            selectedModSetID = ModSetStore.defaultSetID
            record("Could not read mod sets: \(error.localizedDescription)")
        }
    }

    private var selectedModSet: ModSet? {
        modSets.first(where: { $0.id == selectedModSetID })
    }

    private func saveCurrentStateToSelectedModSetIfEditable(recordingSuccess successMessage: String? = nil) {
        guard canEditSelectedModSet else {
            return
        }
        saveCurrentStateToSelectedModSet(recordingSuccess: successMessage)
    }

    private func guardCanManageMods() -> Bool {
        if !hasSavedFolderAccess {
            record("Choose the Mods folder before managing mods.")
            return false
        }

        if !status.modDirectoryExists {
            record("The Mods folder is missing. Choose it again from Settings.")
            return false
        }

        return true
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

    private func withFolderAccess<T>(_ operation: () throws -> T) -> T? {
        do {
            let result = try performWithFolderAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch is SecurityScopedFolderAccessError {
            return nil
        } catch {
            let message = error.localizedDescription
            if lastFolderAccessError != message {
                record("Could not restore saved folder access: \(message)")
                lastFolderAccessError = message
            }
            return nil
        }
    }

    private func recordFolderAccessProblem(_ error: SecurityScopedFolderAccessError) {
        folderAccess.clearBookmark()
        hasSavedFolderAccess = false

        let message = "Choose the Mods folder again. \(error.localizedDescription)"
        if lastFolderAccessError != message {
            record(message)
            lastFolderAccessError = message
        }
    }

    private func record(_ message: String) {
        activityMessage = message
    }
}

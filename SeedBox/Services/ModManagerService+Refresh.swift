import Foundation

extension ModManagerService {
    func reloadMods(in state: inout ModManagerState) {
        guard state.readiness.canManageMods else {
            state.mods = []
            state.invalidModFolders = []
            state.archivedMods = []
            state.archiveSummary = ModArchiveSummary()
            state.hasLoadedMods = false
            return
        }

        do {
            let currentInstall = install(for: state)
            let scanResult = try performWithFolderAccess(state: &state) {
                try ModLibrary.scanWithDiagnostics(install: currentInstall)
            }
            state.mods = scanResult.mods
            state.invalidModFolders = scanResult.invalidFolders
            state.hasLoadedMods = true
        } catch is SecurityScopedFolderAccessError {
            state.mods = []
            state.invalidModFolders = []
            state.hasLoadedMods = false
        } catch {
            state.mods = []
            state.invalidModFolders = []
            state.hasLoadedMods = false
            record(AppStrings.Status.couldNotReadMods(error.localizedDescription), severity: .error, in: &state)
        }
    }

    func reloadArchivedMods(in state: inout ModManagerState) {
        guard state.readiness.canManageMods else {
            state.archivedMods = []
            state.archiveSummary = ModArchiveSummary()
            return
        }

        do {
            let archiveDirectoryURL = install(for: state).archivedModsDirectoryURL
            state.archivedMods = try ModArchive.archivedMods(in: archiveDirectoryURL)
            state.archiveSummary = try ModArchive.summary(in: archiveDirectoryURL)
        } catch {
            state.archivedMods = []
            state.archiveSummary = ModArchiveSummary()
            record(AppStrings.Status.couldNotReadArchivedMods(error.localizedDescription), severity: .error, in: &state)
        }
    }

    func reloadModSets(in state: inout ModManagerState) {
        guard state.readiness.canManageMods else {
            state.modSets = []
            setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            state.appliedModSetID = nil
            return
        }

        do {
            let loadedSets = try ModSetStore.loadSets(
                install: install(for: state),
                currentMods: state.mods
            )

            state.modSets = loadedSets
            if !loadedSets.contains(where: { $0.id == state.selectedModSetID }) {
                setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            }
            if let appliedModSetID = state.appliedModSetID,
               !loadedSets.contains(where: { $0.id == appliedModSetID }) {
                state.appliedModSetID = nil
            }
            if let appliedSet = state.appliedModSetID.flatMap({ appliedID in
                loadedSets.first { $0.id == appliedID }
            }), !modSetMatchesCurrentMods(appliedSet, in: state) {
                state.appliedModSetID = nil
            }
            if state.appliedModSetID == nil,
               let selectedSet = state.modSetSelection.selectedSet,
               modSetMatchesCurrentMods(selectedSet, in: state) {
                state.appliedModSetID = selectedSet.id
            }
        } catch {
            state.modSets = []
            setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            state.appliedModSetID = nil
            record(AppStrings.Status.couldNotReadModSets(error.localizedDescription), severity: .error, in: &state)
        }
    }

    func reloadAuditTrail(in state: inout ModManagerState) {
        auditRecorder.reloadTrail(in: &state)
    }

    func automaticallyPruneExpiredArchivedMods(in state: inout ModManagerState) {
        guard state.archiveSettings.automaticallyPrunesExpiredArchives else {
            return
        }

        do {
            let prunedCount = try pruneExpiredArchiveCount(in: state)
            guard prunedCount > 0 else {
                return
            }

            auditArchivesPruned(
                count: prunedCount,
                summary: AppStrings.Status.prunedExpiredArchives(count: prunedCount),
                source: "automatic",
                in: &state
            )
        } catch {
            record(AppStrings.Status.couldNotPruneArchivedMods(error.localizedDescription), severity: .error, in: &state)
        }
    }

    func pruneExpiredArchiveCount(in state: ModManagerState) throws -> Int {
        try ModArchive.pruneExpiredArchives(
            in: install(for: state).archivedModsDirectoryURL,
            olderThan: Date().addingTimeInterval(-state.archiveSettings.retentionInterval)
        )
    }
}

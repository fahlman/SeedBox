import Foundation

struct ModManagerPresentationState {
    var state: ModManagerState
    var searchText: String
    var selectedModIDs: Set<String>
    var dependencyGraph: ModDependencyGraph
    var filteredMods: [ModInfo]
    var selection: ModSelectionState

    init(
        state: ModManagerState,
        searchText: String,
        selectedModIDs: Set<String>
    ) {
        let dependencyGraph = ModDependencyGraph(mods: state.mods)
        let query = ModSearchQuery(searchText)
        let filteredMods = state.mods.filter { mod in
            query.matches(
                mod,
                in: dependencyGraph,
                hasAvailableUpdate: state.availableUpdate(for: mod) != nil
            )
        }
        let selectedMod = Self.selectedMod(in: filteredMods, selectedModIDs: selectedModIDs)

        self.state = state
        self.searchText = searchText
        self.selectedModIDs = selectedModIDs
        self.dependencyGraph = dependencyGraph
        self.filteredMods = filteredMods
        selection = ModSelectionState(
            selectedModIDs: selectedModIDs,
            selectedMod: selectedMod,
            state: state,
            dependencyGraph: dependencyGraph
        )
    }

    var readiness: ModManagerReadiness {
        state.readiness
    }

    var modSetSelection: ModSetSelectionState {
        state.modSetSelection
    }

    var statusLineMessage: String {
        state.statusLineMessage
    }

    var statusLineSeverity: StatusEvent.Severity {
        state.statusLineSeverity
    }

    var archiveSummary: ModArchiveSummary {
        state.archiveSummary
    }

    var archiveRetentionDays: Int {
        state.archiveSettings.normalizedRetentionDays
    }

    var auditTrail: AuditTrailState {
        state.auditTrail
    }

    var pendingSourceCleanupOffer: SourceCleanupOffer? {
        state.pendingSourceCleanupOffer
    }

    var problemSummary: ModProblemSummary {
        ModProblemSummary(
            dependencyIssues: state.dependencyIssues,
            invalidFolders: state.invalidModFolders,
            duplicateGroups: state.duplicateGroups,
            smapiVersionIssues: state.smapiVersionIssues,
            detectedSMAPIVersion: state.detectedSMAPIVersion
        )
    }

    var selectedSet: ModSet? {
        modSetSelection.selectedSet
    }

    var selectedRenamableSet: ModSet? {
        modSetSelection.selectedRenamableSet
    }

    var selectedDeletableSet: ModSet? {
        modSetSelection.selectedDeletableSet
    }

    var canManageMods: Bool {
        readiness.canManageMods
    }

    var canShowProblems: Bool {
        state.hasProblems
    }

    var canShowActivity: Bool {
        !state.auditTrail.recentEntries.isEmpty
    }

    var canCompareSelectedModSet: Bool {
        state.modSetSelection.selectedSet != nil && canManageMods
    }

    var canPruneExpiredArchives: Bool {
        state.archiveSummary.archivedModCount > 0
    }

    var canShowRestoreHistory: Bool {
        state.archiveSummary.archivedModCount > 0
    }

    var canRestorePreviousVersion: Bool {
        canManageMods && selection.canRestorePreviousVersion
    }

    var canRevealSelectedMod: Bool {
        canManageMods && selection.hasSelectedMod
    }

    var canDeleteSelectedMod: Bool {
        canManageMods && selection.hasSelectedMod
    }

    var canShowModInspector: Bool {
        canManageMods && selection.hasSelectedMod
    }

    var selectedModSetComparison: ModSetComparison? {
        guard let selectedSet else {
            return nil
        }

        return ModManagerInsights.comparison(
            for: selectedSet,
            currentMods: state.mods
        )
    }

    func modSet(withID id: String) -> ModSet? {
        state.modSets.first { $0.id == id }
    }

    func modSetIsAlreadyApplied(_ id: String) -> Bool {
        state.selectedModSetID == id && state.appliedModSetID == id
    }

    private static func selectedMod(
        in filteredMods: [ModInfo],
        selectedModIDs: Set<String>
    ) -> ModInfo? {
        guard selectedModIDs.count == 1,
              let selectedModID = selectedModIDs.first
        else {
            return nil
        }

        return filteredMods.first { $0.id == selectedModID }
    }
}

struct ModProblemSummary {
    var dependencyIssues: [ModInfo]
    var invalidFolders: [InvalidModFolder]
    var duplicateGroups: [ModDuplicateGroup]
    var smapiVersionIssues: [ModInfo]
    var detectedSMAPIVersion: String?
}

struct ModSelectionState {
    var selectedModIDs: Set<String>
    var mod: ModInfo?
    var dependencyStatuses: [ModDependencyStatus]
    var dependents: [ModInfo]
    var previousArchivedVersion: ArchivedModInfo?
    var archivedVersions: [ArchivedModInfo]
    var duplicateGroups: [ModDuplicateGroup]
    var availableUpdate: ModAvailableUpdate?
    var dependencyPageURLs: [String: URL]
    var lastSessionIssue: LastSessionModIssue?

    init(
        selectedModIDs: Set<String>,
        selectedMod: ModInfo?,
        state: ModManagerState,
        dependencyGraph: ModDependencyGraph
    ) {
        self.selectedModIDs = selectedModIDs
        mod = selectedMod

        if let selectedMod {
            dependencyStatuses = dependencyGraph.dependencyStatuses(for: selectedMod)
            dependents = dependencyGraph.dependents(of: selectedMod)
            previousArchivedVersion = ModArchive.previousVersion(for: selectedMod, in: state.archivedMods)
            archivedVersions = ModArchive.archivedVersions(for: selectedMod, in: state.archivedMods)
            duplicateGroups = state.duplicateGroups.filter { group in
                group.mods.contains { $0.id == selectedMod.id }
            }
            availableUpdate = state.availableUpdate(for: selectedMod)
            dependencyPageURLs = state.knownModPageURLs.filter { id, _ in
                selectedMod.dependencyRequirements.contains { requirement in
                    requirement.normalizedUniqueID == id
                }
            }
            lastSessionIssue = state.lastSessionIssues.first { $0.mod.id == selectedMod.id }
        } else {
            dependencyStatuses = []
            dependents = []
            previousArchivedVersion = nil
            archivedVersions = []
            duplicateGroups = []
            availableUpdate = nil
            dependencyPageURLs = [:]
            lastSessionIssue = nil
        }
    }

    var hasSelectedMod: Bool {
        mod != nil
    }

    var canRestorePreviousVersion: Bool {
        previousArchivedVersion != nil
    }
}

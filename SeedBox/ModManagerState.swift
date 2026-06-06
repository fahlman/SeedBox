import Foundation

struct ModManagerState: Equatable, Sendable {
    var modsDirectoryPath: String
    var status: InstallationStatus
    var hasSavedFolderAccess: Bool
    var mods: [ModInfo]
    var invalidModFolders: [InvalidModFolder]
    var archivedMods: [ArchivedModInfo]
    var archiveSummary: ModArchiveSummary
    var archiveSettings: ArchiveSettings
    var hasLoadedMods: Bool
    var modSets: [ModSet]
    var selectedModSetID: String
    var appliedModSetID: String?
    var activityMessage: String
    var auditTrail: AuditTrailState
    var pendingSourceCleanupOffer: SourceCleanupOffer?

    var readiness: ModManagerReadiness {
        if !hasSavedFolderAccess {
            return .needsFolderAccess
        }

        if !status.modDirectoryExists {
            return .missingModsFolder
        }

        return .ready
    }

    var modSetSelection: ModSetSelectionState {
        ModSetSelectionState(
            sets: modSets,
            selectedSetID: selectedModSetID,
            appliedSetID: appliedModSetID
        )
    }

    var statusLineMessage: String {
        if !activityMessage.isEmpty {
            return activityMessage
        }

        return auditTrail.recentEntries.last?.summary ?? ""
    }

    var duplicateGroups: [ModDuplicateGroup] {
        ModManagerInsights.duplicateGroups(in: mods)
    }

    var dependencyIssues: [ModInfo] {
        mods.filter { mod in
            mod.hasMissingRequiredDependencies || mod.hasMissingOptionalDependencies
        }
    }

    var hasProblems: Bool {
        !dependencyIssues.isEmpty || !invalidModFolders.isEmpty || !duplicateGroups.isEmpty
    }
}

struct SourceCleanupOffer: Identifiable, Equatable, Sendable {
    var id: UUID
    var sourceURLs: [URL]
    var importSummary: String
    var cleanupSummary: String?
    var isNotificationOnly: Bool

    init(
        id: UUID = UUID(),
        sourceURLs: [URL],
        importSummary: String,
        cleanupSummary: String? = nil,
        isNotificationOnly: Bool = false
    ) {
        self.id = id
        self.sourceURLs = sourceURLs
        self.importSummary = importSummary
        self.cleanupSummary = cleanupSummary
        self.isNotificationOnly = isNotificationOnly
    }

    var sourceCount: Int {
        sourceURLs.count
    }

    var selectedItemText: String {
        AppStrings.SourceCleanup.selectedItemText(count: sourceCount)
    }
}

enum ModManagerReadiness: Equatable, Sendable {
    case needsFolderAccess
    case missingModsFolder
    case ready

    var canManageMods: Bool {
        self == .ready
    }

    var canCreateModFolder: Bool {
        self == .missingModsFolder
    }

    func setupTitle(modFolderName: String) -> String {
        switch self {
        case .needsFolderAccess:
            return AppStrings.Setup.chooseModsFolderTitle
        case .missingModsFolder:
            return AppStrings.Setup.createFolderTitle(modFolderName)
        case .ready:
            return AppStrings.Setup.ready
        }
    }

    func setupDetail(modFolderName: String) -> String {
        switch self {
        case .needsFolderAccess:
            return AppStrings.Setup.selectModsFolder
        case .missingModsFolder:
            return AppStrings.Setup.seedBoxManagesModsFolder
        case .ready:
            return AppStrings.Setup.folderIsReady(modFolderName)
        }
    }

    var primarySetupButtonTitle: String {
        switch self {
        case .needsFolderAccess:
            return AppStrings.Setup.chooseFolder
        case .missingModsFolder, .ready:
            return AppStrings.Setup.createFolder
        }
    }

    var primarySetupButtonIcon: String {
        switch self {
        case .needsFolderAccess:
            return "folder"
        case .missingModsFolder, .ready:
            return "folder.badge.plus"
        }
    }

    var modsFolderStatusText: String {
        switch self {
        case .ready:
            return AppStrings.Setup.ready
        case .needsFolderAccess:
            return AppStrings.Setup.needsAccess
        case .missingModsFolder:
            return AppStrings.Setup.missing
        }
    }
}

struct ModSetSelectionState: Equatable, Sendable {
    var sets: [ModSet]
    var selectedSetID: String
    var appliedSetID: String?

    var selectedSet: ModSet? {
        sets.first { $0.id == selectedSetID }
    }

    var selectedSetName: String {
        selectedSet?.name ?? ModSetStore.defaultSetName
    }

    var selectedSetIsApplied: Bool {
        selectedSetID == appliedSetID
    }

    var selectedSetCanBeRenamed: Bool {
        guard let selectedSet else {
            return false
        }
        return selectedSet.isUserEditable
    }

    var selectedSetCanBeDeleted: Bool {
        selectedSetCanBeRenamed
    }

    var selectedRenamableSet: ModSet? {
        guard selectedSetCanBeRenamed else {
            return nil
        }
        return selectedSet
    }

    var selectedDeletableSet: ModSet? {
        guard selectedSetCanBeDeleted else {
            return nil
        }
        return selectedSet
    }
}

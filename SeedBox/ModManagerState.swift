import Foundation

struct ModManagerState: Equatable, Sendable {
    var modsDirectoryPath: String
    var status: InstallationStatus
    var hasSavedFolderAccess: Bool
    var mods: [ModInfo]
    var hasLoadedMods: Bool
    var modSets: [ModSet]
    var selectedModSetID: String
    var appliedModSetID: String?
    var activityMessage: String
    var auditTrail: AuditTrailState

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
            return "Choose Mods Folder"
        case .missingModsFolder:
            return "Create \(modFolderName)"
        case .ready:
            return "Ready"
        }
    }

    func setupDetail(modFolderName: String) -> String {
        switch self {
        case .needsFolderAccess:
            return "Select the Mods folder Seed Box should manage."
        case .missingModsFolder:
            return "Seed Box manages this Mods folder directly."
        case .ready:
            return "\(modFolderName) is ready."
        }
    }

    var primarySetupButtonTitle: String {
        switch self {
        case .needsFolderAccess:
            return "Choose Folder"
        case .missingModsFolder, .ready:
            return "Create Folder"
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
            return "Ready"
        case .needsFolderAccess:
            return "Needs access"
        case .missingModsFolder:
            return "Missing"
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

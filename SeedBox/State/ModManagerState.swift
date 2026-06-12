import Foundation

struct StatusEvent: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case info
        case error
    }

    var severity: Severity
    var message: String
}

struct ModManagerState: Equatable, Sendable {
    var modsDirectoryPath: String
    var status: InstallationStatus
    var hasSavedFolderAccess: Bool
    var mods: [ModInfo]
    var invalidModFolders: [InvalidModFolder]
    var archivedMods: [ArchivedModInfo]
    var archiveSummary: ModArchiveSummary
    var archiveSettings: ArchiveSettings
    var sourceCleanupSettings = SourceCleanupSettings(
        moveModFilesToTrashAfterAddingMods: false,
        suppressAddModsSuccessNotification: false
    )
    var checksForModUpdates = false
    var availableUpdates: [ModAvailableUpdate] = []
    var availableSMAPIUpdate: ModAvailableUpdate?
    /// Mod pages resolved during update checks, keyed by normalized unique ID.
    /// Powers "Get Mod" links for missing dependencies.
    var knownModPageURLs: [String: URL] = [:]
    var hasLoadedMods: Bool
    var modSets: [ModSet]
    var selectedModSetID: String
    var appliedModSetID: String?
    var activityStatus: StatusEvent?
    var bisectionSession: ModBisectionSession?
    var hasSMAPILogFolderAccess = false
    var lastSessionReport: SMAPILogReport?
    var pendingLastSessionNotice: LastSessionNotice?
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

    /// String-level access to the current status event, kept for the many
    /// call sites that only deal in messages. Setting a message produces an
    /// info-severity event; clearing it removes the event.
    var activityMessage: String {
        get {
            activityStatus?.message ?? ""
        }
        set {
            activityStatus = newValue.isEmpty
                ? nil
                : StatusEvent(severity: .info, message: newValue)
        }
    }

    var statusLineMessage: String {
        if let activityStatus {
            return activityStatus.message
        }

        return auditTrail.recentEntries.last?.summary ?? ""
    }

    var statusLineSeverity: StatusEvent.Severity {
        activityStatus?.severity ?? .info
    }

    var duplicateGroups: [ModDuplicateGroup] {
        ModManagerInsights.duplicateGroups(in: mods)
    }

    var dependencyIssues: [ModInfo] {
        mods.filter { mod in
            mod.hasMissingRequiredDependencies || mod.hasMissingOptionalDependencies
        }
    }

    /// Enabled mods whose declared MinimumApiVersion exceeds the installed
    /// SMAPI version detected from the bundled mods.
    var smapiVersionIssues: [ModInfo] {
        guard let smapiVersion = detectedSMAPIVersion else {
            return []
        }

        return mods.filter { mod in
            guard mod.isEnabled,
                  let minimumVersion = mod.manifest?.minimumApiVersion?.trimmedNonEmpty
            else {
                return false
            }

            return !ModVersionComparator.version(smapiVersion, satisfiesMinimum: minimumVersion)
        }
    }

    /// Last-session log findings attributed to currently installed mods.
    /// Entries for mods that were removed since the session are dropped.
    var lastSessionIssues: [LastSessionModIssue] {
        guard let lastSessionReport else {
            return []
        }

        var skippedReasonsByName: [String: String] = [:]
        for skippedMod in lastSessionReport.skippedMods {
            skippedReasonsByName[skippedMod.name.lowercased()] = skippedMod.reason
        }

        return mods.compactMap { mod in
            let nameKey = mod.displayName.lowercased()
            let skippedReason = skippedReasonsByName[nameKey]
            let errorCount = lastSessionReport.modErrorCounts[nameKey] ?? 0
            guard skippedReason != nil || errorCount > 0 else {
                return nil
            }

            return LastSessionModIssue(
                mod: mod,
                skippedReason: skippedReason,
                errorCount: errorCount
            )
        }
    }

    var hasProblems: Bool {
        !dependencyIssues.isEmpty
            || !invalidModFolders.isEmpty
            || !duplicateGroups.isEmpty
            || !smapiVersionIssues.isEmpty
            || !lastSessionIssues.isEmpty
    }

    /// The installed SMAPI version, derived from SMAPI's bundled mods inside
    /// the Mods folder so no access outside the folder is needed.
    var detectedSMAPIVersion: String? {
        SMAPIIdentifiers.detectedSMAPIVersion(in: mods)
    }

    /// The known SMAPI update, if it is still newer than what's installed.
    var smapiUpdate: ModAvailableUpdate? {
        guard let availableSMAPIUpdate,
              !ModVersionComparator.version(
                detectedSMAPIVersion,
                satisfiesMinimum: availableSMAPIUpdate.latestVersion
              )
        else {
            return nil
        }

        return availableSMAPIUpdate
    }

    /// The known update for a mod, if it is still newer than what's installed.
    /// Check results are point-in-time; installing or updating a mod after a
    /// check makes its entry stale, so freshness is decided here.
    func availableUpdate(for mod: ModInfo) -> ModAvailableUpdate? {
        guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
              let update = availableUpdates.first(where: { $0.modID == uniqueID }),
              !ModVersionComparator.version(
                mod.manifest?.version,
                satisfiesMinimum: update.latestVersion
              )
        else {
            return nil
        }

        return update
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

    /// The status message explaining why mod management is unavailable, or
    /// nil when ready.
    var managementBlockedMessage: String? {
        switch self {
        case .needsFolderAccess:
            return AppStrings.Status.chooseModsFolderBeforeManaging
        case .missingModsFolder:
            return AppStrings.Status.modsFolderMissingChooseAgain
        case .ready:
            return nil
        }
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

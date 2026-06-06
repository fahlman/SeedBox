import Foundation

enum AppStrings {
    enum App {
        static let name = String(localized: "Seed Box")
    }

    enum ModSetNames {
        static let all = String(localized: "All")
        static let none = String(localized: "None")
        static let defaultSet = String(localized: "Default")
        static let current = String(localized: "Current")
        static let newSet = String(localized: "New Set")
        static let untitledSet = String(localized: "Untitled Set")

        static func copiedSetName(_ setName: String) -> String {
            String(localized: "\(setName) Copy")
        }
    }

    enum Setup {
        static let chooseFolder = String(localized: "Choose Folder")
        static let chooseModsFolderTitle = String(localized: "Choose Mods Folder")
        static let createFolder = String(localized: "Create Folder")
        static let needsAccess = String(localized: "Needs access")
        static let missing = String(localized: "Missing")
        static let ready = String(localized: "Ready")
        static let seedBoxManagesModsFolder = String(localized: "Seed Box manages this Mods folder directly.")
        static let selectModsFolder = String(localized: "Select the Mods folder Seed Box should manage.")

        static func createFolderTitle(_ folderName: String) -> String {
            String(localized: "Create \(folderName)")
        }

        static func folderIsReady(_ folderName: String) -> String {
            String(localized: "\(folderName) is ready.")
        }
    }

    enum EmptyState {
        static let addModsPrompt = String(localized: "Add a mod folder or ZIP archive to install it.")

        static func noMods(in folderName: String) -> String {
            String(localized: "No mods in \(folderName)")
        }
    }

    enum ModSetEditor {
        static let createAction = String(localized: "Create")
        static let createTitle = String(localized: "New Mod Set")
        static let duplicateAction = String(localized: "Duplicate")
        static let duplicateTitle = String(localized: "Duplicate Mod Set")
        static let renameAction = String(localized: "Rename")
        static let renameTitle = String(localized: "Rename Mod Set")
    }

    enum Search {
        static let prompt = String(localized: "Search Mods")
    }

    enum Common {
        static let cancel = String(localized: "Cancel")
        static let delete = String(localized: "Delete")
    }

    enum Commands {
        static let addMods = String(localized: "Add Mods...")
        static let chooseModsFolder = String(localized: "Choose Mods Folder...")
        static let compareModSet = String(localized: "Compare Mod Set")
        static let deleteModSet = String(localized: "Delete Mod Set")
        static let deleteSelectedMod = String(localized: "Delete Selected Mod")
        static let duplicateModSet = String(localized: "Duplicate Mod Set")
        static let modSetMenu = String(localized: "Mod Set")
        static let modsMenu = String(localized: "Mods")
        static let newModSet = String(localized: "New Mod Set")
        static let pruneExpiredArchives = String(localized: "Prune Expired Archives")
        static let refreshModsFolder = String(localized: "Refresh Mods Folder")
        static let renameModSet = String(localized: "Rename Mod Set")
        static let restorePreviousVersion = String(localized: "Restore Previous Version")
        static let revealArchivedModsInFinder = String(localized: "Reveal Archived Mods in Finder")
        static let revealModsFolderInFinder = String(localized: "Reveal Mods Folder in Finder")
        static let revealSelectedModInFinder = String(localized: "Reveal Selected Mod in Finder")
        static let showModDetails = String(localized: "Show Mod Details")
    }

    enum Table {
        static let author = String(localized: "Author")
        static let mod = String(localized: "Mod")
        static let state = String(localized: "State")
        static let type = String(localized: "Type")
        static let updates = String(localized: "Updates")
    }

    enum Toolbar {
        static let activity = String(localized: "Activity")
        static let addMods = String(localized: "Add Mods")
        static let compareModSet = String(localized: "Compare Mod Set")
        static let deleteMod = String(localized: "Delete Mod")
        static let deleteSet = String(localized: "Delete Set")
        static let duplicateSet = String(localized: "Duplicate Set")
        static let hideDetails = String(localized: "Hide Details")
        static let modSet = String(localized: "Mod Set")
        static let newModSet = String(localized: "New Mod Set")
        static let problems = String(localized: "Problems")
        static let pruneExpiredArchives = String(localized: "Prune Expired Archives")
        static let renameSet = String(localized: "Rename Set")
        static let restorePreviousVersion = String(localized: "Restore Previous Version")
        static let revealInFinder = String(localized: "Reveal in Finder")
        static let settings = String(localized: "Settings")
        static let showDetails = String(localized: "Show Details")
    }

    enum Settings {
        static let addingModsSection = String(localized: "Adding Mods")
        static let archivesSection = String(localized: "Archives")
        static let automaticallyPruneExpiredArchives = String(localized: "Automatically prune expired archives")
        static let folder = String(localized: "Folder")
        static let folderAccess = String(localized: "Folder Access")
        static let keepArchivedMods = String(localized: "Keep archived mods")
        static let managedModsFolderSection = String(localized: "Managed Mods Folder")
        static let moveModFilesToTrashAfterAddingMods = String(localized: "Move mod files to trash after successfully adding mods")
        static let notSaved = String(localized: "Not saved")
        static let reveal = String(localized: "Reveal")
        static let saved = String(localized: "Saved")
        static let suppressAddModsSuccessNotification = String(localized: "Do not display notification after successfully adding mods")

        static func days(_ count: Int) -> String {
            String(localized: "\(count) days")
        }
    }

    enum Alerts {
        static let deleteModTitle = String(localized: "Delete Mod?")
        static let deleteModSetTitle = String(localized: "Delete Mod Set?")
        static let dependencyWarning = String(localized: "Dependency Warning")
        static let disableAnyway = String(localized: "Disable Anyway")
        static let disableDependentMods = String(localized: "Disable Dependent Mods")
        static let enableAnyway = String(localized: "Enable Anyway")
        static let enableRequiredDependencies = String(localized: "Enable Required Dependencies")
        static let missingRequiredDependencies = String(localized: "Missing Required Dependencies")
        static let requiredByEnabledMods = String(localized: "Required by Enabled Mods")
        static let unresolvedRequiredDependencies = String(localized: "Unresolved Required Dependencies")
        static let applyAnyway = String(localized: "Apply Anyway")

        static func deleteModMessage(_ modName: String, retentionDays: Int) -> String {
            String(localized: "Delete \(modName)? A restorable copy will be archived for \(retentionDays) days.")
        }

        static func deleteModSetMessage(_ setName: String) -> String {
            String(localized: "Remove the saved mod set \(setName)?")
        }
    }

    enum Dependency {
        static func formattedList(_ values: [String]) -> String {
            ListFormatter.localizedString(byJoining: values)
        }

        static func enableWarning(modName: String, dependencySummary: String, dependencyCount: Int) -> String {
            if dependencyCount == 1 {
                return String(localized: "\(modName) requires \(dependencySummary), which is not ready. Would you like to enable \(modName) anyway?")
            }
            return String(localized: "\(modName) requires \(dependencySummary), which are not ready. Would you like to enable \(modName) anyway?")
        }

        static func disableWarning(modName: String, dependentSummary: String, dependentCount: Int) -> String {
            if dependentCount == 1 {
                return String(localized: "\(dependentSummary) requires \(modName). Would you like to disable \(modName) anyway?")
            }
            return String(localized: "\(modName) is required by \(dependentSummary). Would you like to disable \(modName) anyway?")
        }

        static func singleModSetIssue(setName: String, modName: String, dependencySummary: String) -> String {
            String(localized: "Applying \(setName) will leave \(modName) with unresolved dependencies: \(dependencySummary). Apply anyway?")
        }

        static func multipleModSetIssues(setName: String, issueCount: Int, examples: String) -> String {
            String(localized: "Applying \(setName) will leave \(issueCount) mods with missing required dependencies. Apply anyway?\n\n\(examples)")
        }

        static func missing(displayName: String) -> String {
            String(localized: "\(displayName) is not installed")
        }

        static func missing(displayName: String, minimumVersion: String) -> String {
            String(localized: "\(displayName) \(minimumVersion) or newer is not installed")
        }

        static func disabled(displayName: String) -> String {
            String(localized: "\(displayName) is disabled")
        }

        static func disabled(displayName: String, minimumVersion: String) -> String {
            String(localized: "\(displayName) \(minimumVersion) or newer is disabled")
        }

        static func tooOld(displayName: String) -> String {
            String(localized: "\(displayName) is too old")
        }

        static func tooOld(displayName: String, installedVersion: String, minimumVersion: String) -> String {
            String(localized: "\(displayName) \(installedVersion) is older than required \(minimumVersion)")
        }
    }

    enum Mods {
        static let contentPatcher = String(localized: "Content Patcher")
        static let curseForge = String(localized: "CurseForge")
        static let disabled = String(localized: "Disabled")
        static let enabled = String(localized: "Enabled")
        static let github = String(localized: "GitHub")
        static let modDrop = String(localized: "ModDrop")
        static let nexus = String(localized: "Nexus")
        static let notLinked = String(localized: "Not linked")
        static let notInstalled = String(localized: "Not installed")
        static let smapi = String(localized: "SMAPI")
        static let unknown = String(localized: "Unknown")
        static let unknownAuthor = String(localized: "Unknown author")
        static let unknownVersion = String(localized: "Unknown version")

        static func contentPackFor(_ dependencyID: String) -> String {
            String(localized: "For \(dependencyID)")
        }

        static func dependencyMetadata(requiredCount: Int, optionalCount: Int) -> String {
            switch (requiredCount, optionalCount) {
            case (1, 1):
                return String(localized: "1 required + 1 optional dep")
            case (1, _):
                return String(localized: "1 required + \(optionalCount) optional deps")
            case (_, 1):
                return String(localized: "\(requiredCount) required + 1 optional dep")
            default:
                return String(localized: "\(requiredCount) required + \(optionalCount) optional deps")
            }
        }

        static func requiredDependencyMetadata(count: Int) -> String {
            String(localized: "\(count) required deps")
        }

        static func optionalDependencyMetadata(count: Int) -> String {
            String(localized: "\(count) optional deps")
        }

        static func missingRequiredDependencies(_ summary: String) -> String {
            String(localized: "Missing required: \(summary)")
        }

        static func missingOptionalDependencies(_ summary: String) -> String {
            String(localized: "Missing optional: \(summary)")
        }
    }

    enum Status {
        static let chooseModFoldersOrZipArchives = String(localized: "Choose one or more mod folders or ZIP archives.")
        static let chooseModsFolderBeforeCreating = String(localized: "Choose the Mods folder before creating it.")
        static let chooseModsFolderBeforeManaging = String(localized: "Choose the Mods folder before managing mods.")
        static let chooseArchivedModsToRestore = String(localized: "Choose one or more archived mods to restore.")
        static let includedModSetNamesCannotBeChanged = String(localized: "Included mod set names cannot be changed.")
        static let modsFolderChangedRefreshed = String(localized: "Mods folder changed. Refreshed mod list.")
        static let modsFolderMissingChooseAgain = String(localized: "The Mods folder is missing. Choose it again from Settings.")
        static let noModFoldersInstalled = String(localized: "No mod folders were installed.")
        static let setNameCannotBeEmpty = String(localized: "Set name cannot be empty.")

        static func addedModFolders(count: Int) -> String {
            String(localized: "Added \(count) mod folders.")
        }

        static func addedModFoldersSentence(count: Int) -> String {
            String(localized: "Added \(count) mod folders.")
        }

        static func alreadyInstalledMod(_ displayName: String) -> String {
            String(localized: "\(displayName) is already installed.")
        }

        static func appliedSet(_ setName: String, changedCount: Int) -> String {
            String(localized: "Applied \(setName) (\(changedCount) changes).")
        }

        static func chooseFolderNamed(_ folderName: String) -> String {
            String(localized: "Choose the folder named \(folderName).")
        }

        static func chooseModsFolderAgain(_ errorDescription: String) -> String {
            String(localized: "Choose the Mods folder again. \(errorDescription)")
        }

        static func couldNotAddMods(_ errorDescription: String) -> String {
            String(localized: "Could not add mods: \(errorDescription)")
        }

        static func couldNotApplySet(_ errorDescription: String) -> String {
            String(localized: "Could not apply set: \(errorDescription)")
        }

        static func couldNotChooseMods(_ errorDescription: String) -> String {
            String(localized: "Could not choose mods: \(errorDescription)")
        }

        static func couldNotChooseModsFolder(_ errorDescription: String) -> String {
            String(localized: "Could not choose Mods folder: \(errorDescription)")
        }

        static func couldNotPreviewMods(_ errorDescription: String) -> String {
            String(localized: "Could not preview mods: \(errorDescription)")
        }

        static func couldNotCreateModFolder(_ errorDescription: String) -> String {
            String(localized: "Could not create mod folder: \(errorDescription)")
        }

        static func couldNotCreateModSet(_ errorDescription: String) -> String {
            String(localized: "Could not create mod set: \(errorDescription)")
        }

        static func couldNotDeleteMod(_ modName: String, errorDescription: String) -> String {
            String(localized: "Could not delete \(modName): \(errorDescription)")
        }

        static func couldNotDeleteModSet(_ errorDescription: String) -> String {
            String(localized: "Could not delete mod set: \(errorDescription)")
        }

        static func couldNotPruneArchivedMods(_ errorDescription: String) -> String {
            String(localized: "Could not prune archived mods: \(errorDescription)")
        }

        static func couldNotReadModSets(_ errorDescription: String) -> String {
            String(localized: "Could not read mod sets: \(errorDescription)")
        }

        static func couldNotReadArchivedMods(_ errorDescription: String) -> String {
            String(localized: "Could not read archived mods: \(errorDescription)")
        }

        static func couldNotReadMods(_ errorDescription: String) -> String {
            String(localized: "Could not read mods: \(errorDescription)")
        }

        static func couldNotReconcileAddedMods(_ errorDescription: String) -> String {
            String(localized: "Could not reconcile added mods: \(errorDescription)")
        }

        static func couldNotReconcileInstalledMods(_ errorDescription: String) -> String {
            String(localized: "Could not reconcile installed mods: \(errorDescription)")
        }

        static func couldNotRenameModSet(_ errorDescription: String) -> String {
            String(localized: "Could not rename mod set: \(errorDescription)")
        }

        static func couldNotRestoreArchivedMods(_ errorDescription: String) -> String {
            String(localized: "Could not restore archived mods: \(errorDescription)")
        }

        static func couldNotRestoreSavedFolderAccess(_ errorDescription: String) -> String {
            String(localized: "Could not restore saved folder access: \(errorDescription)")
        }

        static func couldNotRevealArchivedMods(_ errorDescription: String) -> String {
            String(localized: "Could not reveal archived mods: \(errorDescription)")
        }

        static func couldNotRevealMod(_ modName: String, errorDescription: String) -> String {
            String(localized: "Could not reveal \(modName): \(errorDescription)")
        }

        static func couldNotRevealModsFolder(_ errorDescription: String) -> String {
            String(localized: "Could not reveal Mods folder: \(errorDescription)")
        }

        static func couldNotSaveFolderAccess(_ errorDescription: String) -> String {
            String(localized: "Could not save folder access: \(errorDescription)")
        }

        static func couldNotSaveModSet(_ errorDescription: String) -> String {
            String(localized: "Could not save mod set: \(errorDescription)")
        }

        static func couldNotUpdateMod(_ modName: String, errorDescription: String) -> String {
            String(localized: "Could not update \(modName): \(errorDescription)")
        }

        static func couldNotWatchModsFolder(_ errorDescription: String) -> String {
            String(localized: "Could not watch Mods folder: \(errorDescription)")
        }

        static let couldNotApplySetSelectionMissing = String(localized: "Could not apply set: selection is missing.")
        static func prunedExpiredArchives(count: Int) -> String {
            String(localized: "Pruned \(count) expired archive folders.")
        }

        static func createdModFolder(_ path: String) -> String {
            String(localized: "Created \(path).")
        }

        static func createdModSet(_ setName: String) -> String {
            String(localized: "Created mod set \(setName).")
        }

        static func deletedModArchived(_ modName: String) -> String {
            String(localized: "Deleted \(modName). Archived a restorable copy.")
        }

        static func deletedModSet(_ setName: String) -> String {
            String(localized: "Deleted mod set \(setName).")
        }

        static func deletedModSetAppliedDefault(_ setName: String, changedCount: Int) -> String {
            String(localized: "Deleted mod set \(setName). Applied Default (\(changedCount) changes).")
        }

        static func deletedModSetChooseFolderAgainToApplyDefault(_ setName: String) -> String {
            String(localized: "Deleted mod set \(setName). Choose the Mods folder again to apply Default.")
        }

        static func deletedModSetCouldNotApplyDefault(_ setName: String, errorDescription: String) -> String {
            String(localized: "Deleted mod set \(setName), but could not apply Default: \(errorDescription)")
        }

        static func duplicatedSelectedMod(_ displayName: String) -> String {
            String(localized: "Skipped \(displayName) because it was duplicated in the selected sources.")
        }

        static func enabledMod(_ modName: String) -> String {
            String(localized: "Enabled \(modName).")
        }

        static func disabledMod(_ modName: String) -> String {
            String(localized: "Disabled \(modName).")
        }

        static func renamedSet(to setName: String) -> String {
            String(localized: "Renamed set to \(setName).")
        }

        static func restoredArchivedMods(count: Int) -> String {
            String(localized: "Restored \(count) archived mods.")
        }

        static func restoredMod(_ modName: String) -> String {
            String(localized: "Restored \(modName).")
        }

        static func restoredModArchivedCurrent(_ modName: String) -> String {
            String(localized: "Restored \(modName). Archived current copy.")
        }

        static func noPreviousVersionAvailable(_ modName: String) -> String {
            String(localized: "No previous version of \(modName) is available.")
        }

        static func selectedFolder(_ path: String) -> String {
            String(localized: "Selected \(path).")
        }

        static func skippedAlreadyInstalledMods(count: Int) -> String {
            String(localized: "Skipped \(count) already installed mods.")
        }

        static func skippedDuplicatedSelectedMods(count: Int) -> String {
            String(localized: "Skipped \(count) duplicated selected mods.")
        }

        static func replacedMod(
            _ displayName: String,
            previousVersion: String?,
            installedVersion: String?,
            replacementKind: ModReplacementKind
        ) -> String {
            switch replacementKind {
            case .update:
                switch (previousVersion, installedVersion) {
                case (.some(let previousVersion), .some(let installedVersion)):
                    return String(localized: "Updated \(displayName) from \(previousVersion) to \(installedVersion). Archived previous copy.")
                case (.none, .some(let installedVersion)):
                    return String(localized: "Updated \(displayName) to \(installedVersion). Archived previous copy.")
                default:
                    return String(localized: "Updated \(displayName). Archived previous copy.")
                }
            case .reinstall:
                if let installedVersion {
                    return String(localized: "Reinstalled \(displayName) \(installedVersion). Archived previous copy.")
                }
                return String(localized: "Reinstalled \(displayName). Archived previous copy.")
            case .downgrade:
                switch (previousVersion, installedVersion) {
                case (.some(let previousVersion), .some(let installedVersion)):
                    return String(localized: "Downgraded \(displayName) from \(previousVersion) to \(installedVersion). Archived previous copy.")
                case (.none, .some(let installedVersion)):
                    return String(localized: "Downgraded \(displayName) to \(installedVersion). Archived previous copy.")
                default:
                    return String(localized: "Downgraded \(displayName). Archived previous copy.")
                }
            case .replace:
                return String(localized: "Replaced \(displayName). Archived previous copy.")
            }
        }

        static func updatedModFolders(count: Int) -> String {
            String(localized: "Updated \(count) mod folders.")
        }

        static func updatedModSet(_ setName: String) -> String {
            String(localized: "Updated \(setName).")
        }

        static func updatedModSet(after changeMessage: String, setName: String) -> String {
            String(localized: "\(changeMessage) Updated \(setName).")
        }
    }

    enum ImportPreview {
        static let actionColumn = String(localized: "Action")
        static let detailsColumn = String(localized: "Details")
        static let cancel = String(localized: "Cancel")
        static let downgrade = String(localized: "Downgrade")
        static let duplicate = String(localized: "Duplicate")
        static let duplicateSelection = String(localized: "Another selected item already installs this mod.")
        static let install = String(localized: "Install")
        static let installAction = String(localized: "Install")
        static let installedVersionColumn = String(localized: "Installed")
        static let modColumn = String(localized: "Mod")
        static let reinstall = String(localized: "Reinstall")
        static let replace = String(localized: "Replace")
        static let restoreNote = String(localized: "Existing mods will be archived first, so you can restore the previous version if needed.")
        static let selectedVersionColumn = String(localized: "Selected")
        static let skip = String(localized: "Skip")
        static let title = String(localized: "Review Mods")
        static let typeColumn = String(localized: "Type")
        static let update = String(localized: "Update")

        static func summary(itemCount: Int, installableCount: Int) -> String {
            String(localized: "\(itemCount) mods found. \(installableCount) will be installed or replaced.")
        }

        static func alreadyInstalled(_ folderName: String) -> String {
            String(localized: "Already installed as \(folderName).")
        }

        static func willDowngrade(_ folderName: String) -> String {
            String(localized: "Will archive and downgrade \(folderName).")
        }

        static func willInstall(_ folderName: String) -> String {
            String(localized: "Will install as \(folderName).")
        }

        static func willReinstall(_ folderName: String) -> String {
            String(localized: "Will archive and reinstall \(folderName).")
        }

        static func willReplace(_ folderName: String) -> String {
            String(localized: "Will archive and replace \(folderName).")
        }

        static func willUpdate(_ folderName: String) -> String {
            String(localized: "Will archive and update \(folderName).")
        }
    }

    enum ModInspector {
        static let archived = String(localized: "Archived")
        static let archiveSection = String(localized: "Archive")
        static let archivedMods = String(localized: "Archived Mods")
        static let archiveSize = String(localized: "Archive Size")
        static let author = String(localized: "Author")
        static let dependenciesSection = String(localized: "Dependencies")
        static let detailsSection = String(localized: "Details")
        static let disabled = String(localized: "Disabled")
        static let duplicatesSection = String(localized: "Duplicates")
        static let entryDll = String(localized: "Entry DLL")
        static let folder = String(localized: "Folder")
        static let minimumApiVersion = String(localized: "Minimum SMAPI")
        static let missing = String(localized: "Missing")
        static let noDependencies = String(localized: "No dependencies.")
        static let noDependents = String(localized: "No enabled mods require this mod.")
        static let noPreviousVersion = String(localized: "No previous version is archived.")
        static let optionalDependency = String(localized: "Optional")
        static let previousVersion = String(localized: "Previous Version")
        static let pruneExpiredArchives = String(localized: "Prune Expired Archives")
        static let requiredBySection = String(localized: "Required By")
        static let requiredDependency = String(localized: "Required")
        static let restorePreviousVersion = String(localized: "Restore Previous Version")
        static let reveal = String(localized: "Reveal")
        static let satisfied = String(localized: "Satisfied")
        static let state = String(localized: "State")
        static let type = String(localized: "Type")
        static let uniqueID = String(localized: "Unique ID")
        static let updateKeys = String(localized: "Update Keys")
        static let updateSource = String(localized: "Update Source")
        static let versionTooOld = String(localized: "Version too old")

        static func installedVersion(_ version: String) -> String {
            String(localized: "Installed \(version)")
        }

        static func minimumVersion(_ version: String) -> String {
            String(localized: "Requires \(version)+")
        }
    }

    enum ModSetComparison {
        static let changeColumn = String(localized: "Change")
        static let close = String(localized: "Close")
        static let disable = String(localized: "Disable")
        static let enable = String(localized: "Enable")
        static let modColumn = String(localized: "Mod")
        static let noChanges = String(localized: "No changes")
        static let typeColumn = String(localized: "Type")
        static let versionColumn = String(localized: "Version")

        static func summary(enableCount: Int, disableCount: Int) -> String {
            String(localized: "\(enableCount) mods will be enabled. \(disableCount) mods will be disabled.")
        }

        static func title(_ setName: String) -> String {
            String(localized: "Compare \(setName)")
        }
    }

    enum SourceCleanup {
        static let fileNoLongerExists = String(localized: "File no longer exists.")
        static let keepFiles = String(localized: "Keep Files")
        static let modsAddedTitle = String(localized: "Mods Added")
        static let moveOriginalFilesToTrashTitle = String(localized: "Move Original Files to Trash?")
        static let moveToTrash = String(localized: "Move to Trash")
        static let ok = String(localized: "OK")
        static let rememberChoice = String(localized: "Remember my choice")

        static func selectedItemText(count: Int) -> String {
            String(localized: "\(count) original selected items")
        }

        static func moveSelectedItemsQuestion(count: Int) -> String {
            String(localized: "Move \(count) original selected items to the Trash?")
        }

        static func couldNotMoveOriginalFilesToTrash(count: Int) -> String {
            String(localized: "Could not move \(count) original files to the Trash.")
        }

        static func movedOriginalFilesToTrash(movedCount: Int, failedCount: Int) -> String {
            if failedCount == 0 {
                return String(localized: "Moved \(movedCount) original files to the Trash.")
            }

            switch (movedCount, failedCount) {
            case (1, 1):
                return String(localized: "Moved 1 original file to the Trash. Could not move 1 original file.")
            case (1, _):
                return String(localized: "Moved 1 original file to the Trash. Could not move \(failedCount) original files.")
            case (_, 1):
                return String(localized: "Moved \(movedCount) original files to the Trash. Could not move 1 original file.")
            default:
                return String(localized: "Moved \(movedCount) original files to the Trash. Could not move \(failedCount) original files.")
            }
        }
    }

    enum Problems {
        static let dependenciesSection = String(localized: "Dependencies")
        static let duplicatesSection = String(localized: "Duplicates")
        static let invalidFoldersSection = String(localized: "Invalid Folders")
        static let missingManifest = String(localized: "No manifest.json was found in this folder.")
        static let noProblems = String(localized: "No problems")
        static let title = String(localized: "Problems")
    }

    enum Activity {
        static let actionColumn = String(localized: "Action")
        static let summaryColumn = String(localized: "Summary")
        static let timeColumn = String(localized: "Time")
        static let title = String(localized: "Activity")
    }

    enum AuditActions {
        static let archivesPruned = String(localized: "Archives Pruned")
        static let modDeleted = String(localized: "Mod Deleted")
        static let modDisabled = String(localized: "Mod Disabled")
        static let modEnabled = String(localized: "Mod Enabled")
        static let modMovedToTrash = String(localized: "Mod Moved to Trash")
        static let modRestored = String(localized: "Mod Restored")
        static let modSetApplied = String(localized: "Mod Set Applied")
        static let modSetCreated = String(localized: "Mod Set Created")
        static let modSetDeleted = String(localized: "Mod Set Deleted")
        static let modSetRenamed = String(localized: "Mod Set Renamed")
        static let modsAdded = String(localized: "Mods Added")
        static let modsFolderCreated = String(localized: "Mods Folder Created")
        static let modsFolderSelected = String(localized: "Mods Folder Selected")
        static let modsInstallSkipped = String(localized: "Mods Install Skipped")
        static let modsUpdated = String(localized: "Mods Updated")
        static let sourceFilesMovedToTrash = String(localized: "Source Files Moved to Trash")
    }

    enum Errors {
        static let cannotDeleteIncludedSets = String(localized: "Included mod sets cannot be deleted.")
        static let cannotEditIncludedSets = String(localized: "Included mod sets cannot be edited.")
        static let noSavedFolderAccess = String(localized: "No saved folder access was found.")
        static let ready = String(localized: "Ready")
        static let needsSetup = String(localized: "Needs setup")
        static let seedBoxManagesDefaultModsFolder = String(localized: "Seed Box manages the default Mods folder.")

        static func disabledFolderNameCannotBeEnabled(_ name: String) -> String {
            String(localized: "The disabled folder name \(name) cannot be enabled safely.")
        }

        static func duplicateModSetName(_ name: String) -> String {
            String(localized: "A mod set named \(name) already exists.")
        }

        static func modAlreadyExists(at path: String) -> String {
            String(localized: "A mod already exists at \(path).")
        }

        static func modAlreadyInstalled(folderName: String, path: String) -> String {
            String(localized: "\(folderName) is already installed at \(path).")
        }

        static func modFolderDoesNotExist(at path: String) -> String {
            String(localized: "The mod folder does not exist at \(path).")
        }

        static func modSetNotFound(_ id: String) -> String {
            String(localized: "Mod set \(id) was not found.")
        }

        static func noInstallableMods(at path: String) -> String {
            String(localized: "No installable mod folders were found in \(path).")
        }

        static func savedFolderAccessCouldNotBeRestored(_ reason: String) -> String {
            String(localized: "Saved folder access could not be restored: \(reason)")
        }

        static func couldNotWatch(_ path: String, reason: String) -> String {
            String(localized: "Could not watch \(path): \(reason)")
        }
    }

    enum Notifications {
        static let modsFolderChangedTitle = String(localized: "Mods Folder Changed")
        static let modsFolderChangedBody = String(localized: "Seed Box refreshed the mod list.")
    }

    enum Audit {
        static let createdModsFolder = String(localized: "Created Mods folder.")
        static let selectedModsFolder = String(localized: "Selected Mods folder.")
    }
}

struct ModManagerActions {
    var chooseModsFolder: () -> Void
    var addMods: () -> Void
    var refresh: () -> Void
    var showProblems: () -> Void
    var showActivity: () -> Void
    var showRestoreHistory: () -> Void
    var showModInspector: () -> Void
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var compareSelectedModSet: () -> Void
    var revealModsFolder: () -> Void
    var revealArchivedModsFolder: () -> Void
    var pruneExpiredArchives: () -> Void
    var restorePreviousVersion: () -> Void
    var revealSelectedMod: () -> Void
    var deleteSelectedMod: () -> Void
}

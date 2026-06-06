import SwiftUI

struct ModManagerViewPresentation {
    var sheet: ModManagerSheet?
    var alert: ModManagerAlert?
    var isAddingMods = false
    var isChoosingModsFolder = false
    var isDropTargeted = false
    var remembersSourceCleanupChoice = false
    var isShowingModInspector = false

    mutating func dismissAlert() {
        alert = nil
    }

    mutating func dismissSheet() {
        sheet = nil
    }

    mutating func resetSourceCleanupChoice() {
        remembersSourceCleanupChoice = false
    }
}

enum ModManagerSheet: Identifiable {
    case modSetEditor(ModSetEditorMode)
    case importPreview(ModImportPreview)
    case sourceCleanup(SourceCleanupOffer)
    case problems
    case activity
    case modSetComparison(ModSetComparison)

    var id: String {
        switch self {
        case .modSetEditor(let mode):
            return "mod-set-editor-\(mode.id)"
        case .importPreview(let preview):
            return "import-preview-\(preview.id)"
        case .sourceCleanup(let offer):
            return "source-cleanup-\(offer.id)"
        case .problems:
            return "problems"
        case .activity:
            return "activity"
        case .modSetComparison(let comparison):
            return "mod-set-comparison-\(comparison.id)"
        }
    }
}

enum ModManagerAlert: Identifiable {
    case deleteMod(ModInfo)
    case deleteModSet(ModSet)
    case dependency(DependencyConfirmation)

    var id: String {
        switch self {
        case .deleteMod(let mod):
            return "delete-mod-\(mod.id)"
        case .deleteModSet(let set):
            return "delete-mod-set-\(set.id)"
        case .dependency(let confirmation):
            return "dependency-\(confirmation.id)"
        }
    }

    var title: String {
        switch self {
        case .deleteMod:
            return AppStrings.Alerts.deleteModTitle
        case .deleteModSet:
            return AppStrings.Alerts.deleteModSetTitle
        case .dependency(let confirmation):
            return confirmation.title
        }
    }
}

struct DependencyConfirmation: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var confirmRole: ButtonRole?
    var action: DependencyConfirmationAction
    var repairTitle: String?
    var repairRole: ButtonRole?
    var repairAction: DependencyConfirmationAction?

    init(
        title: String,
        message: String,
        confirmTitle: String,
        confirmRole: ButtonRole?,
        action: DependencyConfirmationAction,
        repairTitle: String? = nil,
        repairRole: ButtonRole? = nil,
        repairAction: DependencyConfirmationAction? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.confirmRole = confirmRole
        self.action = action
        self.repairTitle = repairTitle
        self.repairRole = repairRole
        self.repairAction = repairAction
    }
}

enum DependencyConfirmationAction {
    case setMod(ModInfo, enabled: Bool)
    case setMods([ModInfo], enabled: Bool)
    case selectModSet(String)
}

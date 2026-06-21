import Foundation

enum SeedBoxRoute: Hashable, Sendable {
    case library
    case problems
    case warnings
    case errors
    case activity
    case restoreHistory
    case smartModSet(SmartModSet)
    case modSet(id: String)
    case mod(id: String)
}

struct SeedBoxRouteDispatcher {
    var state: ModManagerState

    @discardableResult
    func dispatch(
        _ route: SeedBoxRoute,
        presentation: inout ModManagerViewPresentation,
        selectedLibraryItemID: inout String,
        selectedModIDs: inout Set<String>
    ) -> SeedBoxRouteDispatchResult {
        switch route {
        case .library:
            selectedLibraryItemID = ModLibrarySelection.resolvedID(selectedLibraryItemID, in: state)
            selectedModIDs = []
            presentation.dismissSheet()
            return .handled
        case .problems:
            presentation.sheet = .problems
            return .handled
        case .warnings:
            return dispatch(
                .smartModSet(.warnings),
                presentation: &presentation,
                selectedLibraryItemID: &selectedLibraryItemID,
                selectedModIDs: &selectedModIDs
            )
        case .errors:
            return dispatch(
                .smartModSet(.errors),
                presentation: &presentation,
                selectedLibraryItemID: &selectedLibraryItemID,
                selectedModIDs: &selectedModIDs
            )
        case .activity:
            presentation.sheet = .activity
            return .handled
        case .restoreHistory:
            presentation.sheet = .restoreHistory
            return .handled
        case .smartModSet(let smartSet):
            selectedLibraryItemID = ModLibrarySelection.smartID(smartSet)
            selectedModIDs = []
            presentation.dismissSheet()
            return .handled
        case .modSet(let id):
            guard state.modSets.contains(where: { $0.id == id }) else {
                return .unavailable
            }
            selectedLibraryItemID = ModLibrarySelection.modSetID(id)
            selectedModIDs = []
            presentation.dismissSheet()
            return .handled
        case .mod(let id):
            guard let mod = state.mods.first(where: { $0.id == id }) else {
                return .unavailable
            }

            let currentSelection = ModLibrarySelection(
                id: ModLibrarySelection.resolvedID(selectedLibraryItemID, in: state)
            )
            if !currentSelection.includes(mod, in: state) {
                selectedLibraryItemID = ModLibrarySelection.smartID(.allMods)
            }

            selectedModIDs = [mod.id]
            presentation.dismissSheet()
            return .handled
        }
    }
}

enum SeedBoxRouteDispatchResult: Equatable, Sendable {
    case handled
    case unavailable
}

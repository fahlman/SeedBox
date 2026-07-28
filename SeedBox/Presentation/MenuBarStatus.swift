import Foundation

/// A concise, safe snapshot of Seed Box state for the menu bar companion,
/// derived from ``ModManagerState`` without duplicating any business logic.
/// Carries only counts and the selected set name — never paths or diagnostics.
struct MenuBarStatus: Equatable, Sendable {
    var hasFolderAccess: Bool
    var selectedSetName: String?
    var warningsCount: Int
    var errorsCount: Int
    var updatesCount: Int
    var hasLastSessionIssues: Bool
    var checksForUpdates: Bool

    var hasWarnings: Bool { warningsCount > 0 }
    var hasErrors: Bool { errorsCount > 0 }
    var hasUpdates: Bool { updatesCount > 0 }

    static func make(from state: ModManagerState) -> MenuBarStatus {
        MenuBarStatus(
            hasFolderAccess: state.hasSavedFolderAccess,
            selectedSetName: state.modSetSelection.selectedSet?.name,
            warningsCount: ModFilterEngine.count(for: .warnings, in: state),
            errorsCount: ModFilterEngine.count(for: .errors, in: state),
            updatesCount: updatesCount(in: state),
            hasLastSessionIssues: !state.lastSessionIssues.isEmpty,
            checksForUpdates: state.checksForModUpdates
        )
    }

    private static func updatesCount(in state: ModManagerState) -> Int {
        guard state.checksForModUpdates else {
            return 0
        }
        var count = state.mods.filter { state.availableUpdate(for: $0) != nil }.count
        if state.smapiUpdate != nil {
            count += 1
        }
        return count
    }
}

import Foundation

struct ModTableRow: Identifiable {
    var mod: ModInfo
    var availableUpdate: ModAvailableUpdate?

    var id: String {
        mod.id
    }

    var enabledText: String {
        mod.stateText
    }

    var enabledSortText: String {
        mod.isEnabled ? "0 Enabled" : "1 Disabled"
    }

    var nameSortText: String {
        "\(mod.displayName) \(mod.versionText)"
    }

    var authorText: String {
        mod.authorText
    }

    var typeText: String {
        mod.typeText
    }

    var updateSourceText: String {
        mod.updateSourceText
    }

    /// Sorts mods with available updates first within the Updates column.
    var updateSortText: String {
        if let availableUpdate {
            return "0 \(availableUpdate.latestVersion)"
        }
        return "1 \(mod.updateSourceText)"
    }
}

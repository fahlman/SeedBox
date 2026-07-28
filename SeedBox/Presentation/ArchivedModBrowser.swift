import Foundation

enum ArchivedModReasonFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case deleted
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            AppStrings.RestoreHistory.allArchives
        case .deleted:
            AppStrings.RestoreHistory.deleted
        case .updated:
            AppStrings.RestoreHistory.updated
        }
    }

    func includes(_ archivedMod: ArchivedModInfo) -> Bool {
        switch self {
        case .all:
            return true
        case .deleted:
            return archivedMod.reason == .deleted
        case .updated:
            return archivedMod.reason == .updated
        }
    }
}

enum ArchivedModBrowser {
    static func filteredArchivedMods(
        _ archivedMods: [ArchivedModInfo],
        searchText: String,
        reasonFilter: ArchivedModReasonFilter
    ) -> [ArchivedModInfo] {
        let terms = searchText
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }

        return archivedMods.filter { archivedMod in
            guard reasonFilter.includes(archivedMod) else {
                return false
            }

            guard !terms.isEmpty else {
                return true
            }

            let searchableText = [
                archivedMod.displayName,
                archivedMod.versionText,
                archivedMod.folderName,
                archivedMod.manifest?.uniqueID,
                archivedMod.manifest?.author,
                archivedMod.reason?.archiveBrowserDisplayText
            ]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()

            return terms.allSatisfy { searchableText.contains($0) }
        }
    }
}

extension ModArchiveReason {
    var archiveBrowserDisplayText: String {
        switch self {
        case .deleted:
            return AppStrings.RestoreHistory.deleted
        case .updated:
            return AppStrings.RestoreHistory.updated
        }
    }
}

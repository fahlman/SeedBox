import Foundation

extension ModManagerService {
    func restoreSummary(for restoreResults: [RestoredModResult]) -> String {
        if restoreResults.count == 1,
           let result = restoreResults.first {
            if result.archivedCurrentURL != nil {
                return AppStrings.Status.restoredModArchivedCurrent(result.displayName)
            }

            return AppStrings.Status.restoredMod(result.displayName)
        }

        return AppStrings.Status.restoredArchivedMods(count: restoreResults.count)
    }

    func restoreDetails(for restoreResults: [RestoredModResult]) -> [String: String] {
        [
            "restored_count": "\(restoreResults.count)",
            "source_paths": restoreResults.map(\.sourceURL.path).joined(separator: "\n"),
            "destination_paths": restoreResults.map(\.destinationURL.path).joined(separator: "\n"),
            "replaced_archive_paths": restoreResults.compactMap(\.archivedCurrentURL?.path).joined(separator: "\n"),
            "versions": restoreResults.map { result in
                "\(result.displayName): \(result.version ?? "unknown")"
            }
            .joined(separator: "\n")
        ]
    }
}

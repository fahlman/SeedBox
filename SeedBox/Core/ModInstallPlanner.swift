import Foundation

enum ModInstallIdentity: Hashable {
    case uniqueID(String)
    case folderToken(String)
}

enum ModInstallPlanner {
    static func destinationFolderName(
        for sourceFolderName: String,
        enabled: Bool
    ) -> String {
        let enabledFolderName = sourceFolderName.trimmingPrefix(Character("."))
        return enabled ? enabledFolderName : ".\(enabledFolderName)"
    }

    static func identity(for candidate: ModInstallCandidate) -> ModInstallIdentity? {
        guard let uniqueID = candidate.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
              !uniqueID.isEmpty
        else {
            return nil
        }

        return .uniqueID(uniqueID)
    }

    static func shouldReplace(
        candidate: ModInstallCandidate,
        existingMod: InstalledModLocation,
        policy: ModInstallReplacementPolicy
    ) -> Bool {
        guard policy == .newerOnly else {
            return true
        }

        guard let candidateVersion = candidate.manifest?.version?.trimmedNonEmpty,
              let existingVersion = existingMod.version
        else {
            return false
        }

        return ModVersionComparator.compare(candidateVersion, to: existingVersion) == .orderedDescending
    }

    static func previewAction(
        candidate: ModInstallCandidate,
        existingMod: InstalledModLocation
    ) -> ModImportPreviewAction {
        guard let candidateVersion = candidate.manifest?.version?.trimmedNonEmpty,
              let existingVersion = existingMod.version
        else {
            return .replace
        }

        switch ModVersionComparator.compare(candidateVersion, to: existingVersion) {
        case .orderedDescending:
            return .update
        case .orderedAscending:
            return .downgrade
        case .orderedSame:
            return .reinstall
        }
    }

    static func replacementKind(
        candidate: ModInstallCandidate,
        existingMod: InstalledModLocation
    ) -> ModReplacementKind {
        previewAction(candidate: candidate, existingMod: existingMod).replacementKind ?? .replace
    }

    static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func skippedResult(
        for candidate: ModInstallCandidate,
        existingMod: InstalledModLocation,
        reason: SkippedModInstallReason
    ) -> SkippedModInstallResult {
        skippedResult(
            for: candidate,
            existingURL: existingMod.url,
            existingVersion: existingMod.version,
            fallbackName: existingMod.displayName,
            reason: reason
        )
    }

    static func skippedResult(
        for candidate: ModInstallCandidate,
        existingURL: URL?,
        existingVersion: String? = nil,
        fallbackName: String? = nil,
        reason: SkippedModInstallReason
    ) -> SkippedModInstallResult {
        SkippedModInstallResult(
            sourceURL: candidate.sourceURL,
            existingURL: existingURL,
            displayName: displayName(for: candidate, fallback: fallbackName),
            selectedVersion: candidate.manifest?.version?.trimmedNonEmpty,
            existingVersion: existingVersion,
            reason: reason
        )
    }

    static func displayName(
        for candidate: ModInstallCandidate,
        fallback: String? = nil
    ) -> String {
        candidate.manifest?.name?.trimmedNonEmpty
            ?? fallback
            ?? candidate.destinationFolderName.trimmingPrefix(Character("."))
    }

    static func typeText(for manifest: ModManifest?) -> String {
        guard let manifest else {
            return AppStrings.Mods.unknown
        }

        if manifest.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame {
            return AppStrings.Mods.contentPatcher
        }

        return AppStrings.Mods.smapi
    }
}

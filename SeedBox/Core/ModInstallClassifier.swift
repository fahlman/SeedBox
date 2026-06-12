import Foundation

/// How a single install candidate relates to the Mods folder and to the other
/// candidates in the same selection.
struct ClassifiedInstallCandidate {
    enum Resolution {
        /// Nothing stands in the way; install to this destination.
        case install(destinationURL: URL)
        /// A different copy of this mod is installed; replacement policy
        /// decides whether it is replaced or skipped.
        case existingDiffers(InstalledModLocation)
        /// The candidate is the installed copy itself.
        case alreadyInstalledSameSource(InstalledModLocation)
        /// A folder with the same normalized name exists but wasn't matched
        /// as a mod by unique ID.
        case alreadyInstalledByFolderName(URL)
        /// An earlier candidate in the same selection claims this mod.
        case duplicateInSelection(pendingURL: URL?)
    }

    var candidate: ModInstallCandidate
    var destinationFolderName: String
    var resolution: Resolution
}

/// The single decision tree shared by `installMods` and `previewImport`, so a
/// preview always describes exactly what an install would do.
struct ModInstallClassifier {
    private let modDirectoryURL: URL
    private let enabled: Bool
    private let installedMods: [InstalledModLocation]
    private let existingModURLsByToken: [String: URL]
    private let fileManager: FileManager
    private var pendingIdentities: Set<ModInstallIdentity> = []
    private var pendingDestinationURLsByToken: [String: URL] = [:]

    init(install: StardewInstall, enabled: Bool, fileManager: FileManager) {
        modDirectoryURL = install.modDirectoryURL
        self.enabled = enabled
        self.fileManager = fileManager
        installedMods = ModInstalledCatalog.locations(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )
        existingModURLsByToken = ModInstalledCatalog.urlsByToken(for: installedMods)
    }

    mutating func classify(_ candidate: ModInstallCandidate) throws -> ClassifiedInstallCandidate {
        let destinationFolderName = ModInstallPlanner.destinationFolderName(
            for: candidate.destinationFolderName,
            enabled: enabled
        )
        let folderName = destinationFolderName.trimmingPrefix(Character("."))
        guard !folderName.isEmpty else {
            throw ModLibraryError.invalidDisabledName(candidate.destinationFolderName)
        }

        let destinationToken = folderName.normalizedFolderToken
        let resolution = try resolve(
            candidate,
            operationIdentity: ModInstallPlanner.identity(for: candidate) ?? .folderToken(destinationToken),
            destinationToken: destinationToken,
            destinationURL: modDirectoryURL.appendingPathComponent(destinationFolderName)
        )

        return ClassifiedInstallCandidate(
            candidate: candidate,
            destinationFolderName: destinationFolderName,
            resolution: resolution
        )
    }

    private mutating func resolve(
        _ candidate: ModInstallCandidate,
        operationIdentity: ModInstallIdentity,
        destinationToken: String,
        destinationURL: URL
    ) throws -> ClassifiedInstallCandidate.Resolution {
        if pendingIdentities.contains(operationIdentity)
            || pendingDestinationURLsByToken[destinationToken] != nil {
            return .duplicateInSelection(
                pendingURL: pendingDestinationURLsByToken[destinationToken]
            )
        }

        if let existingMod = ModInstalledCatalog.matchingInstalledMod(
            normalizedUniqueID: candidate.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
            destinationToken: destinationToken,
            installedMods: installedMods
        ) {
            pendingIdentities.insert(operationIdentity)
            if ModInstallPlanner.sameFileURL(candidate.sourceURL, existingMod.url) {
                return .alreadyInstalledSameSource(existingMod)
            }
            return .existingDiffers(existingMod)
        }

        if fileManager.fileExists(atPath: destinationURL.path),
           !fileManager.directoryExists(at: destinationURL) {
            throw ModLibraryError.destinationExists(destinationURL)
        }

        if let existingURL = existingModURLsByToken[destinationToken] {
            pendingIdentities.insert(operationIdentity)
            return .alreadyInstalledByFolderName(existingURL)
        }

        pendingIdentities.insert(operationIdentity)
        pendingDestinationURLsByToken[destinationToken] = destinationURL
        return .install(destinationURL: destinationURL)
    }
}

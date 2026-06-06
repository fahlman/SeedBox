import Foundation

struct InstalledModResult: Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
    var displayName: String
    var version: String?
}

struct UpdatedModResult: Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
    var archivedURL: URL
    var displayName: String
    var previousVersion: String?
    var installedVersion: String?
    var replacementKind: ModReplacementKind
}

struct RestoredModResult: Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
    var archivedCurrentURL: URL?
    var displayName: String
    var version: String?
}

struct SkippedModInstallResult: Equatable, Sendable {
    var sourceURL: URL
    var existingURL: URL?
    var displayName: String
    var selectedVersion: String?
    var existingVersion: String?
    var reason: SkippedModInstallReason
}

enum SkippedModInstallReason: Equatable, Sendable {
    case alreadyInstalled
    case duplicateInSelection
}

enum ModReplacementKind: Equatable, Sendable {
    case update
    case reinstall
    case downgrade
    case replace
}

enum ModInstallReplacementPolicy: Equatable, Sendable {
    case newerOnly
    case replaceExisting
}

struct ModInstallResult: Equatable, Sendable {
    var installed: [InstalledModResult] = []
    var updated: [UpdatedModResult] = []
    var skipped: [SkippedModInstallResult] = []

    var installedURLs: [URL] {
        installed.map(\.destinationURL) + updated.map(\.destinationURL)
    }

    var didChangeInstalledMods: Bool {
        !installed.isEmpty || !updated.isEmpty
    }
}

struct ModImportPreview: Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourceURLs: [URL]
    var items: [ModImportPreviewItem]
    var temporaryExtractionDirectories: [URL] = []

    var installableItems: [ModImportPreviewItem] {
        items.filter(\.action.isInstallable)
    }

    var canInstall: Bool {
        !installableItems.isEmpty
    }
}

struct ModImportPreviewItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourceURL: URL
    var displayName: String
    var selectedVersion: String?
    var existingVersion: String?
    var destinationFolderName: String
    var existingFolderName: String?
    var action: ModImportPreviewAction
    var typeText: String

    var selectedVersionText: String {
        selectedVersion ?? AppStrings.Mods.unknownVersion
    }

    var existingVersionText: String {
        existingVersion ?? AppStrings.Mods.notInstalled
    }
}

enum ModImportPreviewAction: Equatable, Sendable {
    case install
    case update
    case reinstall
    case downgrade
    case replace
    case alreadyInstalled
    case duplicateInSelection

    var isInstallable: Bool {
        switch self {
        case .install, .update, .reinstall, .downgrade, .replace:
            return true
        case .alreadyInstalled, .duplicateInSelection:
            return false
        }
    }

    var replacementKind: ModReplacementKind? {
        switch self {
        case .update:
            return .update
        case .reinstall:
            return .reinstall
        case .downgrade:
            return .downgrade
        case .replace:
            return .replace
        case .install, .alreadyInstalled, .duplicateInSelection:
            return nil
        }
    }
}

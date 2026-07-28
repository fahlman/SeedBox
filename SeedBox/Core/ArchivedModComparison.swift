import Foundation

/// A field-level comparison between an archived mod version and the currently
/// installed version of the same mod.
///
/// Restore History uses this to make the consequences of restoring clear before
/// any files change: what differs, and whether the archived copy is older or
/// newer than what is installed. It reads only manifest metadata, never config
/// contents.
struct ArchivedModComparison: Equatable, Sendable {
    enum InstallStatus: Equatable, Sendable {
        case notInstalled
        case installed
    }

    /// How the archived version relates to the installed version. `.unknown`
    /// when nothing is installed to compare against or either version string is
    /// missing or unparseable.
    enum VersionRelation: Equatable, Sendable {
        case unknown
        case archivedIsOlder
        case archivedIsNewer
        case same
    }

    enum Field: String, Equatable, Sendable, CaseIterable {
        case name
        case version
        case uniqueID
        case updateKeys
        case dependencies
        case contentPackFor
    }

    struct FieldComparison: Equatable, Sendable {
        var field: Field
        var archivedValue: String?
        var installedValue: String?

        var isDifferent: Bool {
            archivedValue != installedValue
        }
    }

    var archivedDisplayName: String
    var installStatus: InstallStatus
    var versionRelation: VersionRelation
    var fields: [FieldComparison]

    /// The currently installed mod the archive was matched against, if any.
    var installedFolderName: String?

    /// Field comparisons that actually differ between the two versions.
    var differences: [FieldComparison] {
        fields.filter(\.isDifferent)
    }

    /// Whether a meaningful comparison is available with at least one change.
    var hasDifferences: Bool {
        installStatus == .installed && !differences.isEmpty
    }

    static func compare(
        _ archived: ArchivedModInfo,
        against installedMods: [ModInfo]
    ) -> ArchivedModComparison {
        let installed = ModArchive.currentMod(for: archived, in: installedMods)
        let fields = Field.allCases.map { field in
            FieldComparison(
                field: field,
                archivedValue: value(of: field, in: archived.manifest),
                installedValue: installed.flatMap { value(of: field, in: $0.manifest) }
            )
        }

        return ArchivedModComparison(
            archivedDisplayName: archived.displayName,
            installStatus: installed == nil ? .notInstalled : .installed,
            versionRelation: versionRelation(archived: archived, installed: installed),
            fields: fields,
            installedFolderName: installed?.enabledFolderName
        )
    }

    private static func versionRelation(
        archived: ArchivedModInfo,
        installed: ModInfo?
    ) -> VersionRelation {
        guard
            let installed,
            let archivedVersion = archived.manifest?.version?.trimmedNonEmpty,
            let installedVersion = installed.manifest?.version?.trimmedNonEmpty
        else {
            return .unknown
        }

        switch ModVersionComparator.compare(archivedVersion, to: installedVersion) {
        case .orderedAscending:
            return .archivedIsOlder
        case .orderedDescending:
            return .archivedIsNewer
        case .orderedSame:
            return .same
        }
    }

    private static func value(of field: Field, in manifest: ModManifest?) -> String? {
        guard let manifest else {
            return nil
        }

        switch field {
        case .name:
            return manifest.name?.trimmedNonEmpty
        case .version:
            return manifest.version?.trimmedNonEmpty
        case .uniqueID:
            return manifest.uniqueID?.trimmedNonEmpty
        case .updateKeys:
            let keys = (manifest.updateKeys ?? []).compactMap(\.trimmedNonEmpty)
            return keys.isEmpty ? nil : keys.sorted().joined(separator: ", ")
        case .dependencies:
            let ids = (manifest.dependencies ?? []).compactMap { $0.uniqueID?.trimmedNonEmpty }
            return ids.isEmpty ? nil : ids.sorted().joined(separator: ", ")
        case .contentPackFor:
            return manifest.contentPackFor?.uniqueID?.trimmedNonEmpty
        }
    }
}

import Foundation

enum ModArchiveReason: String, Sendable {
    case deleted
    case updated
}

struct ArchivedModInfo: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    var url: URL
    var containerURL: URL
    var folderName: String
    var reason: ModArchiveReason?
    var archivedDate: Date?
    var manifest: ModManifest?

    var enabledFolderName: String {
        folderName.trimmingPrefix(Character("."))
    }

    var displayName: String {
        manifest?.name?.trimmedNonEmpty ?? enabledFolderName
    }

    var versionText: String {
        manifest?.version?.trimmedNonEmpty ?? AppStrings.Mods.unknownVersion
    }
}

/// Sidecar metadata written into each archive container. The container's
/// folder name carries the same information for human readers; this file is
/// the canonical machine-readable copy.
private struct ArchiveContainerInfo: Codable {
    var date: Date
    var reason: String
}

private final class CachedArchiveSummary {
    let signature: [String: Date]
    let summary: ModArchiveSummary

    init(signature: [String: Date], summary: ModArchiveSummary) {
        self.signature = signature
        self.summary = summary
    }
}

enum ModArchive {
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    static let containerInfoFileName = "Archive Info.plist"

    // NSCache is documented thread-safe. Archiving, restoring, and pruning
    // all change a container's modification date or the container list, which
    // changes the signature and invalidates the entry.
    nonisolated(unsafe) private static let summaryCache: NSCache<NSString, CachedArchiveSummary> = {
        let cache = NSCache<NSString, CachedArchiveSummary>()
        cache.countLimit = 8
        return cache
    }()

    static func archive(
        _ sourceURL: URL,
        in archiveDirectory: URL,
        reason: ModArchiveReason,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: archiveDirectory,
            withIntermediateDirectories: true
        )

        let containerURL = archiveDirectory
            .appendingPathComponent(containerName(reason: reason, date: date), isDirectory: true)
        try fileManager.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        writeContainerInfoIfMissing(
            ArchiveContainerInfo(date: date, reason: reason.rawValue),
            in: containerURL,
            fileManager: fileManager
        )

        let destinationURL = uniqueDestinationURL(
            in: containerURL,
            named: sourceURL.lastPathComponent,
            fileManager: fileManager
        )
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func pruneExpiredArchives(
        in archiveDirectory: URL,
        olderThan cutoffDate: Date = Date().addingTimeInterval(-retentionInterval),
        fileManager: FileManager = .default
    ) throws -> Int {
        guard fileManager.directoryExists(at: archiveDirectory) else {
            return 0
        }

        let archivedContainers = try fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var prunedCount = 0
        for containerURL in archivedContainers where fileManager.directoryExists(at: containerURL) {
            let values = try containerURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let archiveDate = archiveDate(for: containerURL) ?? values.creationDate ?? values.contentModificationDate
            guard let archiveDate, archiveDate < cutoffDate else {
                continue
            }

            try fileManager.removeItem(at: containerURL)
            prunedCount += 1
        }

        return prunedCount
    }

    static func archivedMods(
        in archiveDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [ArchivedModInfo] {
        guard fileManager.directoryExists(at: archiveDirectory) else {
            return []
        }

        let containers = try fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { fileManager.directoryExists(at: $0) }

        let archivedMods = containers.flatMap { containerURL -> [ArchivedModInfo] in
            let childURLs = (try? fileManager.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            return childURLs.compactMap { childURL in
                guard fileManager.directoryExists(at: childURL) else {
                    return nil
                }

                let manifestURL = childURL.appendingPathComponent("manifest.json")
                guard fileManager.fileExists(atPath: manifestURL.path) else {
                    return nil
                }

                return ArchivedModInfo(
                    url: childURL,
                    containerURL: containerURL,
                    folderName: childURL.lastPathComponent,
                    reason: archiveReason(from: containerURL),
                    archivedDate: archiveDate(for: containerURL),
                    manifest: ModManifestReader.loadManifest(at: manifestURL)
                )
            }
        }

        return archivedMods.sorted { lhs, rhs in
            switch (lhs.archivedDate, rhs.archivedDate) {
            case (.some(let lhsDate), .some(let rhsDate)) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            default:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    static func summary(
        in archiveDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> ModArchiveSummary {
        guard fileManager.directoryExists(at: archiveDirectory) else {
            return ModArchiveSummary()
        }

        // The deep byte-count walk runs on every state refresh, so it's
        // skipped whenever the shallow container signature is unchanged.
        let signature = containerSignature(in: archiveDirectory, fileManager: fileManager)
        let cacheKey = archiveDirectory.standardizedFileURL.path as NSString
        if let cached = summaryCache.object(forKey: cacheKey),
           cached.signature == signature {
            return cached.summary
        }

        let archivedMods = try archivedMods(in: archiveDirectory, fileManager: fileManager)
        let totalByteCount = try byteCount(of: archiveDirectory, fileManager: fileManager)
        let dates = archivedMods.compactMap(\.archivedDate)

        let summary = ModArchiveSummary(
            archivedModCount: archivedMods.count,
            totalByteCount: totalByteCount,
            oldestArchiveDate: dates.min(),
            newestArchiveDate: dates.max()
        )
        summaryCache.setObject(
            CachedArchiveSummary(signature: signature, summary: summary),
            forKey: cacheKey
        )
        return summary
    }

    /// A cheap shallow fingerprint of the archive: each container's name and
    /// modification date. Manual edits deep inside an archived mod won't
    /// change it, which is acceptable for display-only totals.
    private static func containerSignature(
        in archiveDirectory: URL,
        fileManager: FileManager
    ) -> [String: Date] {
        let children = (try? fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var signature: [String: Date] = [:]
        for childURL in children {
            let values = try? childURL.resourceValues(forKeys: [.contentModificationDateKey])
            signature[childURL.lastPathComponent] = values?.contentModificationDate ?? .distantPast
        }
        return signature
    }

    static func previousVersion(
        for mod: ModInfo,
        in archivedMods: [ArchivedModInfo]
    ) -> ArchivedModInfo? {
        archivedVersions(for: mod, in: archivedMods).first
    }

    static func archivedVersions(
        for mod: ModInfo,
        in archivedMods: [ArchivedModInfo]
    ) -> [ArchivedModInfo] {
        archivedMods.filter { archivedMod in
            archivedMod.matches(mod)
        }
    }

    static func currentMod(
        for archivedMod: ArchivedModInfo,
        in mods: [ModInfo]
    ) -> ModInfo? {
        mods.first { mod in
            archivedMod.matches(mod)
        }
    }

    private static func containerName(reason: ModArchiveReason, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(timestamp)-\(reason.rawValue)"
    }

    private static func writeContainerInfoIfMissing(
        _ info: ArchiveContainerInfo,
        in containerURL: URL,
        fileManager: FileManager
    ) {
        let infoURL = containerURL.appendingPathComponent(containerInfoFileName)
        guard !fileManager.fileExists(atPath: infoURL.path) else {
            return
        }

        do {
            try PropertyListEncoder().encode(info).write(to: infoURL)
        } catch {
            // The folder name still carries the metadata via the legacy parse.
            AppLog.archive.error("Couldn't write the archive metadata sidecar: \(error)")
        }
    }

    private static func containerInfo(for containerURL: URL) -> ArchiveContainerInfo? {
        let infoURL = containerURL.appendingPathComponent(containerInfoFileName)
        guard let data = try? Data(contentsOf: infoURL) else {
            // Normal for containers created before the sidecar existed.
            return nil
        }

        do {
            return try PropertyListDecoder().decode(ArchiveContainerInfo.self, from: data)
        } catch {
            AppLog.archive.error("Archive metadata sidecar exists but couldn't be decoded: \(error)")
            return nil
        }
    }

    private static func archiveReason(from containerURL: URL) -> ModArchiveReason? {
        if let info = containerInfo(for: containerURL),
           let reason = ModArchiveReason(rawValue: info.reason) {
            return reason
        }

        return legacyArchiveReason(from: containerURL)
    }

    private static func archiveDate(for containerURL: URL) -> Date? {
        if let info = containerInfo(for: containerURL) {
            return info.date
        }

        return legacyArchiveDate(for: containerURL)
    }

    // Containers created before the sidecar existed carry their metadata only
    // in the folder name.
    private static func legacyArchiveReason(from containerURL: URL) -> ModArchiveReason? {
        let suffix = containerURL.lastPathComponent.split(separator: "-").last.map(String.init)
        return suffix.flatMap(ModArchiveReason.init(rawValue:))
    }

    private static func legacyArchiveDate(for containerURL: URL) -> Date? {
        let containerName = containerURL.lastPathComponent
        guard let reason = legacyArchiveReason(from: containerURL) else {
            return nil
        }

        let suffix = "-\(reason.rawValue)"
        guard containerName.hasSuffix(suffix) else {
            return nil
        }

        let dateString = String(containerName.dropLast(suffix.count))
        let timestamp = dateString.replacingOccurrences(
            of: #"T(\d{2})-(\d{2})-(\d{2})Z"#,
            with: "T$1:$2:$3Z",
            options: .regularExpression
        )
        return ISO8601DateFormatter().date(from: timestamp)
    }

    private static func uniqueDestinationURL(
        in directoryURL: URL,
        named preferredName: String,
        fileManager: FileManager
    ) -> URL {
        let baseURL = directoryURL.appendingPathComponent(preferredName, isDirectory: true)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        for index in 2...Int.max {
            let candidateURL = directoryURL.appendingPathComponent(
                "\(preferredName) \(index)",
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent("\(preferredName) \(UUID().uuidString)", isDirectory: true)
    }

    private static func byteCount(
        of url: URL,
        fileManager: FileManager
    ) throws -> Int64 {
        var totalByteCount: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return totalByteCount
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            guard values.isRegularFile == true else {
                continue
            }

            totalByteCount += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return totalByteCount
    }
}

private extension ArchivedModInfo {
    func matches(_ mod: ModInfo) -> Bool {
        if let archivedUniqueID = manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
           let modUniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID {
            return archivedUniqueID == modUniqueID
        }

        return enabledFolderName.normalizedFolderToken == mod.enabledFolderName.normalizedFolderToken
    }
}

import Foundation
import ZIPFoundation

struct ModImportResourceUsage: Equatable, Sendable {
    var entryCount: Int
    var totalByteCount: UInt64

    mutating func add(_ other: ModImportResourceUsage) {
        let entryTotal = entryCount.addingReportingOverflow(other.entryCount)
        entryCount = entryTotal.overflow ? .max : entryTotal.partialValue

        let byteTotal = totalByteCount.addingReportingOverflow(other.totalByteCount)
        totalByteCount = byteTotal.overflow ? .max : byteTotal.partialValue
    }
}

struct ModArchiveExtractionLimits: Sendable {
    /// These limits are well above normal Stardew Valley mods while bounding
    /// the work Seed Box will do for an untrusted import.
    static let standard = ModArchiveExtractionLimits(
        maximumEntryCount: 20_000,
        maximumTotalUncompressedByteCount: 2 * 1024 * 1024 * 1024
    )

    var maximumEntryCount: Int
    var maximumTotalUncompressedByteCount: UInt64
    var minimumFreeDiskReserveByteCount: UInt64

    init(
        maximumEntryCount: Int,
        maximumTotalUncompressedByteCount: UInt64,
        minimumFreeDiskReserveByteCount: UInt64 = 512 * 1024 * 1024
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumTotalUncompressedByteCount = maximumTotalUncompressedByteCount
        self.minimumFreeDiskReserveByteCount = minimumFreeDiskReserveByteCount
    }
}

struct ModImportSelectionLimits: Sendable {
    static let standard = ModImportSelectionLimits(
        maximumSourceCount: 100,
        maximumEntryCount: 50_000,
        maximumTotalByteCount: 4 * 1024 * 1024 * 1024
    )

    var maximumSourceCount: Int
    var maximumEntryCount: Int
    var maximumTotalByteCount: UInt64
}

enum ModArchiveExtractionError: Error, Equatable, LocalizedError, Sendable {
    case tooManyEntries(URL, limit: Int)
    case expandsTooLarge(URL, limitByteCount: UInt64)
    case tooManySources(limit: Int)
    case selectionHasTooManyEntries(limit: Int)
    case selectionExpandsTooLarge(limitByteCount: UInt64)
    case unsafeArchiveEntry(URL, path: String)
    case symbolicLinkNotAllowed(URL)
    case unsupportedFileType(URL)
    case insufficientDiskSpace(URL, requiredByteCount: UInt64)

    var errorDescription: String? {
        switch self {
        case .tooManyEntries(let url, let limit):
            return AppStrings.Errors.importHasTooManyFiles(url.lastPathComponent, limit: limit)
        case .expandsTooLarge(let url, let limitByteCount):
            return AppStrings.Errors.importExpandsTooLarge(
                url.lastPathComponent,
                limitText: Self.formattedByteCount(limitByteCount)
            )
        case .tooManySources(let limit):
            return AppStrings.Errors.tooManyImportSources(limit: limit)
        case .selectionHasTooManyEntries(let limit):
            return AppStrings.Errors.importSelectionHasTooManyFiles(limit: limit)
        case .selectionExpandsTooLarge(let limitByteCount):
            return AppStrings.Errors.importSelectionExpandsTooLarge(
                limitText: Self.formattedByteCount(limitByteCount)
            )
        case .unsafeArchiveEntry(let url, let path):
            return AppStrings.Errors.archiveContainsUnsafePath(
                url.lastPathComponent,
                path: path
            )
        case .symbolicLinkNotAllowed(let url):
            return AppStrings.Errors.importContainsSymbolicLink(url.lastPathComponent)
        case .unsupportedFileType(let url):
            return AppStrings.Errors.importContainsUnsupportedFile(url.lastPathComponent)
        case .insufficientDiskSpace(let url, let requiredByteCount):
            return AppStrings.Errors.notEnoughSpaceToImport(
                url.lastPathComponent,
                requiredText: Self.formattedByteCount(requiredByteCount)
            )
        }
    }

    private static func formattedByteCount(_ byteCount: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: byteCount),
            countStyle: .file
        )
    }
}

enum ModImportSecurity {
    static let extractionDirectoryPrefix = "SeedBoxZip-"
    static let extractionMarkerFileName = ".seedbox-extraction"
    static let abandonedExtractionAge: TimeInterval = 24 * 60 * 60

    private static let maximumArchivePathByteCount = 4_096
    private static let maximumArchivePathComponentCount = 128

    static func validateImportTree(
        at rootURL: URL,
        limits: ModArchiveExtractionLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> ModImportResourceUsage {
        let rootValues = try rootURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isSymbolicLink != true else {
            throw ModArchiveExtractionError.symbolicLinkNotAllowed(rootURL)
        }
        guard rootValues.isDirectory == true else {
            throw ModArchiveExtractionError.unsupportedFileType(rootURL)
        }

        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        var enumerationError: (any Error)?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var usage = ModImportResourceUsage(entryCount: 0, totalByteCount: 0)
        while let childURL = enumerator.nextObject() as? URL {
            if let enumerationError {
                throw enumerationError
            }

            usage.entryCount += 1
            guard usage.entryCount <= limits.maximumEntryCount else {
                throw ModArchiveExtractionError.tooManyEntries(
                    rootURL,
                    limit: limits.maximumEntryCount
                )
            }

            let values = try childURL.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else {
                enumerator.skipDescendants()
                throw ModArchiveExtractionError.symbolicLinkNotAllowed(childURL)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw ModArchiveExtractionError.unsupportedFileType(childURL)
            }

            let byteCount = UInt64(max(0, values.fileSize ?? 0))
            let total = usage.totalByteCount.addingReportingOverflow(byteCount)
            usage.totalByteCount = total.overflow ? .max : total.partialValue
            guard usage.totalByteCount <= limits.maximumTotalUncompressedByteCount else {
                throw ModArchiveExtractionError.expandsTooLarge(
                    rootURL,
                    limitByteCount: limits.maximumTotalUncompressedByteCount
                )
            }
        }

        if let enumerationError {
            throw enumerationError
        }
        return usage
    }

    static func validateArchive(
        at archiveURL: URL,
        limits: ModArchiveExtractionLimits
    ) throws -> ModImportResourceUsage {
        let archiveValues = try archiveURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard archiveValues.isSymbolicLink != true else {
            throw ModArchiveExtractionError.symbolicLinkNotAllowed(archiveURL)
        }
        guard archiveValues.isRegularFile == true else {
            throw ModArchiveExtractionError.unsupportedFileType(archiveURL)
        }
        guard UInt64(max(0, archiveValues.fileSize ?? 0))
                <= limits.maximumTotalUncompressedByteCount
        else {
            throw ModArchiveExtractionError.expandsTooLarge(
                archiveURL,
                limitByteCount: limits.maximumTotalUncompressedByteCount
            )
        }

        let archive = try Archive(url: archiveURL, accessMode: .read)
        var usage = ModImportResourceUsage(entryCount: 0, totalByteCount: 0)

        for entry in archive {
            guard archiveEntryPathIsSafe(entry.path) else {
                throw ModArchiveExtractionError.unsafeArchiveEntry(
                    archiveURL,
                    path: entry.path
                )
            }
            guard entry.type != .symlink else {
                throw ModArchiveExtractionError.symbolicLinkNotAllowed(
                    URL(fileURLWithPath: entry.path)
                )
            }

            usage.entryCount += 1
            guard usage.entryCount <= limits.maximumEntryCount else {
                throw ModArchiveExtractionError.tooManyEntries(
                    archiveURL,
                    limit: limits.maximumEntryCount
                )
            }

            let total = usage.totalByteCount.addingReportingOverflow(
                entry.uncompressedSize
            )
            usage.totalByteCount = total.overflow ? .max : total.partialValue
            guard usage.totalByteCount <= limits.maximumTotalUncompressedByteCount else {
                throw ModArchiveExtractionError.expandsTooLarge(
                    archiveURL,
                    limitByteCount: limits.maximumTotalUncompressedByteCount
                )
            }
        }
        return usage
    }

    static func validateAvailableCapacity(
        for requiredContentByteCount: UInt64,
        sourceURL: URL,
        destinationDirectoryURL: URL,
        limits: ModArchiveExtractionLimits = .standard
    ) throws {
        let total = requiredContentByteCount.addingReportingOverflow(
            limits.minimumFreeDiskReserveByteCount
        )
        let requiredByteCount = total.overflow ? UInt64.max : total.partialValue
        let values = try destinationDirectoryURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let availableCapacity = values.volumeAvailableCapacityForImportantUsage,
              availableCapacity >= 0
        else {
            return
        }
        guard UInt64(availableCapacity) >= requiredByteCount else {
            throw ModArchiveExtractionError.insufficientDiskSpace(
                sourceURL,
                requiredByteCount: requiredByteCount
            )
        }
    }

    static func removeAbandonedExtractionDirectories(
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let children = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isSymbolicLinkKey
            ],
            options: []
        ) else {
            return
        }
        let cutoffDate = now.addingTimeInterval(-abandonedExtractionAge)

        for childURL in children
        where childURL.lastPathComponent.hasPrefix(extractionDirectoryPrefix) {
            guard let values = try? childURL.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey
                ]
            ) else {
                continue
            }
            guard values.isSymbolicLink != true,
                  values.isDirectory == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoffDate
            else {
                continue
            }

            let markerURL = childURL.appendingPathComponent(extractionMarkerFileName)
            let markerValues = try? markerURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard markerValues?.isRegularFile == true,
                  markerValues?.isSymbolicLink != true
            else {
                continue
            }
            try? fileManager.removeItem(at: childURL)
        }
    }

    private static func archiveEntryPathIsSafe(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.utf8.contains(0),
              path.utf8.count <= maximumArchivePathByteCount
        else {
            return false
        }

        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= maximumArchivePathComponentCount else {
            return false
        }

        return components.enumerated().allSatisfy { index, component in
            if component.isEmpty {
                return index == components.indices.last
            }
            return component != "." && component != ".."
        }
    }
}

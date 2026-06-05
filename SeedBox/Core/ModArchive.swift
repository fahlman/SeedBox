import Foundation

enum ModArchiveReason: String, Sendable {
    case deleted
    case updated
}

enum ModArchive {
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

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
    ) throws {
        guard fileManager.directoryExists(at: archiveDirectory) else {
            return
        }

        let archivedContainers = try fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for containerURL in archivedContainers where fileManager.directoryExists(at: containerURL) {
            let values = try containerURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let archiveDate = values.creationDate ?? values.contentModificationDate
            guard let archiveDate, archiveDate < cutoffDate else {
                continue
            }

            try fileManager.removeItem(at: containerURL)
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
}

import Foundation
import OSLog

enum AuditLogAction: String, Codable, Equatable, Sendable {
    case modsFolderSelected
    case modsFolderCreated
    case modsAdded
    case modEnabled
    case modDisabled
    case modMovedToTrash
    case modSetCreated
    case modSetRenamed
    case modSetApplied
    case modSetDeleted
}

enum AuditLogSubjectKind: String, Codable, Equatable, Sendable {
    case mod
    case modSet
    case modsFolder
}

struct AuditLogSubject: Codable, Equatable, Sendable {
    var kind: AuditLogSubjectKind
    var id: String?
    var name: String
    var path: String?
}

struct AuditLogEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var action: AuditLogAction
    var summary: String
    var modsDirectoryPath: String
    var selectedModSetID: String
    var selectedModSetName: String?
    var appliedModSetID: String?
    var subjects: [AuditLogSubject]
    var details: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: AuditLogAction,
        summary: String,
        modsDirectoryPath: String,
        selectedModSetID: String,
        selectedModSetName: String?,
        appliedModSetID: String?,
        subjects: [AuditLogSubject] = [],
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.summary = summary
        self.modsDirectoryPath = modsDirectoryPath
        self.selectedModSetID = selectedModSetID
        self.selectedModSetName = selectedModSetName
        self.appliedModSetID = appliedModSetID
        self.subjects = subjects
        self.details = details
    }
}

struct AuditTrailState: Equatable, Sendable {
    var logPath: String
    var recentEntries: [AuditLogEntry]
    var lastErrorMessage: String?
}

enum AuditLogStore {
    static let recentEntryLimit = 100

    private struct StoredAuditLog: Codable {
        var entries: [AuditLogEntry]
    }

    private static let logger = Logger(
        subsystem: "com.fahlsing.SeedBox",
        category: "Audit"
    )

    static func append(
        _ entry: AuditLogEntry,
        to logURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = logURL.deletingLastPathComponent()
        if !fileManager.directoryExists(at: directoryURL) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        var entries = try loadEntries(from: logURL)
        entries.append(entry)
        try saveEntries(entries, to: logURL, fileManager: fileManager)
        logger.info("\(entry.action.rawValue, privacy: .public): \(consoleSummary(for: entry), privacy: .public)")
    }

    static func loadEntries(
        from logURL: URL,
        limit: Int? = nil
    ) throws -> [AuditLogEntry] {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return []
        }

        let data = try Data(contentsOf: logURL)
        guard !data.isEmpty else {
            return []
        }

        let storedLog = try PropertyListDecoder().decode(StoredAuditLog.self, from: data)
        return limit.map { Array(storedLog.entries.suffix($0)) } ?? storedLog.entries
    }

    private static func saveEntries(
        _ entries: [AuditLogEntry],
        to logURL: URL,
        fileManager: FileManager
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(StoredAuditLog(entries: entries))
        if fileManager.fileExists(atPath: logURL.path) {
            try fileManager.removeItem(at: logURL)
        }
        try data.write(to: logURL, options: .atomic)
    }

    private static func consoleSummary(for entry: AuditLogEntry) -> String {
        switch entry.action {
        case .modsFolderSelected:
            return "Selected Mods folder."
        case .modsFolderCreated:
            return "Created Mods folder."
        default:
            return summaryByRedactingPaths(from: entry)
        }
    }

    private static func summaryByRedactingPaths(from entry: AuditLogEntry) -> String {
        var summary = entry.summary
        let pathFragments = ([entry.modsDirectoryPath] + entry.subjects.compactMap(\.path))
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for path in pathFragments {
            summary = summary.replacingOccurrences(of: path, with: "[path]")
        }

        return summary
    }
}

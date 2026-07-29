import Foundation
import ZIPFoundation

struct CrashDiagnosticsExportSummary: Equatable, Sendable {
    var payloadCount: Int
    var supportFileCount: Int
    var archiveByteCount: Int
}

struct CrashDiagnosticsExportContext: Equatable, Sendable {
    var appVersion: String
    var buildVersion: String
    var state: ModManagerState?

    static func current(state: ModManagerState? = nil) -> CrashDiagnosticsExportContext {
        CrashDiagnosticsExportContext(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            state: state
        )
    }
}

struct CrashDiagnosticsSummary: Equatable, Sendable {
    static let recentPayloadInterval: TimeInterval = 14 * 24 * 60 * 60

    var payloadCount: Int
    var mostRecentPayloadDate: Date?

    static let empty = CrashDiagnosticsSummary(payloadCount: 0, mostRecentPayloadDate: nil)

    func hasRecentPayloads(
        asOf referenceDate: Date = Date(),
        interval: TimeInterval = Self.recentPayloadInterval
    ) -> Bool {
        guard let mostRecentPayloadDate else {
            return false
        }

        return mostRecentPayloadDate >= referenceDate.addingTimeInterval(-interval)
    }
}

enum CrashDiagnosticsExporter {
    private static let supportDirectoryName = "Seed Box Diagnostics"

    static func defaultArchiveName(generatedAt date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Seed Box Diagnostics \(formatter.string(from: date)).zip"
    }

    static func diagnosticPayloadCount(
        in diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        fileManager: FileManager = .default
    ) -> Int {
        (try? diagnosticPayloadURLs(in: diagnosticsDirectory, fileManager: fileManager).count) ?? 0
    }

    static func diagnosticPayloadURLs(
        in diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.directoryExists(at: diagnosticsDirectory) else {
            return []
        }

        return try fileManager
            .contentsOfDirectory(
                at: diagnosticsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                guard url.pathExtension.lowercased() == "json" else {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    static func diagnosticSummary(
        in diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        fileManager: FileManager = .default
    ) -> CrashDiagnosticsSummary {
        guard let payloadURLs = try? diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: fileManager
        ) else {
            return .empty
        }

        let mostRecentDate = payloadURLs
            .compactMap { payloadURL -> Date? in
                let values = try? payloadURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .creationDateKey]
                )
                return values?.contentModificationDate ?? values?.creationDate
            }
            .max()

        return CrashDiagnosticsSummary(
            payloadCount: payloadURLs.count,
            mostRecentPayloadDate: mostRecentDate
        )
    }

    @discardableResult
    static func exportArchive(
        from diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        to destinationURL: URL,
        context: CrashDiagnosticsExportContext = .current(),
        generatedAt date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> CrashDiagnosticsExportSummary {
        let payloadURLs = try diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: fileManager
        )

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SeedBoxDiagnostics-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectory = stagingDirectory
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
        let temporaryArchiveURL = stagingDirectory
            .appendingPathComponent("Seed Box Diagnostics.zip")

        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        let summary = try writeSupportBundle(
            to: bundleDirectory,
            payloadURLs: payloadURLs,
            context: context,
            generatedAt: date,
            fileManager: fileManager
        )

        try fileManager.zipItem(
            at: bundleDirectory,
            to: temporaryArchiveURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )

        let archiveByteCount = try temporaryArchiveURL
            .resourceValues(forKeys: [.fileSizeKey])
            .fileSize ?? 0
        try copyArchiveAtomically(
            from: temporaryArchiveURL,
            to: destinationURL,
            fileManager: fileManager
        )

        return CrashDiagnosticsExportSummary(
            payloadCount: summary.payloadCount,
            supportFileCount: summary.supportFileCount,
            archiveByteCount: archiveByteCount
        )
    }

    @discardableResult
    static func writeSupportBundle(
        to bundleDirectory: URL,
        payloadURLs: [URL],
        context: CrashDiagnosticsExportContext,
        generatedAt date: Date,
        fileManager: FileManager = .default
    ) throws -> CrashDiagnosticsExportSummary {
        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        let paths = knownPrivatePaths(in: context.state)
        var supportFileCount = 0

        try diagnosticsReadme(payloadCount: payloadURLs.count, generatedAt: date)
            .write(
                to: bundleDirectory.appendingPathComponent("README.txt"),
                atomically: true,
                encoding: .utf8
            )
        supportFileCount += 1

        try writeJSON(
            AppSummary(
                generatedAt: iso8601String(from: date),
                appVersion: context.appVersion,
                buildVersion: context.buildVersion,
                metricKitPayloadCount: payloadURLs.count,
                includesAppState: context.state != nil
            ),
            named: "App Summary.json",
            in: bundleDirectory
        )
        supportFileCount += 1

        if let state = context.state {
            try writeJSON(
                SettingsSummary(state: state),
                named: "Settings Summary.json",
                in: bundleDirectory
            )
            supportFileCount += 1

            try writeJSON(
                InventorySummary(state: state),
                named: "Mod Inventory Summary.json",
                in: bundleDirectory
            )
            supportFileCount += 1

            try writeJSON(
                AuditSummary(state: state, knownPrivatePaths: paths),
                named: "Audit Summary.json",
                in: bundleDirectory
            )
            supportFileCount += 1

            if let report = state.lastSessionReport {
                try writeJSON(
                    LastSessionSummary(report: report, knownPrivatePaths: paths),
                    named: "Last Session Summary.json",
                    in: bundleDirectory
                )
                supportFileCount += 1
            }
        }

        if !payloadURLs.isEmpty {
            let payloadDirectory = bundleDirectory
                .appendingPathComponent("MetricKit Payloads", isDirectory: true)
            try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

            for payloadURL in payloadURLs {
                try writeSanitizedMetricKitPayload(
                    from: payloadURL,
                    to: payloadDirectory.appendingPathComponent(payloadURL.lastPathComponent),
                    knownPrivatePaths: paths
                )
                supportFileCount += 1
            }
        }

        return CrashDiagnosticsExportSummary(
            payloadCount: payloadURLs.count,
            supportFileCount: supportFileCount,
            archiveByteCount: 0
        )
    }

    private static func diagnosticsReadme(payloadCount: Int, generatedAt date: Date) -> String {
        """
        Seed Box Diagnostics

        Generated: \(iso8601String(from: date) ?? "Unknown")
        MetricKit diagnostic payloads: \(payloadCount)

        This support bundle was created only because you chose Export Diagnostics in Seed Box. It may contain app settings summaries, mod inventory summaries, recent audit summaries, last-session SMAPI log summaries, and sanitized Apple MetricKit diagnostic JSON payloads.

        It does not include mod files, mod manifests, mod config files, SMAPI logs, or game saves. Seed Box redacts local file paths from every JSON file before writing this bundle.
        """
    }

    private static func writeJSON<Value: Encodable>(
        _ value: Value,
        named fileName: String,
        in directoryURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: .atomic)
    }

    fileprivate static func iso8601String(from date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withTimeZone
        ]
        return formatter.string(from: date)
    }

    private static func knownPrivatePaths(in state: ModManagerState?) -> [String] {
        guard let state else {
            return []
        }

        let paths = [state.modsDirectoryPath, state.auditTrail.logPath]
            + state.mods.map(\.url.path)
            + state.invalidModFolders.map(\.url.path)
            + state.archivedMods.flatMap { [$0.url.path, $0.containerURL.path] }
            + state.auditTrail.recentEntries.flatMap { entry in
                [entry.modsDirectoryPath] + entry.subjects.compactMap(\.path)
            }

        return Array(Set(paths.filter { !$0.isEmpty }))
            .sorted { $0.count > $1.count }
    }

    fileprivate static func redacted(_ text: String, knownPrivatePaths: [String]) -> String {
        var redactedText = text
        for path in knownPrivatePaths {
            redactedText = redactedText.replacingOccurrences(of: path, with: "[redacted path]")
        }

        let patterns = [
            #"file:/+(?:Users|Volumes|private|var|tmp)/[^\s"',;)]+"#,
            #"/(?:Users|Volumes|private|var|tmp)/[^\s"',;)]+"#,
            #"~(?:/[^\s"',;)]+)+"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(redactedText.startIndex..., in: redactedText)
            redactedText = expression.stringByReplacingMatches(
                in: redactedText,
                range: range,
                withTemplate: "[redacted path]"
            )
        }

        let trimmedText = redactedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.hasPrefix("/") || trimmedText.hasPrefix("file:/") {
            return "[redacted path]"
        }

        return redactedText
    }

    private static func copyArchiveAtomically(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let stagedURL = destinationDirectory
            .appendingPathComponent(".SeedBoxDiagnostics-\(UUID().uuidString)")
            .appendingPathExtension("tmp")
        defer {
            try? fileManager.removeItem(at: stagedURL)
        }

        try fileManager.copyItem(at: sourceURL, to: stagedURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        }
    }

    private static func writeSanitizedMetricKitPayload(
        from sourceURL: URL,
        to destinationURL: URL,
        knownPrivatePaths: [String]
    ) throws {
        let data = try Data(contentsOf: sourceURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let sanitizedObject = sanitizedJSONObject(
            object,
            knownPrivatePaths: knownPrivatePaths
        )
        let sanitizedData = try JSONSerialization.data(
            withJSONObject: sanitizedObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try sanitizedData.write(to: destinationURL, options: .atomic)
    }

    private static func sanitizedJSONObject(
        _ value: Any,
        knownPrivatePaths: [String]
    ) -> Any {
        switch value {
        case let string as String:
            return redacted(string, knownPrivatePaths: knownPrivatePaths)
        case let array as [Any]:
            return array.map {
                sanitizedJSONObject($0, knownPrivatePaths: knownPrivatePaths)
            }
        case let dictionary as [String: Any]:
            return Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
                (
                    key,
                    sanitizedJSONObject(value, knownPrivatePaths: knownPrivatePaths)
                )
            })
        default:
            return value
        }
    }
}

private struct AppSummary: Encodable {
    var generatedAt: String?
    var appVersion: String
    var buildVersion: String
    var metricKitPayloadCount: Int
    var includesAppState: Bool
}

private struct SettingsSummary: Encodable {
    var modsFolderName: String
    var modsFolderReady: Bool
    var modsFolderAccessSaved: Bool
    var modsFolderIssueCount: Int
    var smapiLogFolderAccessSaved: Bool
    var checksForModUpdates: Bool
    var moveModFilesToTrashAfterAddingMods: Bool
    var suppressAddModsSuccessNotification: Bool
    var automaticallyPrunesExpiredArchives: Bool
    var archiveRetentionDays: Int
    var modSetCount: Int
    var selectedModSetName: String?
    var appliedModSetName: String?
    var bisectionInProgress: Bool
    var hasPendingLastSessionNotice: Bool

    init(state: ModManagerState) {
        let selectedSet = state.modSets.first { $0.id == state.selectedModSetID }
        let appliedSet = state.appliedModSetID.flatMap { appliedSetID in
            state.modSets.first { $0.id == appliedSetID }
        }

        modsFolderName = URL(fileURLWithPath: state.modsDirectoryPath).lastPathComponent
        modsFolderReady = state.readiness.canManageMods
        modsFolderAccessSaved = state.hasSavedFolderAccess
        modsFolderIssueCount = state.status.issues.count
        smapiLogFolderAccessSaved = state.hasSMAPILogFolderAccess
        checksForModUpdates = state.checksForModUpdates
        moveModFilesToTrashAfterAddingMods = state.sourceCleanupSettings.moveModFilesToTrashAfterAddingMods
        suppressAddModsSuccessNotification = state.sourceCleanupSettings.suppressAddModsSuccessNotification
        automaticallyPrunesExpiredArchives = state.archiveSettings.automaticallyPrunesExpiredArchives
        archiveRetentionDays = state.archiveSettings.normalizedRetentionDays
        modSetCount = state.modSets.count
        selectedModSetName = selectedSet?.name
        appliedModSetName = appliedSet?.name
        bisectionInProgress = state.bisectionSession != nil
        hasPendingLastSessionNotice = state.pendingLastSessionNotice != nil
    }
}

private struct InventorySummary: Encodable {
    var totalMods: Int
    var enabledMods: Int
    var disabledMods: Int
    var invalidFolderCount: Int
    var duplicateGroupCount: Int
    var archivedModCount: Int
    var archiveByteCount: Int64
    var availableUpdateCount: Int
    var detectedSMAPIVersion: String?
    var availableSMAPIUpdateVersion: String?
    var modsWithMissingRequiredDependencies: Int
    var modsWithMissingOptionalDependencies: Int
    var modsWithSMAPIVersionIssues: Int
    var modsWithLastSessionIssues: Int
    var mods: [ModSummary]

    init(state: ModManagerState) {
        let availableUpdateIDs = Set(state.availableUpdates.map(\.modID))
        let smapiVersionIssueFolderNames = Set(state.smapiVersionIssues.map(\.folderName))
        let lastSessionIssueFolderNames = Set(state.lastSessionIssues.map(\.mod.folderName))

        totalMods = state.mods.count
        enabledMods = state.mods.filter(\.isEnabled).count
        disabledMods = state.mods.count - enabledMods
        invalidFolderCount = state.invalidModFolders.count
        duplicateGroupCount = state.duplicateGroups.count
        archivedModCount = state.archiveSummary.archivedModCount
        archiveByteCount = state.archiveSummary.totalByteCount
        availableUpdateCount = state.mods.filter { mod in
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID else {
                return false
            }
            return availableUpdateIDs.contains(uniqueID)
        }.count
        detectedSMAPIVersion = state.detectedSMAPIVersion
        availableSMAPIUpdateVersion = state.smapiUpdate?.latestVersion
        modsWithMissingRequiredDependencies = state.mods.filter(\.hasMissingRequiredDependencies).count
        modsWithMissingOptionalDependencies = state.mods.filter(\.hasMissingOptionalDependencies).count
        modsWithSMAPIVersionIssues = state.smapiVersionIssues.count
        modsWithLastSessionIssues = state.lastSessionIssues.count
        mods = state.mods
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { mod in
                let normalizedUniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID
                return ModSummary(
                    mod: mod,
                    updateAvailable: normalizedUniqueID.map { availableUpdateIDs.contains($0) } ?? false,
                    hasSMAPIVersionIssue: smapiVersionIssueFolderNames.contains(mod.folderName),
                    hasLastSessionIssue: lastSessionIssueFolderNames.contains(mod.folderName)
                )
            }
    }
}

private struct ModSummary: Encodable {
    var displayName: String
    var folderName: String
    var uniqueID: String?
    var version: String
    var author: String
    var type: String
    var isEnabled: Bool
    var updateAvailable: Bool
    var requiredDependencyCount: Int
    var optionalDependencyCount: Int
    var missingRequiredDependencyCount: Int
    var missingOptionalDependencyCount: Int
    var hasSMAPIVersionIssue: Bool
    var hasLastSessionIssue: Bool

    init(
        mod: ModInfo,
        updateAvailable: Bool,
        hasSMAPIVersionIssue: Bool,
        hasLastSessionIssue: Bool
    ) {
        displayName = mod.displayName
        folderName = mod.enabledFolderName
        uniqueID = mod.manifest?.uniqueID
        version = mod.versionText
        author = mod.authorText
        type = mod.typeText
        isEnabled = mod.isEnabled
        self.updateAvailable = updateAvailable
        requiredDependencyCount = mod.requiredDependencyRequirements.count
        optionalDependencyCount = mod.optionalDependencyRequirements.count
        missingRequiredDependencyCount = mod.missingRequiredDependencies.count
        missingOptionalDependencyCount = mod.missingOptionalDependencies.count
        self.hasSMAPIVersionIssue = hasSMAPIVersionIssue
        self.hasLastSessionIssue = hasLastSessionIssue
    }
}

private struct AuditSummary: Encodable {
    var logAvailable: Bool
    var recentEntryCount: Int
    var lastErrorMessage: String?
    var recentEntries: [AuditEntrySummary]

    init(state: ModManagerState, knownPrivatePaths: [String]) {
        logAvailable = !state.auditTrail.logPath.isEmpty
        recentEntryCount = state.auditTrail.recentEntries.count
        lastErrorMessage = state.auditTrail.lastErrorMessage.map {
            CrashDiagnosticsExporter.redacted($0, knownPrivatePaths: knownPrivatePaths)
        }
        recentEntries = state.auditTrail.recentEntries.map {
            AuditEntrySummary(entry: $0, knownPrivatePaths: knownPrivatePaths)
        }
    }
}

private struct AuditEntrySummary: Encodable {
    var timestamp: String?
    var action: String
    var summary: String
    var selectedModSetName: String?
    var appliedModSetID: String?
    var subjects: [AuditSubjectSummary]
    var details: [String: String]

    init(entry: AuditLogEntry, knownPrivatePaths: [String]) {
        timestamp = CrashDiagnosticsExporter.iso8601String(from: entry.timestamp)
        action = entry.action.rawValue
        summary = CrashDiagnosticsExporter.redacted(entry.summary, knownPrivatePaths: knownPrivatePaths)
        selectedModSetName = entry.selectedModSetName
        appliedModSetID = entry.appliedModSetID
        subjects = entry.subjects.map {
            AuditSubjectSummary(subject: $0, knownPrivatePaths: knownPrivatePaths)
        }
        details = Dictionary(uniqueKeysWithValues: entry.details.map { key, value in
            (
                key,
                CrashDiagnosticsExporter.redacted(value, knownPrivatePaths: knownPrivatePaths)
            )
        })
    }
}

private struct AuditSubjectSummary: Encodable {
    var kind: String
    var id: String?
    var name: String
    var hadPath: Bool

    init(subject: AuditLogSubject, knownPrivatePaths: [String]) {
        kind = subject.kind.rawValue
        id = subject.id
        name = CrashDiagnosticsExporter.redacted(subject.name, knownPrivatePaths: knownPrivatePaths)
        hadPath = subject.path != nil
    }
}

private struct LastSessionSummary: Encodable {
    var smapiVersion: String?
    var gameVersion: String?
    var generatedAt: String?
    var sessionStartedAt: String?
    var skippedModCount: Int
    var erroringModCount: Int
    var skippedMods: [SkippedModSummary]

    init(report: SMAPILogReport, knownPrivatePaths: [String]) {
        smapiVersion = report.smapiVersion
        gameVersion = report.gameVersion
        generatedAt = CrashDiagnosticsExporter.iso8601String(from: report.generatedAt)
        sessionStartedAt = CrashDiagnosticsExporter.iso8601String(from: report.sessionStartedAt)
        skippedModCount = report.skippedMods.count
        erroringModCount = report.modErrorCounts.count
        skippedMods = report.skippedMods.map {
            SkippedModSummary(
                skippedMod: $0,
                knownPrivatePaths: knownPrivatePaths
            )
        }
    }
}

private struct SkippedModSummary: Encodable {
    var name: String
    var version: String?
    var reason: String

    init(skippedMod: SMAPISkippedMod, knownPrivatePaths: [String]) {
        name = CrashDiagnosticsExporter.redacted(
            skippedMod.name,
            knownPrivatePaths: knownPrivatePaths
        )
        version = skippedMod.version.map {
            CrashDiagnosticsExporter.redacted(
                $0,
                knownPrivatePaths: knownPrivatePaths
            )
        }
        reason = CrashDiagnosticsExporter.redacted(
            skippedMod.reason,
            knownPrivatePaths: knownPrivatePaths
        )
    }
}

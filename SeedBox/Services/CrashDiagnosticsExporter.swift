import Foundation
import ZIPFoundation

struct CrashDiagnosticsExportSummary: Equatable, Sendable {
    var payloadCount: Int
    var supportFileCount: Int
    var archiveByteCount: Int
}

struct CrashDiagnosticsExportLimits: Equatable, Sendable {
    static let standard = CrashDiagnosticsExportLimits(
        maximumPayloadCount: CrashDiagnosticsCollector.defaultMaximumPayloadCount,
        maximumPayloadByteCount: CrashDiagnosticsCollector.defaultMaximumByteCount,
        maximumTotalPayloadByteCount: CrashDiagnosticsCollector.defaultMaximumByteCount
    )

    var maximumPayloadCount: Int
    var maximumPayloadByteCount: Int
    var maximumTotalPayloadByteCount: Int
}

enum CrashDiagnosticsExportError: Error, Equatable, LocalizedError, Sendable {
    case tooManyPayloads(maximumCount: Int)
    case payloadTooLarge(fileName: String, maximumByteCount: Int)
    case payloadsTooLarge(maximumByteCount: Int)
    case invalidPayload(fileName: String)

    var errorDescription: String? {
        switch self {
        case .tooManyPayloads:
            String(localized: "There are too many diagnostic files to export safely.")
        case .payloadTooLarge:
            String(localized: "A diagnostic file is too large to export safely.")
        case .payloadsTooLarge:
            String(localized: "The stored diagnostics are too large to export safely.")
        case .invalidPayload:
            String(localized: "A stored diagnostic file could not be read safely.")
        }
    }
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
    static let stagingDirectoryPrefix = "SeedBoxDiagnostics-"
    static let stagingMarkerFileName = ".seedbox-diagnostics"
    static let abandonedStagingAge: TimeInterval = 24 * 60 * 60

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
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                guard url.pathExtension.lowercased() == "json" else {
                    return false
                }
                let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                return values?.isRegularFile == true
                    && values?.isSymbolicLink != true
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
        fileManager: FileManager = .default,
        limits: CrashDiagnosticsExportLimits = .standard,
        temporaryDirectoryURL: URL? = nil
    ) throws -> CrashDiagnosticsExportSummary {
        let payloadURLs = try diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: fileManager
        )

        let temporaryDirectory = temporaryDirectoryURL
            ?? fileManager.temporaryDirectory
        removeAbandonedStagingDirectories(
            in: temporaryDirectory,
            fileManager: fileManager
        )
        let stagingDirectory = try SecureTemporaryWorkspace.create(
            in: temporaryDirectory,
            prefix: stagingDirectoryPrefix,
            markerFileName: stagingMarkerFileName,
            fileManager: fileManager
        )
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
            fileManager: fileManager,
            limits: limits
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
        fileManager: FileManager = .default,
        limits: CrashDiagnosticsExportLimits = .standard
    ) throws -> CrashDiagnosticsExportSummary {
        let validatedPayloadURLs = try validatedPayloadURLs(
            payloadURLs,
            limits: limits
        )
        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        let paths = knownPrivatePaths(in: context.state)
        var supportFileCount = 0

        try diagnosticsReadme(payloadCount: validatedPayloadURLs.count, generatedAt: date)
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
                metricKitPayloadCount: validatedPayloadURLs.count,
                includesAppState: context.state != nil
            ),
            named: "App Summary.json",
            in: bundleDirectory,
            knownPrivatePaths: paths
        )
        supportFileCount += 1

        if let state = context.state {
            try writeJSON(
                SettingsSummary(state: state),
                named: "Settings Summary.json",
                in: bundleDirectory,
                knownPrivatePaths: paths
            )
            supportFileCount += 1

            try writeJSON(
                InventorySummary(state: state),
                named: "Mod Inventory Summary.json",
                in: bundleDirectory,
                knownPrivatePaths: paths
            )
            supportFileCount += 1

            try writeJSON(
                AuditSummary(state: state, knownPrivatePaths: paths),
                named: "Audit Summary.json",
                in: bundleDirectory,
                knownPrivatePaths: paths
            )
            supportFileCount += 1

            if let report = state.lastSessionReport {
                try writeJSON(
                    LastSessionSummary(report: report, knownPrivatePaths: paths),
                    named: "Last Session Summary.json",
                    in: bundleDirectory,
                    knownPrivatePaths: paths
                )
                supportFileCount += 1
            }
        }

        if !validatedPayloadURLs.isEmpty {
            let payloadDirectory = bundleDirectory
                .appendingPathComponent("MetricKit Payloads", isDirectory: true)
            try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

            var totalPayloadByteCount = 0
            for payloadURL in validatedPayloadURLs {
                let sanitizedPayload = try sanitizedMetricKitPayload(
                    from: payloadURL,
                    knownPrivatePaths: paths,
                    maximumByteCount: limits.maximumPayloadByteCount
                )
                let total = totalPayloadByteCount.addingReportingOverflow(
                    sanitizedPayload.sourceByteCount
                )
                guard !total.overflow,
                      total.partialValue <= limits.maximumTotalPayloadByteCount
                else {
                    throw CrashDiagnosticsExportError.payloadsTooLarge(
                        maximumByteCount: limits.maximumTotalPayloadByteCount
                    )
                }
                totalPayloadByteCount = total.partialValue
                try sanitizedPayload.data.write(
                    to: payloadDirectory.appendingPathComponent(
                        payloadURL.lastPathComponent
                    ),
                    options: .atomic
                )
                supportFileCount += 1
            }
        }

        return CrashDiagnosticsExportSummary(
            payloadCount: validatedPayloadURLs.count,
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
        in directoryURL: URL,
        knownPrivatePaths: [String]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        let sanitizedObject = sanitizedJSONObject(
            object,
            knownPrivatePaths: knownPrivatePaths
        )
        let sanitizedData = try JSONSerialization.data(
            withJSONObject: sanitizedObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try sanitizedData.write(
            to: directoryURL.appendingPathComponent(fileName),
            options: .atomic
        )
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

    private static func sanitizedMetricKitPayload(
        from sourceURL: URL,
        knownPrivatePaths: [String],
        maximumByteCount: Int
    ) throws -> (data: Data, sourceByteCount: Int) {
        let data: Data
        do {
            data = try BoundedFileReader.readRegularFile(
                at: sourceURL,
                maximumByteCount: maximumByteCount
            )
        } catch BoundedFileReadError.exceedsLimit {
            throw CrashDiagnosticsExportError.payloadTooLarge(
                fileName: sourceURL.lastPathComponent,
                maximumByteCount: maximumByteCount
            )
        } catch {
            throw CrashDiagnosticsExportError.invalidPayload(
                fileName: sourceURL.lastPathComponent
            )
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CrashDiagnosticsExportError.invalidPayload(
                fileName: sourceURL.lastPathComponent
            )
        }
        let sanitizedObject = sanitizedJSONObject(
            object,
            knownPrivatePaths: knownPrivatePaths
        )
        let sanitizedData = try JSONSerialization.data(
            withJSONObject: sanitizedObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        return (sanitizedData, data.count)
    }

    private static func validatedPayloadURLs(
        _ payloadURLs: [URL],
        limits: CrashDiagnosticsExportLimits
    ) throws -> [URL] {
        guard payloadURLs.count <= limits.maximumPayloadCount else {
            throw CrashDiagnosticsExportError.tooManyPayloads(
                maximumCount: limits.maximumPayloadCount
            )
        }

        var totalByteCount = 0
        var seenFileNames: Set<String> = []
        for payloadURL in payloadURLs {
            guard seenFileNames.insert(payloadURL.lastPathComponent).inserted else {
                throw CrashDiagnosticsExportError.invalidPayload(
                    fileName: payloadURL.lastPathComponent
                )
            }

            let values: URLResourceValues
            do {
                values = try payloadURL.resourceValues(
                    forKeys: [
                        .fileSizeKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey
                    ]
                )
            } catch {
                throw CrashDiagnosticsExportError.invalidPayload(
                    fileName: payloadURL.lastPathComponent
                )
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw CrashDiagnosticsExportError.invalidPayload(
                    fileName: payloadURL.lastPathComponent
                )
            }

            let byteCount = max(0, values.fileSize ?? 0)
            guard byteCount <= limits.maximumPayloadByteCount else {
                throw CrashDiagnosticsExportError.payloadTooLarge(
                    fileName: payloadURL.lastPathComponent,
                    maximumByteCount: limits.maximumPayloadByteCount
                )
            }
            let total = totalByteCount.addingReportingOverflow(byteCount)
            guard !total.overflow,
                  total.partialValue <= limits.maximumTotalPayloadByteCount
            else {
                throw CrashDiagnosticsExportError.payloadsTooLarge(
                    maximumByteCount: limits.maximumTotalPayloadByteCount
                )
            }
            totalByteCount = total.partialValue
        }
        return payloadURLs
    }

    static func removeAbandonedStagingDirectories(
        in temporaryDirectory: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        SecureTemporaryWorkspace.removeAbandonedDirectories(
            in: temporaryDirectory,
            prefix: stagingDirectoryPrefix,
            markerFileName: stagingMarkerFileName,
            olderThan: abandonedStagingAge,
            now: now,
            fileManager: fileManager
        )
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
            var sanitizedDictionary: [String: Any] = [:]
            for (key, childValue) in dictionary {
                let redactedKey = redacted(
                    key,
                    knownPrivatePaths: knownPrivatePaths
                )
                var uniqueKey = redactedKey
                var collisionIndex = 2
                while sanitizedDictionary[uniqueKey] != nil {
                    uniqueKey = "\(redactedKey) [\(collisionIndex)]"
                    collisionIndex += 1
                }
                sanitizedDictionary[uniqueKey] = sanitizedJSONObject(
                    childValue,
                    knownPrivatePaths: knownPrivatePaths
                )
            }
            return sanitizedDictionary
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
        id = subject.id.map {
            CrashDiagnosticsExporter.redacted(
                $0,
                knownPrivatePaths: knownPrivatePaths
            )
        }
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

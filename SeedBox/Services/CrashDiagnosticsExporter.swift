import Foundation
import ZIPFoundation

struct CrashDiagnosticsExportSummary: Equatable, Sendable {
    var payloadCount: Int
    var archiveByteCount: Int
}

enum CrashDiagnosticsExportError: LocalizedError, Equatable, Sendable {
    case noDiagnostics

    var errorDescription: String? {
        switch self {
        case .noDiagnostics:
            AppStrings.Status.noDiagnosticsToExport
        }
    }
}

enum CrashDiagnosticsExporter {
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

    @discardableResult
    static func exportArchive(
        from diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        to destinationURL: URL,
        generatedAt date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> CrashDiagnosticsExportSummary {
        let payloadURLs = try diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: fileManager
        )
        guard !payloadURLs.isEmpty else {
            throw CrashDiagnosticsExportError.noDiagnostics
        }

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SeedBoxDiagnostics-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectory = stagingDirectory
            .appendingPathComponent("Seed Box Diagnostics", isDirectory: true)
        let temporaryArchiveURL = stagingDirectory
            .appendingPathComponent("Seed Box Diagnostics.zip")

        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        try diagnosticsReadme(payloadCount: payloadURLs.count, generatedAt: date)
            .write(
                to: bundleDirectory.appendingPathComponent("README.txt"),
                atomically: true,
                encoding: .utf8
            )

        for payloadURL in payloadURLs {
            try fileManager.copyItem(
                at: payloadURL,
                to: bundleDirectory.appendingPathComponent(payloadURL.lastPathComponent)
            )
        }

        try fileManager.zipItem(
            at: bundleDirectory,
            to: temporaryArchiveURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )

        let archiveData = try Data(contentsOf: temporaryArchiveURL)
        try archiveData.write(to: destinationURL, options: .atomic)

        return CrashDiagnosticsExportSummary(
            payloadCount: payloadURLs.count,
            archiveByteCount: archiveData.count
        )
    }

    private static func diagnosticsReadme(payloadCount: Int, generatedAt date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withTimeZone
        ]

        return """
        Seed Box Diagnostics

        Generated: \(formatter.string(from: date))
        Diagnostic payloads: \(payloadCount)

        This archive contains MetricKit diagnostic JSON files that Seed Box stored locally on this Mac. Seed Box creates this archive only when you choose Export Diagnostics.
        """
    }
}

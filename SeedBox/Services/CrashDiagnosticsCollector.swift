import Foundation
import MetricKit

/// Receives Apple's MetricKit diagnostics — crash reports above all — and
/// stores them locally so a support conversation can reference what
/// happened. Nothing is transmitted anywhere; the files live in the app
/// container and the user owns them.
// All stored state is immutable after init; MetricKit delivers payloads on
// its own queue and file writes go through thread-safe FileManager.
final class CrashDiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashDiagnosticsCollector()
    static let didStorePayloadNotification = Notification.Name("SeedBoxCrashDiagnosticsCollectorDidStorePayload")
    static let didDeletePayloadsNotification = Notification.Name("SeedBoxCrashDiagnosticsCollectorDidDeletePayloads")
    static let defaultRetentionInterval: TimeInterval = 90 * 24 * 60 * 60
    static let defaultMaximumPayloadCount = 20
    static let defaultMaximumByteCount = 50 * 1_024 * 1_024

    static func defaultDiagnosticsDirectory() -> URL {
        StardewInstall.defaultModSetDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private let diagnosticsDirectory: URL
    private let retentionInterval: TimeInterval
    private let maximumPayloadCount: Int
    private let maximumByteCount: Int

    init(
        diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory(),
        retentionInterval: TimeInterval = CrashDiagnosticsCollector.defaultRetentionInterval,
        maximumPayloadCount: Int = CrashDiagnosticsCollector.defaultMaximumPayloadCount,
        maximumByteCount: Int = CrashDiagnosticsCollector.defaultMaximumByteCount
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.retentionInterval = retentionInterval
        self.maximumPayloadCount = maximumPayloadCount
        self.maximumByteCount = maximumByteCount
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            store(payload.jsonRepresentation(), receivedAt: Date())
        }
    }

    /// Writes one diagnostic payload as a timestamped JSON file. Split out
    /// and given raw data so it can be tested without MetricKit cooperation.
    func store(_ payloadData: Data, receivedAt date: Date) {
        do {
            guard payloadData.count <= maximumByteCount else {
                AppLog.diagnostics.error("Discarded an oversized MetricKit diagnostic payload (\(payloadData.count, privacy: .public) bytes).")
                return
            }

            try FileManager.default.createDirectory(
                at: diagnosticsDirectory,
                withIntermediateDirectories: true
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withDashSeparatorInDate,
                .withFractionalSeconds
            ]
            let timestamp = formatter.string(from: date)
                .replacingOccurrences(of: ":", with: "-")
            let name = "Diagnostic \(timestamp) \(UUID().uuidString).json"
            try payloadData.write(
                to: diagnosticsDirectory.appendingPathComponent(name),
                options: .atomic
            )
            try pruneStoredPayloads(referenceDate: Date())
            AppLog.diagnostics.error("Received a diagnostic payload from MetricKit; stored for review (\(payloadData.count, privacy: .public) bytes).")
            NotificationCenter.default.post(name: Self.didStorePayloadNotification, object: self)
        } catch {
            AppLog.diagnostics.error("Couldn't store a MetricKit diagnostic payload: \(error)")
        }
    }

    func deleteAllStoredPayloads(fileManager: FileManager = .default) throws {
        guard fileManager.directoryExists(at: diagnosticsDirectory) else {
            return
        }

        for url in try payloadFileURLs(fileManager: fileManager) {
            try fileManager.removeItem(at: url)
        }
        NotificationCenter.default.post(name: Self.didDeletePayloadsNotification, object: self)
    }

    func pruneStoredPayloads(
        referenceDate: Date = Date(),
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.directoryExists(at: diagnosticsDirectory) else {
            return
        }

        let cutoffDate = referenceDate.addingTimeInterval(-retentionInterval)
        var retainedPayloads: [(url: URL, date: Date, byteCount: Int)] = []

        for url in try payloadFileURLs(fileManager: fileManager) {
            let values = try url.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
            )
            let date = values.contentModificationDate ?? values.creationDate ?? .distantPast
            guard date >= cutoffDate else {
                try fileManager.removeItem(at: url)
                continue
            }
            retainedPayloads.append((url, date, values.fileSize ?? 0))
        }

        retainedPayloads.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }

        var retainedCount = 0
        var retainedByteCount = 0
        for payload in retainedPayloads {
            let canRetain = retainedCount < maximumPayloadCount
                && retainedByteCount + payload.byteCount <= maximumByteCount
            if canRetain {
                retainedCount += 1
                retainedByteCount += payload.byteCount
            } else {
                try fileManager.removeItem(at: payload.url)
            }
        }
    }

    private func payloadFileURLs(fileManager: FileManager) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: diagnosticsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard url.pathExtension.lowercased() == "json" else {
                return false
            }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

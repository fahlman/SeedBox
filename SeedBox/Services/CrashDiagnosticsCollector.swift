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

    static func defaultDiagnosticsDirectory() -> URL {
        StardewInstall.defaultModSetDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private let diagnosticsDirectory: URL

    init(diagnosticsDirectory: URL = CrashDiagnosticsCollector.defaultDiagnosticsDirectory()) {
        self.diagnosticsDirectory = diagnosticsDirectory
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
            try FileManager.default.createDirectory(
                at: diagnosticsDirectory,
                withIntermediateDirectories: true
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate]
            let name = "Diagnostic \(formatter.string(from: date).replacingOccurrences(of: ":", with: "-")).json"
            try payloadData.write(to: diagnosticsDirectory.appendingPathComponent(name))
            AppLog.diagnostics.error("Received a diagnostic payload from MetricKit; stored for review (\(payloadData.count, privacy: .public) bytes).")
        } catch {
            AppLog.diagnostics.error("Couldn't store a MetricKit diagnostic payload: \(error)")
        }
    }
}

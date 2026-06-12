import Foundation

struct SMAPISkippedMod: Equatable, Sendable {
    var name: String
    var version: String?
    var reason: String
}

/// What SMAPI's log says happened in the last game session.
struct SMAPILogReport: Equatable, Sendable {
    var smapiVersion: String?
    var gameVersion: String?
    /// The log file's modification date — effectively when the session ended.
    var generatedAt: Date?
    /// The log file's creation date. SMAPI recreates the file each game
    /// launch, so this uniquely identifies a session even while the game is
    /// still appending to the log.
    var sessionStartedAt: Date?
    var skippedMods: [SMAPISkippedMod] = []
    /// ERROR-level log lines per mod, keyed by lowercased mod name.
    var modErrorCounts: [String: Int] = [:]
}

/// A last-session problem attributed to a currently installed mod.
struct LastSessionModIssue: Identifiable, Equatable, Sendable {
    var id: String { mod.id }
    var mod: ModInfo
    var skippedReason: String?
    var errorCount: Int
}

/// A one-time launch announcement that the last game session had problems.
struct LastSessionNotice: Identifiable, Equatable, Sendable {
    var id: String { "\(sessionDate.timeIntervalSince1970)" }
    var sessionDate: Date
    var skippedModCount: Int
    var erroringModCount: Int
}

private final class CachedLogReport {
    let modificationDate: Date?
    let fileSize: Int
    let report: SMAPILogReport

    init(modificationDate: Date?, fileSize: Int, report: SMAPILogReport) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.report = report
    }
}

enum SMAPILogReader {
    static let fileName = "SMAPI-latest.txt"

    /// Trace-heavy logs can be large; anything beyond this is implausible
    /// and skipped rather than read into memory.
    static let maximumLogByteCount = 64 * 1024 * 1024

    // NSCache is documented thread-safe; the log is reparsed only when its
    // modification date or size changes.
    nonisolated(unsafe) private static let reportCache: NSCache<NSString, CachedLogReport> = {
        let cache = NSCache<NSString, CachedLogReport>()
        cache.countLimit = 8
        return cache
    }()

    static func loadReport(inLogFolder folderURL: URL) -> SMAPILogReport? {
        let logURL = folderURL.appendingPathComponent(fileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let fileSize = (attributes[.size] as? NSNumber)?.intValue
        else {
            // Normal before the first game session writes a log.
            AppLog.logInsights.debug("No readable \(fileName, privacy: .public) in the chosen folder.")
            return nil
        }

        guard fileSize <= maximumLogByteCount else {
            AppLog.logInsights.error("SMAPI log exceeds the size cap (\(fileSize, privacy: .public) bytes); skipping it.")
            return nil
        }

        let modificationDate = attributes[.modificationDate] as? Date
        let cacheKey = logURL.standardizedFileURL.path as NSString
        if let cached = reportCache.object(forKey: cacheKey),
           cached.fileSize == fileSize,
           cached.modificationDate == modificationDate {
            return cached.report
        }

        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            AppLog.logInsights.error("SMAPI log exists but couldn't be read as UTF-8.")
            return nil
        }

        var report = parse(text)
        AppLog.logInsights.info("Parsed SMAPI log: \(report.skippedMods.count, privacy: .public) skipped, \(report.modErrorCounts.count, privacy: .public) erroring mods, found SMAPI version: \(report.smapiVersion != nil, privacy: .public).")
        report.generatedAt = modificationDate
        report.sessionStartedAt = attributes[.creationDate] as? Date
        reportCache.setObject(
            CachedLogReport(modificationDate: modificationDate, fileSize: fileSize, report: report),
            forKey: cacheKey
        )
        return report
    }

    /// Tolerant line-oriented parse of SMAPI's log format:
    /// `[HH:mm:ss LEVEL Source] message`, with unprefixed continuation lines
    /// (stack traces) attributed to the preceding entry and ignored here.
    static func parse(_ text: String) -> SMAPILogReport {
        var report = SMAPILogReport()
        let linePattern = /^\[\d{2}:\d{2}:\d{2} (TRACE|DEBUG|INFO|WARN|ERROR|ALERT)\s+([^\]]+)\] (.*)$/
        let versionPattern = /SMAPI (\S+) with Stardew Valley (\S+)/
        let skippedPattern = /^\s*-\s+(.+?)\s+because\s+(.+)$/

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let match = line.firstMatch(of: linePattern) else {
                continue
            }

            let level = match.output.1
            let source = match.output.2.trimmingCharacters(in: .whitespaces)
            let message = String(match.output.3)

            if report.smapiVersion == nil,
               source == "SMAPI",
               let versionMatch = message.firstMatch(of: versionPattern) {
                report.smapiVersion = String(versionMatch.output.1)
                report.gameVersion = String(versionMatch.output.2)
            }

            if source == "SMAPI",
               let skippedMatch = message.firstMatch(of: skippedPattern) {
                report.skippedMods.append(
                    skippedMod(
                        nameAndVersion: String(skippedMatch.output.1),
                        reason: String(skippedMatch.output.2)
                    )
                )
                continue
            }

            if level == "ERROR", source != "SMAPI", source.lowercased() != "game" {
                report.modErrorCounts[source.lowercased(), default: 0] += 1
            }
        }

        return report
    }

    private static func skippedMod(nameAndVersion: String, reason: String) -> SMAPISkippedMod {
        let trimmed = nameAndVersion.trimmingCharacters(in: .whitespaces)
        let components = trimmed.split(separator: " ")
        if components.count > 1,
           let last = components.last,
           last.first?.isNumber == true || (last.hasPrefix("v") && last.dropFirst().first?.isNumber == true) {
            return SMAPISkippedMod(
                name: components.dropLast().joined(separator: " "),
                version: String(last),
                reason: reason
            )
        }

        return SMAPISkippedMod(name: trimmed, version: nil, reason: reason)
    }
}

import OSLog

/// Diagnostic loggers for Apple's unified log, one category per area.
///
/// View with Console.app or:
/// `log show --predicate 'subsystem == "com.fahlsing.SeedBox"' --info --debug`
///
/// These exist for the failure paths that are deliberately quiet in the UI.
/// Interpolated values are redacted by OSLog's privacy model unless marked
/// public; paths, mod names, and error descriptions stay private — only
/// counts, codes, and flags are public.
enum AppLog {
    private static let subsystem = "com.fahlsing.SeedBox"

    static let folderAccess = Logger(subsystem: subsystem, category: "FolderAccess")
    static let scan = Logger(subsystem: subsystem, category: "Scan")
    static let archive = Logger(subsystem: subsystem, category: "Archive")
    static let updateCheck = Logger(subsystem: subsystem, category: "UpdateCheck")
    static let logInsights = Logger(subsystem: subsystem, category: "LogInsights")
    static let monitor = Logger(subsystem: subsystem, category: "Monitor")
    static let bisection = Logger(subsystem: subsystem, category: "Bisection")
    static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")
}

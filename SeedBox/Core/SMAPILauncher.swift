import Foundation

public struct SMAPILaunchRequest: Equatable {
    public var executableURL: URL
    public var currentDirectoryURL: URL
    public var arguments: [String]

    public var commandLinePreview: String {
        ([executableURL.path] + arguments)
            .map(Self.shellQuoted)
            .joined(separator: " ")
    }

    public func makeProcess() -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = currentDirectoryURL
        process.arguments = arguments
        return process
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           !value.contains("'") {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum SMAPILauncher {
    public static func request(
        for install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> SMAPILaunchRequest {
        let status = install.status(fileManager: fileManager)

        if !status.installDirectoryExists {
            throw LauncherError.missingInstallDirectory(install.macOSDirectory)
        }
        if !status.smapiExecutableExists {
            throw LauncherError.missingSMAPI(install.smapiExecutableURL)
        }
        if !status.modDirectoryExists {
            throw LauncherError.missingModDirectory(install.modDirectoryURL)
        }

        return SMAPILaunchRequest(
            executableURL: install.smapiExecutableURL,
            currentDirectoryURL: install.macOSDirectory,
            arguments: install.launchArguments
        )
    }
}

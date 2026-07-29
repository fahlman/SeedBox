import Foundation

struct ModSetIdentifier: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              rawValue.utf8.allSatisfy(Self.isAllowedByte)
        else {
            throw CocoaError(
                .fileReadInvalidFileName,
                userInfo: [NSFilePathErrorKey: rawValue]
            )
        }

        self.rawValue = rawValue
    }

    init(fileURL: URL) throws {
        guard fileURL.pathExtension.lowercased() == "plist" else {
            throw CocoaError(
                .fileReadInvalidFileName,
                userInfo: [NSFilePathErrorKey: fileURL.path]
            )
        }

        try self.init(fileURL.deletingPathExtension().lastPathComponent)
    }

    func fileURL(in directoryURL: URL) -> URL {
        let standardizedDirectory = directoryURL.standardizedFileURL
        let candidate = standardizedDirectory
            .appendingPathComponent(rawValue)
            .appendingPathExtension("plist")
            .standardizedFileURL

        precondition(candidate.deletingLastPathComponent() == standardizedDirectory)
        return candidate
    }

    private static func isAllowedByte(_ byte: UInt8) -> Bool {
        switch byte {
        case Character("A").asciiValue!...Character("Z").asciiValue!,
             Character("a").asciiValue!...Character("z").asciiValue!,
             Character("0").asciiValue!...Character("9").asciiValue!,
             Character("-").asciiValue!,
             Character("_").asciiValue!:
            return true
        default:
            return false
        }
    }
}

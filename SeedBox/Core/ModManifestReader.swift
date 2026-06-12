import Foundation

private final class CachedManifestEntry {
    let modificationDate: Date?
    let fileSize: Int
    let manifest: ModManifest?

    init(modificationDate: Date?, fileSize: Int, manifest: ModManifest?) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.manifest = manifest
    }
}

enum ModManifestReader {
    static let fileName = "manifest.json"

    /// Real manifests are a few kilobytes; reject anything implausibly large
    /// before reading it into memory.
    static let maximumManifestByteCount = 1024 * 1024

    // NSCache is documented thread-safe; failed decodes are cached too so
    // broken manifests stay cheap across rescans.
    nonisolated(unsafe) private static let manifestCache: NSCache<NSString, CachedManifestEntry> = {
        let cache = NSCache<NSString, CachedManifestEntry>()
        cache.countLimit = 4096
        return cache
    }()

    /// Loads a manifest, reusing the previous decode when the file's
    /// modification date and size are unchanged. Every rescan stats each
    /// manifest but only re-reads and re-decodes the ones that changed.
    static func loadManifest(at url: URL) -> ModManifest? {
        // FileManager attributes are read fresh on every call, unlike URL
        // resource values, which are cached per URL instance.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.intValue
        else {
            return nil
        }

        guard fileSize <= maximumManifestByteCount else {
            AppLog.scan.error("Manifest exceeds the size cap (\(fileSize, privacy: .public) bytes): \(url.path)")
            return nil
        }

        let cacheKey = url.standardizedFileURL.path as NSString
        let modificationDate = attributes[.modificationDate] as? Date
        if let cached = manifestCache.object(forKey: cacheKey),
           cached.fileSize == fileSize,
           cached.modificationDate == modificationDate {
            return cached.manifest
        }

        guard let data = try? Data(contentsOf: url) else {
            AppLog.scan.error("Manifest exists but couldn't be read: \(url.path)")
            return nil
        }

        let manifest = decodeManifest(from: data)
        if manifest == nil {
            AppLog.scan.error("Manifest couldn't be decoded even with lenient parsing: \(url.path)")
        }
        manifestCache.setObject(
            CachedManifestEntry(
                modificationDate: modificationDate,
                fileSize: fileSize,
                manifest: manifest
            ),
            forKey: cacheKey
        )
        return manifest
    }

    /// SMAPI parses manifests leniently, and published mods commonly ship
    /// manifests with a UTF-8 BOM, comments, or trailing commas that strict
    /// JSON decoding rejects.
    static func decodeManifest(from data: Data) -> ModManifest? {
        let data = strippingUTF8ByteOrderMark(from: data)
        if let manifest = try? JSONDecoder().decode(ModManifest.self, from: data) {
            return manifest
        }

        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]),
              JSONSerialization.isValidJSONObject(object),
              let normalizedData = try? JSONSerialization.data(withJSONObject: object)
        else {
            return nil
        }

        return try? JSONDecoder().decode(ModManifest.self, from: normalizedData)
    }

    private static func strippingUTF8ByteOrderMark(from data: Data) -> Data {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard data.count >= byteOrderMark.count,
              data.prefix(byteOrderMark.count).elementsEqual(byteOrderMark)
        else {
            return data
        }

        return data.dropFirst(byteOrderMark.count)
    }

    static func findManifest(
        in directoryURL: URL,
        maximumDepth: Int = 3,
        fileManager: FileManager = .default
    ) -> URL? {
        let directURL = directoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        guard maximumDepth > 0 else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for childURL in children where fileManager.directoryExists(at: childURL) {
            if let foundURL = findManifest(
                in: childURL,
                maximumDepth: maximumDepth - 1,
                fileManager: fileManager
            ) {
                return foundURL
            }
        }

        return nil
    }

    static func directoryContainsManifest(
        _ directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        fileManager.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path)
    }
}

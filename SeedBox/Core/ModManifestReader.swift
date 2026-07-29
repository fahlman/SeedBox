import Darwin
import Foundation

private final class CachedManifestEntry {
    let signature: ManifestFileSignature
    let manifest: ModManifest?

    init(signature: ManifestFileSignature, manifest: ModManifest?) {
        self.signature = signature
        self.manifest = manifest
    }
}

private struct ManifestFileSignature: Equatable {
    var device: UInt64
    var inode: UInt64
    var fileSize: Int
    var modificationSeconds: Int64
    var modificationNanoseconds: Int64

    init?(url: URL) {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              metadata.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= off_t(Int.max)
        else {
            return nil
        }

        device = UInt64(bitPattern: Int64(metadata.st_dev))
        inode = metadata.st_ino
        fileSize = Int(metadata.st_size)
        modificationSeconds = Int64(metadata.st_mtimespec.tv_sec)
        modificationNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
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

    /// Loads a manifest, reusing the previous decode while the same file has
    /// the same size and modification time. Reads never follow symbolic links.
    static func loadManifest(at url: URL) -> ModManifest? {
        guard let signature = ManifestFileSignature(url: url) else {
            return nil
        }

        guard signature.fileSize <= maximumManifestByteCount else {
            AppLog.scan.error("Manifest exceeds the size cap (\(signature.fileSize, privacy: .public) bytes): \(url.path)")
            return nil
        }

        let cacheKey = url.standardizedFileURL.path as NSString
        if let cached = manifestCache.object(forKey: cacheKey),
           cached.signature == signature {
            return cached.manifest
        }

        guard let data = try? BoundedFileReader.readRegularFile(
            at: url,
            maximumByteCount: maximumManifestByteCount
        ) else {
            AppLog.scan.error("Manifest exists but couldn't be read: \(url.path)")
            return nil
        }

        let manifest = decodeManifest(from: data)
        if manifest == nil {
            AppLog.scan.error("Manifest couldn't be decoded even with lenient parsing: \(url.path)")
        }
        manifestCache.setObject(
            CachedManifestEntry(
                signature: signature,
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
        if isSafeRegularFile(directURL) {
            return directURL
        }

        guard maximumDepth > 0 else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles]
        )) ?? []

        for childURL in children {
            let values = try? childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true
            else {
                continue
            }

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
        fileManager _: FileManager
    ) -> Bool {
        isSafeRegularFile(
            directoryURL.appendingPathComponent(fileName)
        )
    }

    private static func isSafeRegularFile(_ url: URL) -> Bool {
        ManifestFileSignature(url: url) != nil
    }
}

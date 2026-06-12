import Foundation

/// Checks for mod updates against the SMAPI web API, the community service
/// SMAPI itself uses. One fixed HTTPS endpoint; the request carries only each
/// mod's unique ID, installed version, and manifest update keys.
struct SMAPIModUpdateClient: ModUpdateChecking {
    static let endpoint = URL(string: "https://api.smapi.io/v3.0/mods")!

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "SeedBox/\(Bundle.main.shortVersionText) (macOS)"
        ]
        session = URLSession(configuration: configuration)
    }

    /// The SMAPI version assumed when none can be detected from the Mods
    /// folder; the API uses it to filter updates that need newer SMAPI.
    static let fallbackAPIVersion = "4.0.0"

    func checkForUpdates(
        _ queries: [ModUpdateQuery],
        apiVersion: String?
    ) async throws -> [ModUpdateCheckResult] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                mods: queries.map(RequestMod.init),
                apiVersion: apiVersion?.trimmedNonEmpty ?? Self.fallbackAPIVersion
            )
        )

        AppLog.updateCheck.debug("Checking updates for \(queries.count, privacy: .public) entries.")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.updateCheck.error("Update check failed with HTTP status \(statusCode, privacy: .public).")
            throw URLError(.badServerResponse)
        }

        do {
            return try Self.decodeResults(from: data)
        } catch {
            AppLog.updateCheck.error("Update check response couldn't be decoded: \(error)")
            throw error
        }
    }

    static func decodeResults(from data: Data) throws -> [ModUpdateCheckResult] {
        try JSONDecoder().decode([ResponseMod].self, from: data).map { responseMod in
            ModUpdateCheckResult(
                uniqueID: responseMod.id,
                suggestedVersion: responseMod.suggestedUpdate?.version,
                downloadURL: httpsURL(from: responseMod.suggestedUpdate?.url),
                pageURL: httpsURL(from: responseMod.metadata?.main?.url)
            )
        }
    }

    private static func httpsURL(from urlText: String?) -> URL? {
        urlText
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
    }

    private struct RequestBody: Encodable {
        var mods: [RequestMod]
        var apiVersion: String
        var platform = "Mac"
        // Extended metadata carries each mod's main page URL, which powers
        // the "Get Mod" links for missing dependencies.
        var includeExtendedMetadata = true
    }

    private struct RequestMod: Encodable {
        var id: String
        var updateKeys: [String]
        var installedVersion: String?

        init(_ query: ModUpdateQuery) {
            id = query.uniqueID
            updateKeys = query.updateKeys
            installedVersion = query.installedVersion
        }
    }

    private struct ResponseMod: Decodable {
        var id: String
        var suggestedUpdate: SuggestedUpdate?
        var metadata: ResponseMetadata?
    }

    private struct SuggestedUpdate: Decodable {
        var version: String?
        var url: String?
    }

    private struct ResponseMetadata: Decodable {
        var main: ResponseModPage?
    }

    private struct ResponseModPage: Decodable {
        var url: String?
    }
}

private extension Bundle {
    var shortVersionText: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}

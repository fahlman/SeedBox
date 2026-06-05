import XCTest

final class LocalizationCatalogTests: XCTestCase {
    private let expectedLocales = [
        "en",
        "de",
        "es",
        "fr",
        "it",
        "ja",
        "ko",
        "nl",
        "pt-BR",
        "zh-Hans"
    ]

    func testStringCatalogContainsEverySupportedLocale() throws {
        let catalog = try loadStringCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)

            for locale in expectedLocales {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                let values = localizedValues(in: localization)
                XCTAssertFalse(values.isEmpty, "\(key) missing \(locale) value")
                for value in values {
                    XCTAssertFalse(value.text.isEmpty, "\(key) has an empty \(locale) value")
                }
            }
        }
    }

    func testStringCatalogHasTranslatorContextForEveryString() throws {
        let catalog = try loadStringCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let comment = try XCTUnwrap(entry["comment"] as? String, "\(key) is missing translator context")
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) has empty translator context")
        }
    }

    func testStringCatalogLocalizedPlaceholdersMatchSource() throws {
        let catalog = try loadStringCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            let expected = placeholders(inSource: key)
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)

            for locale in expectedLocales {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                for value in localizedValues(in: localization) {
                    XCTAssertTrue(
                        localizedPlaceholders(
                            in: value.text,
                            match: expected,
                            allowsMissingNumericPlaceholders: value.allowsMissingNumericPlaceholders
                        ),
                        "\(key) has mismatched \(locale) placeholders in \(value.text)"
                    )
                }
            }
        }
    }

    private func loadStringCatalog() throws -> [String: Any] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectRootURL
            .appendingPathComponent("SeedBox")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func placeholders(inSource source: String) -> [Int: String] {
        let matches = source.matches(of: /%@|%lld/)
        return Dictionary(uniqueKeysWithValues: matches.enumerated().map { index, match in
            let kind = String(match.output) == "%@" ? "@" : "lld"
            return (index + 1, kind)
        })
    }

    private func localizedValues(in localization: [String: Any]) -> [(text: String, allowsMissingNumericPlaceholders: Bool)] {
        if let stringUnit = localization["stringUnit"] as? [String: Any],
           let value = stringUnit["value"] as? String {
            return [(value, false)]
        }

        guard
            let variations = localization["variations"] as? [String: Any],
            let plural = variations["plural"] as? [String: Any]
        else {
            return []
        }

        return plural.compactMap { category, rawVariation in
            guard
                let variation = rawVariation as? [String: Any],
                let stringUnit = variation["stringUnit"] as? [String: Any],
                let value = stringUnit["value"] as? String
            else {
                return nil
            }

            return (value, category == "one")
        }
    }

    private func localizedPlaceholders(
        in value: String,
        match expected: [Int: String],
        allowsMissingNumericPlaceholders: Bool
    ) -> Bool {
        let positional = value.matches(of: /%(\d+)\$(@|lld)/).map { match in
            (Int(match.output.1) ?? -1, String(match.output.2))
        }

        let actual: [(Int, String)]
        if positional.isEmpty {
            actual = value.matches(of: /%(@|lld)/).enumerated().map { index, match in
                (index + 1, String(match.output.1))
            }
        } else {
            actual = positional
        }

        guard !expected.isEmpty else {
            return actual.isEmpty
        }

        var seen: [Int: String] = [:]
        for (position, kind) in actual {
            guard expected[position] == kind else {
                return false
            }
            seen[position] = kind
        }

        return expected.allSatisfy { position, kind in
            if allowsMissingNumericPlaceholders && kind == "lld" {
                return true
            }
            return seen[position] != nil
        }
    }
}

import AppKit

enum AboutPanelContent {
    static func options(bundle: Bundle = .main) -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: AppStrings.App.name,
            .applicationVersion: versionText(bundle: bundle)
        ]

        if let credits = credits(in: bundle) {
            options[.credits] = credits
        }

        return options
    }

    static func versionText(bundle: Bundle = .main) -> String {
        versionText(
            appVersion: stringValue(for: "CFBundleShortVersionString", in: bundle),
            buildVersion: stringValue(for: "CFBundleVersion", in: bundle)
        )
    }

    static func versionText(appVersion: String?, buildVersion: String?) -> String {
        let version = appVersion?.trimmedNonEmpty ?? AppStrings.App.unknownVersion
        let build = buildVersion?.trimmedNonEmpty ?? AppStrings.App.unknownBuild
        return AppStrings.App.versionBuild(version: version, build: build)
    }

    private static func credits(in bundle: Bundle) -> NSAttributedString? {
        guard let url = bundle.url(forResource: "Credits", withExtension: "rtf") else {
            return nil
        }

        return try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    private static func stringValue(for key: String, in bundle: Bundle) -> String? {
        (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmedNonEmpty
    }
}

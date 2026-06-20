import Foundation

enum AppDistributionChannel: String, CaseIterable, Sendable {
    case appStoreCandidate
    case steam

    static var current: AppDistributionChannel {
        #if SEEDBOX_STEAM
        return .steam
        #else
        return .appStoreCandidate
        #endif
    }

    var usesAppSandbox: Bool {
        switch self {
        case .appStoreCandidate:
            true
        case .steam:
            false
        }
    }

    var supportsSteamworksIntegration: Bool {
        switch self {
        case .appStoreCandidate:
            false
        case .steam:
            true
        }
    }

    var releaseConfigurationName: String {
        switch self {
        case .appStoreCandidate:
            "Release"
        case .steam:
            "Release Steam"
        }
    }

    var entitlementsPath: String {
        switch self {
        case .appStoreCandidate:
            "SeedBox/Sandbox.entitlements"
        case .steam:
            "SeedBox/Steam.entitlements"
        }
    }
}

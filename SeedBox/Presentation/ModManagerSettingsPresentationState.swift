import Foundation

struct ModManagerSettingsPresentationState {
    var install: StardewInstall
    var modFolderName: String
    var modsDirectoryPath: String
    var readiness: ModManagerReadiness
    var hasSavedFolderAccess: Bool
    var sourceCleanupSettings: SourceCleanupSettings
    var archiveSettings: ArchiveSettings

    @MainActor
    init(viewModel: ModManagerViewModel) {
        install = viewModel.install
        modFolderName = viewModel.modFolderName
        modsDirectoryPath = viewModel.state.modsDirectoryPath
        readiness = viewModel.state.readiness
        hasSavedFolderAccess = viewModel.state.hasSavedFolderAccess
        sourceCleanupSettings = viewModel.sourceCleanupSettings
        archiveSettings = viewModel.archiveSettings
    }
}

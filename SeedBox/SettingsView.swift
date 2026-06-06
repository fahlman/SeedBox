import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @State private var isChoosingModsFolder = false

    var body: some View {
        Form {
            Section(AppStrings.Settings.managedModsFolderSection) {
                LabeledContent(AppStrings.Settings.folder) {
                    Text(viewModel.modFolderName)
                        .foregroundStyle(.secondary)
                }

                NativePathControl(url: viewModel.install.modDirectoryURL)
                    .frame(height: 28)
                    .help(viewModel.state.modsDirectoryPath)

                LabeledContent(viewModel.modFolderName) {
                    Label(
                        readiness.modsFolderStatusText,
                        systemImage: readiness.canManageMods ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(readiness.canManageMods ? .green : .orange)
                }

                LabeledContent(AppStrings.Settings.folderAccess) {
                    Label(
                        viewModel.state.hasSavedFolderAccess ? AppStrings.Settings.saved : AppStrings.Settings.notSaved,
                        systemImage: viewModel.state.hasSavedFolderAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(viewModel.state.hasSavedFolderAccess ? .green : .orange)
                }

                HStack {
                    Button {
                        isChoosingModsFolder = true
                    } label: {
                        Label(AppStrings.Setup.chooseFolder, systemImage: "folder")
                    }

                    Button {
                        viewModel.revealModsFolder()
                    } label: {
                        Label(AppStrings.Settings.reveal, systemImage: "eye")
                    }
                    .disabled(!readiness.canManageMods)

                    Button {
                        Task {
                            await viewModel.createModFolder()
                        }
                    } label: {
                        Label(AppStrings.Setup.createFolder, systemImage: "folder.badge.plus")
                    }
                    .disabled(!readiness.canCreateModFolder)

                    Spacer()
                }
            }

            Section(AppStrings.Settings.addingModsSection) {
                Toggle(
                    AppStrings.Settings.moveModFilesToTrashAfterAddingMods,
                    isOn: moveModFilesToTrashBinding
                )

                Toggle(
                    AppStrings.Settings.suppressAddModsSuccessNotification,
                    isOn: suppressAddModsSuccessNotificationBinding
                )
            }

            Section(AppStrings.Settings.archivesSection) {
                Toggle(
                    AppStrings.Settings.automaticallyPruneExpiredArchives,
                    isOn: automaticallyPrunesExpiredArchivesBinding
                )

                Stepper(
                    value: archiveRetentionDaysBinding,
                    in: 1...365
                ) {
                    LabeledContent(AppStrings.Settings.keepArchivedMods) {
                        Text(AppStrings.Settings.days(viewModel.archiveSettings.normalizedRetentionDays))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .fileImporter(
            isPresented: $isChoosingModsFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.chooseModsFolder(url)
                }
            case .failure(let error):
                viewModel.recordModsFolderSelectionError(error)
            }
        }
    }

    private var readiness: ModManagerReadiness {
        viewModel.state.readiness
    }

    private var moveModFilesToTrashBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.sourceCleanupSettings.moveModFilesToTrashAfterAddingMods
            },
            set: { isEnabled in
                viewModel.setMoveModFilesToTrashAfterAddingMods(isEnabled)
            }
        )
    }

    private var suppressAddModsSuccessNotificationBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.sourceCleanupSettings.suppressAddModsSuccessNotification
            },
            set: { isEnabled in
                viewModel.setSuppressAddModsSuccessNotification(isEnabled)
            }
        )
    }

    private var automaticallyPrunesExpiredArchivesBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.archiveSettings.automaticallyPrunesExpiredArchives
            },
            set: { isEnabled in
                viewModel.setAutomaticallyPrunesExpiredArchives(isEnabled)
            }
        )
    }

    private var archiveRetentionDaysBinding: Binding<Int> {
        Binding(
            get: {
                viewModel.archiveSettings.normalizedRetentionDays
            },
            set: { days in
                viewModel.setArchiveRetentionDays(days)
            }
        )
    }
}

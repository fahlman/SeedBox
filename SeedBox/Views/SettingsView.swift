import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @State private var isChoosingModsFolder = false

    private var presentationState: ModManagerSettingsPresentationState {
        ModManagerSettingsPresentationState(viewModel: viewModel)
    }

    var body: some View {
        Form {
            Section(AppStrings.Settings.managedModsFolderSection) {
                LabeledContent(AppStrings.Settings.folder) {
                    Text(presentationState.modFolderName)
                        .foregroundStyle(.secondary)
                }

                NativePathControl(url: presentationState.install.modDirectoryURL)
                    .frame(height: 28)
                    .help(presentationState.modsDirectoryPath)

                LabeledContent(presentationState.modFolderName) {
                    Label(
                        presentationState.readiness.modsFolderStatusText,
                        systemImage: presentationState.readiness.canManageMods ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(presentationState.readiness.canManageMods ? .green : .orange)
                }

                LabeledContent(AppStrings.Settings.folderAccess) {
                    Label(
                        presentationState.hasSavedFolderAccess ? AppStrings.Settings.saved : AppStrings.Settings.notSaved,
                        systemImage: presentationState.hasSavedFolderAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(presentationState.hasSavedFolderAccess ? .green : .orange)
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
                    .disabled(!presentationState.readiness.canManageMods)

                    Button {
                        Task {
                            await viewModel.createModFolder()
                        }
                    } label: {
                        Label(AppStrings.Setup.createFolder, systemImage: "folder.badge.plus")
                    }
                    .disabled(!presentationState.readiness.canCreateModFolder)

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
                        Text(AppStrings.Settings.days(presentationState.archiveSettings.normalizedRetentionDays))
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

    private var moveModFilesToTrashBinding: Binding<Bool> {
        Binding(
            get: {
                presentationState.sourceCleanupSettings.moveModFilesToTrashAfterAddingMods
            },
            set: { isEnabled in
                viewModel.setMoveModFilesToTrashAfterAddingMods(isEnabled)
            }
        )
    }

    private var suppressAddModsSuccessNotificationBinding: Binding<Bool> {
        Binding(
            get: {
                presentationState.sourceCleanupSettings.suppressAddModsSuccessNotification
            },
            set: { isEnabled in
                viewModel.setSuppressAddModsSuccessNotification(isEnabled)
            }
        )
    }

    private var automaticallyPrunesExpiredArchivesBinding: Binding<Bool> {
        Binding(
            get: {
                presentationState.archiveSettings.automaticallyPrunesExpiredArchives
            },
            set: { isEnabled in
                viewModel.setAutomaticallyPrunesExpiredArchives(isEnabled)
            }
        )
    }

    private var archiveRetentionDaysBinding: Binding<Int> {
        Binding(
            get: {
                presentationState.archiveSettings.normalizedRetentionDays
            },
            set: { days in
                viewModel.setArchiveRetentionDays(days)
            }
        )
    }
}

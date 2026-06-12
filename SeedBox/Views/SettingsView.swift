import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var viewModel: ModManagerViewModel
    @State private var isChoosingModsFolder = false
    @State private var isChoosingLogFolder = false

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
                    isOn: settingBinding(
                        get: { viewModel.state.sourceCleanupSettings.moveModFilesToTrashAfterAddingMods },
                        set: viewModel.setMoveModFilesToTrashAfterAddingMods
                    )
                )

                Toggle(
                    AppStrings.Settings.suppressAddModsSuccessNotification,
                    isOn: settingBinding(
                        get: { viewModel.state.sourceCleanupSettings.suppressAddModsSuccessNotification },
                        set: viewModel.setSuppressAddModsSuccessNotification
                    )
                )
            }

            Section(AppStrings.Settings.smapiLogSection) {
                LabeledContent(AppStrings.Settings.logFolder) {
                    Label(
                        viewModel.state.hasSMAPILogFolderAccess
                            ? AppStrings.Settings.saved
                            : AppStrings.Settings.notSaved,
                        systemImage: viewModel.state.hasSMAPILogFolderAccess
                            ? "checkmark.circle.fill"
                            : "doc.text.magnifyingglass"
                    )
                    .foregroundStyle(viewModel.state.hasSMAPILogFolderAccess ? .green : .secondary)
                }

                Text(AppStrings.Settings.smapiLogFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    isChoosingLogFolder = true
                } label: {
                    Label(AppStrings.Settings.chooseLogFolder, systemImage: "folder")
                }
            }

            Section(AppStrings.Settings.modUpdatesSection) {
                Toggle(
                    AppStrings.Settings.checkForModUpdatesToggle,
                    isOn: settingBinding(
                        get: { viewModel.state.checksForModUpdates },
                        set: viewModel.setChecksForModUpdates
                    )
                )

                Text(AppStrings.Settings.modUpdatesPrivacyFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await viewModel.checkForModUpdates()
                    }
                } label: {
                    Label(AppStrings.Settings.checkForUpdatesNow, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(
                    !viewModel.state.checksForModUpdates
                        || !presentationState.readiness.canManageMods
                )

                if let smapiUpdate = viewModel.state.smapiUpdate {
                    HStack(spacing: 8) {
                        Label(
                            AppStrings.Status.smapiUpdateAvailable(smapiUpdate.latestVersion),
                            systemImage: "arrow.up.circle.fill"
                        )
                        .foregroundStyle(.blue)

                        if let downloadURL = smapiUpdate.downloadURL {
                            Link(AppStrings.ModInspector.viewUpdatePage, destination: downloadURL)
                                .font(.callout)
                        }
                    }
                }
            }

            Section(AppStrings.Settings.archivesSection) {
                Toggle(
                    AppStrings.Settings.automaticallyPruneExpiredArchives,
                    isOn: settingBinding(
                        get: { viewModel.state.archiveSettings.automaticallyPrunesExpiredArchives },
                        set: viewModel.setAutomaticallyPrunesExpiredArchives
                    )
                )

                Stepper(
                    value: settingBinding(
                        get: { viewModel.state.archiveSettings.normalizedRetentionDays },
                        set: viewModel.setArchiveRetentionDays
                    ),
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
        .fileImporter(
            isPresented: $isChoosingLogFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.chooseSMAPILogFolder(url)
                }
            case .failure(let error):
                viewModel.recordSMAPILogFolderSelectionError(error)
            }
        }
    }

    /// Bridges a state-backed value and an async actor-routed setter into a
    /// SwiftUI binding.
    private func settingBinding<Value: Sendable>(
        get: @escaping () -> Value,
        set: @escaping (Value) async -> Void
    ) -> Binding<Value> {
        Binding(get: get) { newValue in
            Task {
                await set(newValue)
            }
        }
    }
}

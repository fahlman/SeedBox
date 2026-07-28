import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var viewModel: ModManagerViewModel
    @State private var isChoosingModsFolder = false
    @State private var isChoosingLogFolder = false
    @State private var isCheckingForModUpdates = false
    @State private var diagnosticsSummary = CrashDiagnosticsSummary.empty
    @State private var diagnosticsStatus: StatusEvent?
    @State private var modUpdateStatus: StatusEvent?
    @AppStorage(MenuBarCompanion.enabledDefaultsKey) private var menuBarCompanionEnabled = false

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

            Section(AppStrings.Settings.menuBarSection) {
                Toggle(AppStrings.MenuBar.showItem, isOn: $menuBarCompanionEnabled)

                Text(AppStrings.Settings.menuBarFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .fileDialogDefaultDirectory(SMAPILogReader.defaultLogFolderURL)
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

            Section(AppStrings.Settings.diagnosticsSection) {
                LabeledContent(AppStrings.Settings.storedDiagnostics) {
                    Text(AppStrings.Settings.diagnosticPayloadCount(diagnosticsSummary.payloadCount))
                        .foregroundStyle(.secondary)
                }

                if diagnosticsSummary.hasRecentPayloads() {
                    Label(
                        AppStrings.Settings.recentDiagnosticsAvailable,
                        systemImage: "waveform.path.ecg"
                    )
                    .foregroundStyle(.orange)
                }

                if let mostRecentPayloadDate = diagnosticsSummary.mostRecentPayloadDate {
                    Text(AppStrings.Settings.mostRecentDiagnostic(
                        mostRecentPayloadDate.formatted(date: .abbreviated, time: .shortened)
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Text(AppStrings.Settings.diagnosticsFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        revealDiagnosticsFolder()
                    } label: {
                        Label(AppStrings.Settings.revealDiagnostics, systemImage: "eye")
                    }

                    Button {
                        exportDiagnostics()
                    } label: {
                        Label(AppStrings.Settings.exportDiagnostics, systemImage: "square.and.arrow.up")
                    }

                    Spacer()
                }

                if let diagnosticsStatus {
                    Label(
                        diagnosticsStatus.message,
                        systemImage: diagnosticsStatus.severity == .error
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(diagnosticsStatus.severity == .error ? .red : .secondary)
                    .font(.callout)
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
                    checkForModUpdates()
                } label: {
                    if isCheckingForModUpdates {
                        Label {
                            Text(AppStrings.Status.checkingForModUpdates)
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label(AppStrings.Settings.checkForUpdatesNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(
                    isCheckingForModUpdates
                        || !viewModel.state.checksForModUpdates
                        || !presentationState.readiness.canManageMods
                )

                if let modUpdateStatus {
                    Label(
                        modUpdateStatus.message,
                        systemImage: modUpdateStatus.severity == .error
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(modUpdateStatus.severity == .error ? .red : .secondary)
                    .font(.callout)
                }

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
        .onAppear(perform: refreshDiagnosticsSummary)
        .onReceive(NotificationCenter.default.publisher(for: CrashDiagnosticsCollector.didStorePayloadNotification)) { _ in
            Task { @MainActor in
                refreshDiagnosticsSummary()
            }
        }
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

    /// Bridges a state-backed value and an async actor-routed setter into a
    /// SwiftUI binding.
    @MainActor
    private func settingBinding<Value: Sendable>(
        get: @escaping @MainActor @Sendable () -> Value,
        set: @escaping @MainActor @Sendable (Value) async -> Void
    ) -> Binding<Value> {
        Binding(get: get) { newValue in
            Task { @MainActor in
                await set(newValue)
            }
        }
    }

    @MainActor
    private func revealDiagnosticsFolder() {
        do {
            let diagnosticsDirectory = CrashDiagnosticsCollector.defaultDiagnosticsDirectory()
            try FileManager.default.createDirectory(
                at: diagnosticsDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([diagnosticsDirectory])
            refreshDiagnosticsSummary()
        } catch {
            diagnosticsStatus = StatusEvent(
                severity: .error,
                message: AppStrings.Status.couldNotRevealDiagnostics(error.localizedDescription)
            )
        }
    }

    @MainActor
    private func exportDiagnostics() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = CrashDiagnosticsExporter.defaultArchiveName()
        if let zipType = UTType(filenameExtension: "zip") {
            savePanel.allowedContentTypes = [zipType]
        }

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            let summary = try CrashDiagnosticsExporter.exportArchive(
                to: destinationURL,
                context: .current(state: viewModel.state)
            )
            diagnosticsStatus = StatusEvent(
                severity: .info,
                message: AppStrings.Status.exportedDiagnostics(fileCount: summary.supportFileCount)
            )
            refreshDiagnosticsSummary()
        } catch {
            diagnosticsStatus = StatusEvent(
                severity: .error,
                message: AppStrings.Status.couldNotExportDiagnostics(error.localizedDescription)
            )
        }
    }

    @MainActor
    private func refreshDiagnosticsSummary() {
        diagnosticsSummary = CrashDiagnosticsExporter.diagnosticSummary()
    }

    @MainActor
    private func checkForModUpdates() {
        guard !isCheckingForModUpdates else {
            return
        }

        isCheckingForModUpdates = true
        modUpdateStatus = StatusEvent(
            severity: .info,
            message: AppStrings.Status.checkingForModUpdates
        )

        Task { @MainActor in
            await viewModel.checkForModUpdates()
            modUpdateStatus = viewModel.state.activityStatus
                ?? StatusEvent(severity: viewModel.state.statusLineSeverity, message: viewModel.state.statusLineMessage)
            isCheckingForModUpdates = false
        }
    }
}

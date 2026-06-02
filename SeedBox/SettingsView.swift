import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @State private var isChoosingModsFolder = false

    var body: some View {
        Form {
            Section("Managed Mods Folder") {
                LabeledContent("Folder") {
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

                LabeledContent("Folder Access") {
                    Label(
                        viewModel.state.hasSavedFolderAccess ? "Saved" : "Not saved",
                        systemImage: viewModel.state.hasSavedFolderAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(viewModel.state.hasSavedFolderAccess ? .green : .orange)
                }

                HStack {
                    Button {
                        isChoosingModsFolder = true
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }

                    Button {
                        viewModel.revealModsFolder()
                    } label: {
                        Label("Reveal", systemImage: "magnifyingglass")
                    }
                    .disabled(!readiness.canManageMods)

                    Button {
                        Task {
                            await viewModel.createModFolder()
                        }
                    } label: {
                        Label("Create Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(!readiness.canCreateModFolder)

                    Spacer()
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
}

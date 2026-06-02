import AppKit
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
                    .help(viewModel.modsDirectoryPath)

                LabeledContent(viewModel.modFolderName) {
                    Label(
                        modsFolderStatusText,
                        systemImage: viewModel.canManageMods ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(viewModel.canManageMods ? .green : .orange)
                }

                LabeledContent("Folder Access") {
                    Label(
                        viewModel.hasSavedFolderAccess ? "Saved" : "Not saved",
                        systemImage: viewModel.hasSavedFolderAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(viewModel.hasSavedFolderAccess ? .green : .orange)
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
                    .disabled(!viewModel.canManageMods)

                    Button {
                        viewModel.createModFolder()
                    } label: {
                        Label("Create Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(viewModel.status.modDirectoryExists || !viewModel.hasSavedFolderAccess)

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
                viewModel.chooseModsFolder(url)
            case .failure(let error):
                viewModel.recordModsFolderSelectionError(error)
            }
        }
    }

    private var modsFolderStatusText: String {
        if viewModel.canManageMods {
            return "Ready"
        }
        if !viewModel.hasSavedFolderAccess {
            return "Needs access"
        }
        return "Missing"
    }
}

private struct NativePathControl: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.backgroundColor = .clear
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        control.url = url
        control.toolTip = url.path
    }
}

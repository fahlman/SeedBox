import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        Form {
            Section("Managed Mods Folder") {
                HStack {
                    Text("Path")
                    Spacer()
                    Text(viewModel.modFolderName)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                NativePathControl(url: viewModel.install.modDirectoryURL)
                    .frame(height: 28)
                    .help(viewModel.modsDirectoryPath)

                SettingsStatusRow(
                    title: viewModel.modFolderName,
                    detail: viewModel.status.modDirectoryExists ? "Ready" : "Missing",
                    isOK: viewModel.status.modDirectoryExists
                )

                SettingsStatusRow(
                    title: "Folder Access",
                    detail: viewModel.hasSavedFolderAccess ? "Saved" : "Not saved",
                    isOK: viewModel.hasSavedFolderAccess
                )

                HStack {
                    Button {
                        viewModel.chooseModsFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }

                    Button {
                        viewModel.revealModsFolder()
                    } label: {
                        Label("Reveal", systemImage: "magnifyingglass")
                    }

                    Button {
                        viewModel.createModFolder()
                    } label: {
                        Label("Create Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(viewModel.status.modDirectoryExists)

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
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

private struct SettingsStatusRow: View {
    var title: String
    var detail: String
    var isOK: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
            StatusIcon(isOK: isOK)
        }
    }
}

private struct StatusIcon: View {
    var isOK: Bool

    var body: some View {
        Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(isOK ? .green : .orange)
    }
}

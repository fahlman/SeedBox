import SwiftUI

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @State private var searchText = ""

    private var filteredMods: [ModInfo] {
        guard !searchText.isEmpty else {
            return viewModel.mods
        }

        return viewModel.mods.filter { mod in
            mod.displayName.localizedCaseInsensitiveContains(searchText)
                || mod.authorText.localizedCaseInsensitiveContains(searchText)
                || (mod.manifest?.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(viewModel: viewModel)

            Divider()

            ToolbarBar(
                viewModel: viewModel,
                searchText: $searchText
            )

            Divider()

            if viewModel.status.modDirectoryExists {
                ModList(
                    mods: filteredMods,
                    viewModel: viewModel
                )
            } else {
                SetupEmptyState(viewModel: viewModel)
            }

            if !viewModel.activityMessage.isEmpty {
                Divider()
                ActivityBar(message: viewModel.activityMessage)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HeaderBar: View {
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Seed Box")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var statusText: String {
        if viewModel.status.canManageMods {
            let enabledCount = viewModel.mods.filter(\.isEnabled).count
            let disabledCount = viewModel.mods.count - enabledCount
            return "\(enabledCount) enabled, \(disabledCount) disabled in \(viewModel.modFolderName)."
        }
        if viewModel.isSMAPILikelyMissing {
            return "SMAPI not detected in Steam or GOG."
        }
        if !viewModel.hasSavedFolderAccess {
            return "Choose your Mods folder."
        }
        return "Create or pick the \(viewModel.modFolderName) folder."
    }
}

private struct ToolbarBar: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            TextField("Search mods", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            ReadinessPill(
                title: "\(viewModel.mods.filter(\.isEnabled).count) enabled",
                systemImage: "checkmark.circle.fill",
                color: .green
            )

            ReadinessPill(
                title: "\(viewModel.mods.filter { !$0.isEnabled }.count) disabled",
                systemImage: "pause.circle.fill",
                color: .orange
            )

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                viewModel.addMods()
            } label: {
                Label("Add Mod", systemImage: "plus")
            }
            .disabled(!viewModel.status.canManageMods)

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct ModList: View {
    var mods: [ModInfo]
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        if mods.isEmpty {
            EmptyModList(viewModel: viewModel)
        } else {
            List(mods) { mod in
                ModRow(
                    mod: mod,
                    viewModel: viewModel
                )
                .listRowSeparator(.visible)
            }
            .listStyle(.plain)
        }
    }
}

private struct ModRow: View {
    var mod: ModInfo
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle("", isOn: Binding(
                get: { mod.isEnabled },
                set: { viewModel.setMod(mod, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(mod.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if !mod.isEnabled {
                        Text("Disabled")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text("\(mod.versionText) by \(mod.authorText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let description = mod.manifest?.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button {
                    viewModel.revealMod(mod)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Reveal in Finder")

                Button(role: .destructive) {
                    viewModel.deleteMod(mod)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Move to Trash")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 15))
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyModList: View {
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("No mods in \(viewModel.modFolderName)")
                .font(.title3.weight(.semibold))

            Text("Add an unzipped mod folder to install it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.addMods()
            } label: {
                Label("Add Mod", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct SetupEmptyState: View {
    @ObservedObject var viewModel: ModManagerViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(setupTitle)
                .font(.title3.weight(.semibold))

            Text(setupDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    primarySetupAction()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var setupTitle: String {
        if viewModel.isSMAPILikelyMissing {
            return "SMAPI Not Installed"
        }
        if !viewModel.hasSavedFolderAccess {
            return "Choose Mods Folder"
        }
        return "Create \(viewModel.modFolderName)"
    }

    private var setupDetail: String {
        if viewModel.isSMAPILikelyMissing {
            return "No default Mods folder was found in Steam or GOG locations."
        }
        if !viewModel.hasSavedFolderAccess {
            return "Select the Mods folder Seed Box should manage."
        }
        return "Seed Box manages this Mods folder directly."
    }

    private var primaryButtonTitle: String {
        if !viewModel.hasSavedFolderAccess {
            return "Choose Folder"
        }
        return "Create Folder"
    }

    private var primaryButtonIcon: String {
        if !viewModel.hasSavedFolderAccess {
            return "folder"
        }
        return "folder.badge.plus"
    }

    private func primarySetupAction() {
        if !viewModel.hasSavedFolderAccess {
            viewModel.chooseModsFolder()
        } else {
            viewModel.createModFolder()
        }
    }
}

private struct ActivityBar: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct ReadinessPill: View {
    var title: String
    var systemImage: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private func openSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}

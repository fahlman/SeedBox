import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @State private var searchText = ""
    @State private var showOutput = false

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

            VStack(spacing: 0) {
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

                Divider()

                DisclosureGroup(isExpanded: $showOutput) {
                    ConsoleView(output: viewModel.output)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                } label: {
                    Label("SMAPI Output", systemImage: "text.alignleft")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HeaderBar: View {
    @ObservedObject var viewModel: LauncherViewModel

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

            Button {
                viewModel.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!viewModel.isRunning)

            Button {
                viewModel.launch()
            } label: {
                Label(viewModel.launchButtonTitle, systemImage: "play.fill")
                    .frame(minWidth: 108)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.status.canLaunch || viewModel.isRunning)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var statusText: String {
        if viewModel.isRunning {
            return "SMAPI is running."
        }
        if viewModel.status.canLaunch {
            return "\(viewModel.mods.count) mod folder\(viewModel.mods.count == 1 ? "" : "s") in \(viewModel.modFolderName)."
        }
        return "Finish setup before launching."
    }
}

private struct ToolbarBar: View {
    @ObservedObject var viewModel: LauncherViewModel
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
            .disabled(!viewModel.status.modDirectoryExists)

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
    @ObservedObject var viewModel: LauncherViewModel

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
    @ObservedObject var viewModel: LauncherViewModel

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
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("No mods in \(viewModel.modFolderName)")
                .font(.title3.weight(.semibold))

            Text("Add an unzipped mod folder, or link your existing default mods from Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    viewModel.addMods()
                } label: {
                    Label("Add Mod", systemImage: "plus")
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
}

private struct SetupEmptyState: View {
    @ObservedObject var viewModel: LauncherViewModel

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
        if !viewModel.status.installDirectoryExists {
            return "Choose Stardew Valley"
        }
        if !viewModel.status.smapiExecutableExists {
            return "Install SMAPI"
        }
        return "Create \(viewModel.modFolderName)"
    }

    private var setupDetail: String {
        if !viewModel.status.installDirectoryExists {
            return "The launcher needs your Stardew Valley folder before it can manage mods."
        }
        if !viewModel.status.smapiExecutableExists {
            return "SMAPI was not found in the selected Stardew Valley folder."
        }
        return "Create the managed mod folder before adding seeds to this box."
    }

    private var primaryButtonTitle: String {
        if !viewModel.status.installDirectoryExists {
            return "Choose Folder"
        }
        if !viewModel.status.smapiExecutableExists {
            return "Refresh"
        }
        return "Create Folder"
    }

    private var primaryButtonIcon: String {
        if !viewModel.status.installDirectoryExists {
            return "folder"
        }
        if !viewModel.status.smapiExecutableExists {
            return "arrow.clockwise"
        }
        return "folder.badge.plus"
    }

    private func primarySetupAction() {
        if !viewModel.status.installDirectoryExists {
            viewModel.chooseInstallFolder()
        } else if !viewModel.status.smapiExecutableExists {
            viewModel.refresh()
        } else {
            viewModel.createModFolder()
        }
    }
}

private struct ConsoleView: View {
    var output: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(output.isEmpty ? "No launch output yet." : output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .textColor))
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .textSelection(.enabled)
                    .id("output")
                    .padding(12)
            }
            .frame(minHeight: 150)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .onChange(of: output) { _ in
                proxy.scrollTo("output", anchor: .bottom)
            }
        }
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

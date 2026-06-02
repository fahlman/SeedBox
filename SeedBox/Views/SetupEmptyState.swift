import SwiftUI

struct SetupEmptyState: View {
    @ObservedObject var viewModel: ModManagerViewModel
    var chooseModsFolder: () -> Void

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
                .disabled(readiness != .needsFolderAccess && !readiness.canCreateModFolder)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var setupTitle: String {
        readiness.setupTitle(modFolderName: viewModel.modFolderName)
    }

    private var setupDetail: String {
        readiness.setupDetail(modFolderName: viewModel.modFolderName)
    }

    private var primaryButtonTitle: String {
        readiness.primarySetupButtonTitle
    }

    private var primaryButtonIcon: String {
        readiness.primarySetupButtonIcon
    }

    private func primarySetupAction() {
        if readiness == .needsFolderAccess {
            chooseModsFolder()
        } else {
            Task {
                await viewModel.createModFolder()
            }
        }
    }

    private var readiness: ModManagerReadiness {
        viewModel.state.readiness
    }
}

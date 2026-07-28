import SwiftUI

struct ModLibrarySidebar: View {
    var presentationState: ModManagerPresentationState
    @Binding var selectedItemID: String
    var selectItem: (String) -> Void

    var body: some View {
        List(selection: selectedItemBinding) {
            Section(AppStrings.Library.library) {
                ForEach(presentationState.builtInSmartModSetItems) { item in
                    sidebarRow(for: item)
                }
            }

            if !presentationState.userSmartModSetItems.isEmpty {
                Section(AppStrings.Library.savedSearches) {
                    ForEach(presentationState.userSmartModSetItems) { item in
                        sidebarRow(for: item)
                    }
                }
            }

            Section(AppStrings.Help.modSetsTitle) {
                ForEach(presentationState.modSetItems) { item in
                    sidebarRow(for: item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppStrings.Library.library)
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
    }

    private func sidebarRow(for item: ModLibraryItem) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(item.title)
                if let baseSetName = item.inheritsFromName {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(AppStrings.Library.inheritsFrom(baseSetName))
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .badge(item.count)
        .tag(item.id)
    }

    private var selectedItemBinding: Binding<String?> {
        Binding(
            get: {
                selectedItemID
            },
            set: { newItemID in
                guard let newItemID else {
                    return
                }
                selectItem(newItemID)
            }
        )
    }

}

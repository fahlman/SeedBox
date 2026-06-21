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
                Section(AppStrings.Library.smartModSets) {
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
        Label(item.title, systemImage: item.systemImage)
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

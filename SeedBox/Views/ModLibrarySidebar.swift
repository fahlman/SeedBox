import SwiftUI

struct ModLibrarySidebar: View {
    var presentationState: ModManagerPresentationState
    @Binding var selectedItemID: String
    var selectItem: (String) -> Void

    var body: some View {
        List(selection: selectedItemBinding) {
            Section(AppStrings.Library.smartModSets) {
                ForEach(SmartModSet.allCases) { smartSet in
                    Label(smartSet.title, systemImage: smartSet.systemImage)
                        .badge(smartSet.count(in: presentationState.state))
                        .tag(ModLibrarySelection.smartID(smartSet))
                }
            }

            Section(AppStrings.Help.modSetsTitle) {
                ForEach(presentationState.modSetSelection.sets) { set in
                    Label(set.name, systemImage: set.isUserEditable ? "folder" : "folder.badge.gearshape")
                        .badge(modCount(for: set))
                        .tag(ModLibrarySelection.modSetID(set.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppStrings.Library.library)
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
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

    private func modCount(for set: ModSet) -> Int {
        presentationState.state.mods.filter { mod in
            !set.disabledFolderTokens.contains(mod.enabledFolderName.normalizedFolderToken)
        }.count
    }
}

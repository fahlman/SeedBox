import SwiftUI

struct ModList: View {
    var mods: [ModInfo]
    var canManageMods: Bool
    var modFolderName: String
    @Binding var selectedModIDs: Set<String>
    var selectedMod: ModInfo?
    var availableUpdate: (ModInfo) -> ModAvailableUpdate?
    var addMods: () -> Void
    var requestSetModEnabled: (ModInfo, Bool) -> Void
    var revealSelectedMod: () -> Void
    var requestDeleteSelectedMod: () -> Void
    @SceneStorage("modList.sortColumn") private var storedSortColumn = ModListSortColumn.mod.rawValue
    @SceneStorage("modList.sortDirection") private var storedSortDirection = ModListSortDirection.forward.rawValue

    private var rows: [ModTableRow] {
        mods.map { mod in
            ModTableRow(mod: mod, availableUpdate: availableUpdate(mod))
        }
        .sorted(using: currentSortOrder)
    }

    var body: some View {
        if mods.isEmpty {
            EmptyModList(
                canManageMods: canManageMods,
                modFolderName: modFolderName,
                addMods: addMods
            )
        } else {
            Table(rows, selection: $selectedModIDs, sortOrder: sortOrderBinding) {
                TableColumn(AppStrings.Table.state, value: \.enabledSortText) { row in
                    Toggle(row.enabledText, isOn: Binding(
                        get: { row.mod.isEnabled },
                        set: { enabled in
                            requestSetModEnabled(row.mod, enabled)
                        }
                    ))
                    .labelsHidden()
                    .disabled(!canManageMods)
                }
                .width(min: 76, ideal: 92, max: 110)

                TableColumn(AppStrings.Table.mod, value: \.nameSortText) { row in
                    ModNameCell(mod: row.mod)
                }

                TableColumn(AppStrings.Table.author, value: \.authorText) { row in
                    Text(row.authorText)
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 170, max: 240)

                TableColumn(AppStrings.Table.type, value: \.typeText) { row in
                    Text(row.typeText)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 150, max: 180)

                TableColumn(AppStrings.Table.updates, value: \.updateSortText) { row in
                    if let availableUpdate = row.availableUpdate {
                        Label(availableUpdate.latestVersion, systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .help(AppStrings.ModInspector.updateAvailable(availableUpdate.latestVersion))
                    } else {
                        Text(row.updateSourceText)
                            .lineLimit(1)
                    }
                }
                .width(min: 110, ideal: 130, max: 170)
            }
            .contextMenu {
                Button {
                    revealSelectedMod()
                } label: {
                    Label(AppStrings.Toolbar.revealInFinder, systemImage: "eye")
                }
                .disabled(selectedMod == nil || !canManageMods)

                Button(role: .destructive) {
                    requestDeleteSelectedMod()
                } label: {
                    Label(AppStrings.Toolbar.deleteMod, systemImage: "trash")
                }
                .disabled(selectedMod == nil || !canManageMods)
            }
        }
    }

    private var sortOrderBinding: Binding<[KeyPathComparator<ModTableRow>]> {
        Binding(
            get: { currentSortOrder },
            set: { newSortOrder in
                guard let descriptor = ModListSortDescriptor(comparator: newSortOrder.first) else {
                    return
                }

                storedSortColumn = descriptor.column.rawValue
                storedSortDirection = descriptor.direction.rawValue
            }
        )
    }

    private var currentSortOrder: [KeyPathComparator<ModTableRow>] {
        let column = ModListSortColumn(rawValue: storedSortColumn) ?? .mod
        let direction = ModListSortDirection(rawValue: storedSortDirection) ?? .forward
        return [column.comparator(direction: direction)]
    }
}

private struct ModListSortDescriptor {
    var column: ModListSortColumn
    var direction: ModListSortDirection

    init?(comparator: KeyPathComparator<ModTableRow>?) {
        guard let comparator,
              let column = ModListSortColumn(comparator: comparator)
        else {
            return nil
        }

        self.column = column
        direction = ModListSortDirection(sortOrder: comparator.order)
    }
}

private enum ModListSortColumn: String {
    case state
    case mod
    case author
    case type
    case updates

    init?(comparator: KeyPathComparator<ModTableRow>) {
        if comparator.keyPath == \ModTableRow.enabledSortText {
            self = .state
        } else if comparator.keyPath == \ModTableRow.nameSortText {
            self = .mod
        } else if comparator.keyPath == \ModTableRow.authorText {
            self = .author
        } else if comparator.keyPath == \ModTableRow.typeText {
            self = .type
        } else if comparator.keyPath == \ModTableRow.updateSortText {
            self = .updates
        } else {
            return nil
        }
    }

    func comparator(direction: ModListSortDirection) -> KeyPathComparator<ModTableRow> {
        switch self {
        case .state:
            return KeyPathComparator(\ModTableRow.enabledSortText, order: direction.sortOrder)
        case .mod:
            return KeyPathComparator(\ModTableRow.nameSortText, order: direction.sortOrder)
        case .author:
            return KeyPathComparator(\ModTableRow.authorText, order: direction.sortOrder)
        case .type:
            return KeyPathComparator(\ModTableRow.typeText, order: direction.sortOrder)
        case .updates:
            return KeyPathComparator(\ModTableRow.updateSortText, order: direction.sortOrder)
        }
    }
}

private enum ModListSortDirection: String {
    case forward
    case reverse

    init(sortOrder: SortOrder) {
        self = sortOrder == .reverse ? .reverse : .forward
    }

    var sortOrder: SortOrder {
        switch self {
        case .forward:
            return .forward
        case .reverse:
            return .reverse
        }
    }
}

import SwiftUI

extension ModManagerView {
    @ViewBuilder
    func sheetContent(
        for sheet: ModManagerSheet,
        presentationState: ModManagerPresentationState
    ) -> some View {
        switch sheet {
        case .modSetEditor(let mode):
            ModSetNameSheet(
                mode: mode,
                availableBaseSets: mode.supportsBaseSelection
                    ? presentationState.availableBaseSets(forEditing: mode.editingSetID)
                    : [],
                onCancel: {
                    presentation.dismissSheet()
                },
                onCommit: { name, parentID in
                    Task {
                        await commitModSetEditor(mode: mode, name: name, parentID: parentID)
                    }
                }
            )
        case .importPreview(let session):
            ModImportPreviewSheet(
                preview: session.preview,
                cancel: {
                    session.discardInBackground()
                    presentation.dismissSheet()
                },
                install: {
                    installPreviewedMods(session)
                }
            )
        case .sourceCleanup(let offer):
            SourceCleanupOfferSheet(
                offer: offer,
                remembersChoice: $presentation.remembersSourceCleanupChoice,
                keepFiles: {
                    Task {
                        await viewModel.keepSourceFiles(
                            for: offer,
                            remembersChoice: presentation.remembersSourceCleanupChoice
                        )
                    }
                    presentation.dismissSheet()
                },
                moveToTrash: {
                    Task {
                        await viewModel.moveSourceFilesToTrash(
                            for: offer,
                            remembersChoice: presentation.remembersSourceCleanupChoice
                        )
                        presentation.dismissSheet()
                    }
                },
                dismissNotice: {
                    Task {
                        await viewModel.dismissSourceCleanupOffer()
                    }
                    presentation.dismissSheet()
                }
            )
        case .problems:
            ProblemsSheet(
                dataStoreIssues: presentationState.state.dataStoreIssues,
                dependencyIssues: presentationState.problemSummary.dependencyIssues,
                invalidFolders: presentationState.problemSummary.invalidFolders,
                duplicateGroups: presentationState.problemSummary.duplicateGroups,
                smapiVersionIssues: presentationState.problemSummary.smapiVersionIssues,
                detectedSMAPIVersion: presentationState.problemSummary.detectedSMAPIVersion,
                lastSessionIssues: presentationState.state.lastSessionIssues,
                lastSessionDate: presentationState.state.lastSessionReport?.generatedAt,
                modPageURLs: presentationState.state.knownModPageURLs,
                canStartBisection: presentationState.canManageMods
                    && presentationState.state.bisectionSession == nil
                    && presentationState.state.mods.filter(\.isEnabled).count >= 2,
                canManageMods: presentationState.canManageMods,
                resolveDuplicates: resolveDuplicateGroup,
                disableMod: { mod in
                    setMod(mod, enabled: false)
                },
                startBisection: startBisection,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .activity:
            ActivitySheet(
                auditTrail: presentationState.auditTrail,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .restoreHistory:
            RestoreHistorySheet(
                archivedMods: presentationState.state.archivedMods,
                currentMods: presentationState.state.mods,
                archiveSummary: presentationState.archiveSummary,
                restore: restoreArchivedMods,
                deletePermanently: deleteArchivedMods,
                revealInFinder: viewModel.revealArchivedModsFolder,
                pruneExpiredArchives: pruneExpiredArchives,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .modSetComparison(let comparison):
            ModSetComparisonSheet(comparison: comparison) {
                presentation.dismissSheet()
            }
        case .bisection:
            if let session = presentationState.state.bisectionSession {
                BisectionSheet(
                    session: session,
                    mods: presentationState.state.mods,
                    reportResult: { problemOccurred in
                        Task {
                            await viewModel.recordBisectionResult(problemOccurred: problemOccurred)
                        }
                    },
                    cancel: {
                        Task {
                            await viewModel.cancelBisection()
                        }
                    }
                )
            }
        }
    }

    var activeSheet: Binding<ModManagerSheet?> {
        Binding(
            get: {
                presentation.sheet
            },
            set: { sheet in
                if sheet == nil {
                    switch presentation.sheet {
                    case .importPreview(let session):
                        session.discardInBackground()
                    case .sourceCleanup:
                        Task {
                            await viewModel.dismissSourceCleanupOffer()
                        }
                    default:
                        break
                    }
                }
                presentation.sheet = sheet
            }
        )
    }

    @ViewBuilder
    func alertActions(for alert: ModManagerAlert) -> some View {
        switch alert {
        case .deleteMod(let mod):
            Button(AppStrings.Common.delete, role: .destructive) {
                Task {
                    let didDelete = await viewModel.deleteMod(mod)
                    if didDelete {
                        removeSelectedModID(mod.id)
                    }
                    if didDelete, let undoManager {
                        ModUndoRegistrar.registerModDeletion(
                            in: undoManager,
                            viewModel: viewModel,
                            folderName: mod.enabledFolderName
                        )
                    }
                    presentation.dismissAlert()
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
            }
        case .deleteModSet(let set):
            Button(AppStrings.Common.delete, role: .destructive) {
                Task {
                    let didDelete = await viewModel.deleteModSet(set)
                    if didDelete, let undoManager {
                        ModUndoRegistrar.registerModSetExistence(
                            in: undoManager,
                            viewModel: viewModel,
                            set: set,
                            deleted: true,
                            actionName: AppStrings.Undo.deleteModSet
                        )
                    }
                    presentation.dismissAlert()
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
            }
        case .dependency(let confirmation):
            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
            }

            if let repairTitle = confirmation.repairTitle,
               let repairAction = confirmation.repairAction {
                Button(repairTitle, role: confirmation.repairRole) {
                    performDependencyAction(repairAction)
                }
            }

            Button(confirmation.confirmTitle, role: confirmation.confirmRole) {
                performDependencyAction(confirmation.action)
            }
        case .lastSessionNotice:
            Button(AppStrings.Alerts.reviewProblems) {
                presentation.dismissAlert()
                syncLaunchModUpdateCheck(presentationState)
                openRoute(.problems)
                Task {
                    await viewModel.dismissLastSessionNotice()
                }
            }

            Button(AppStrings.Alerts.notNow, role: .cancel) {
                presentation.dismissAlert()
                syncLaunchModUpdateCheck(presentationState)
                Task {
                    await viewModel.dismissLastSessionNotice()
                }
            }
        case .modUpdateNetworkAccess:
            Button(AppStrings.Alerts.enableAndCheckNow) {
                presentation.dismissAlert()
                Task {
                    await viewModel.setChecksForModUpdates(true)
                    await viewModel.checkForModUpdates()
                }
            }

            Button(AppStrings.Alerts.notNow, role: .cancel) {
                presentation.dismissAlert()
            }
        case .message:
            Button(AppStrings.Common.ok) {
                presentation.dismissAlert()
            }
        }
    }

    @ViewBuilder
    func alertMessage(
        for alert: ModManagerAlert,
        presentationState: ModManagerPresentationState
    ) -> some View {
        switch alert {
        case .deleteMod(let mod):
            Text(AppStrings.Alerts.deleteModMessage(
                mod.displayName,
                retentionDays: presentationState.archiveRetentionDays
            ))
        case .deleteModSet(let set):
            Text(AppStrings.Alerts.deleteModSetMessage(set.name))
        case .dependency(let confirmation):
            Text(confirmation.message)
        case .lastSessionNotice(let notice):
            Text(lastSessionNoticeMessage(for: notice))
        case .modUpdateNetworkAccess:
            Text(AppStrings.Alerts.allowModUpdateNetworkAccessMessage)
        case .message(let alert):
            Text(alert.message)
        }
    }

    func lastSessionNoticeMessage(for notice: LastSessionNotice) -> String {
        var sentences: [String] = []
        if notice.skippedModCount > 0 {
            sentences.append(AppStrings.Alerts.lastSessionSkippedMods(count: notice.skippedModCount))
        }
        if notice.erroringModCount > 0 {
            sentences.append(AppStrings.Alerts.lastSessionErroringMods(count: notice.erroringModCount))
        }
        return sentences.joined(separator: " ")
    }

    var alertIsPresented: Binding<Bool> {
        Binding(
            get: { presentation.alert != nil },
            set: { isPresented in
                if !isPresented {
                    if case .lastSessionNotice = presentation.alert {
                        Task {
                            await viewModel.dismissLastSessionNotice()
                        }
                    }
                    presentation.dismissAlert()
                    syncLaunchModUpdateCheck(presentationState)
                }
            }
        )
    }
}

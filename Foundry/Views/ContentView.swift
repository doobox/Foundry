import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct HTMLSourceEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let partID: UUID
    let propertyKey: PartProperty.Key
    let propertyPath: [Int]
    let source: HTMLPartSource
}

private struct PageTextEditRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let partID: UUID
    let propertyKey: PartProperty.Key
    let propertyPath: [Int]
    let value: String
}

private struct PageDeletionRequest {
    let pageID: UUID
    let title: String
    let subpageCount: Int
}

struct ContentView: View {
    @ObservedObject var document: FoundryDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedPageID: UUID?
    @State private var inspectedPageID: UUID?
    @State private var selectedPageFolderID: UUID?
    @State private var selectedPageAssetID: UUID?
    @State private var expandedPageTreeItemIDs: Set<UUID> = []
    @State private var selectedAssetLibraryNodeID: UUID?
    /// Selection in the Assets panel's Library/Dev tabs — a collection
    /// identifier or a file path.
    @State private var selectedAssetCollectionItemID: String?
    @State private var selectedPartIDs: Set<UUID> = []
    @State private var selectedPartSelectionOrder: [UUID] = []
    @State private var selectedPartID: UUID?
    @State private var expandedStructurePartIDs: Set<UUID> = []
    @State private var selectedPrimitive: CanvasPrimitiveSelection?
    @State private var selectedLibraryPartType: PartType?
    @State private var copiedParts: [PartNode] = []
    @State private var editsSharedReusableDefinition = false
    @State private var workspaceLayout = WorkspacePresetStore.initialLayoutForNewDocument()
    @State private var detachedPanelWindows = DetachedPanelWindowCoordinator()
    @State private var frameworkWindowID = UUID()
    @State private var siteSettingsWindowID = UUID()
    @State private var exportErrorMessage: String?
    @State private var publishingCommandDispatcher = PublishingCommandDispatcher()
    @State private var showsPublishingProgress = false
    @State private var publishingState: PublishingModalState = .preparing
    @State private var publishingTask: Task<Void, Never>?
    @State private var publishingChangeTask: Task<Void, Never>?
    @State private var publishingChangesByTreeItem: [UUID: PublishingChange] = [:]
    @State private var previewSessionID = UUID()
    @State private var previewSessionApplicationIdentifier: String?
    @State private var isPreviewSessionOpen = false
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var browserPreviewServer = PreviewServer()
    @State private var browserPreviewURL: URL?
    @State private var browserPreviewRevision: UInt64?
    @State private var browserPreviewPackageRevision: Int?
    @State private var canvasEditorOptions = CanvasEditorOptions()
    @State private var partCatalog = PartPackageCatalog.shared
    @State private var canvasViewportWidth = 390.0
    @State private var selectedAppearance = SiteAppearance.light
    private var canvasAppearance: SiteAppearance {
        document.site.appearanceMode.permits(selectedAppearance) ? selectedAppearance :
            (document.site.appearanceMode == .dark ? .dark : .light)
    }
    @State private var htmlSourceEditRequest: HTMLSourceEditRequest?
    @State private var pageTextEditRequest: PageTextEditRequest?
    @State private var pageDeletionRequest: PageDeletionRequest?
    @State private var canvasReusablePartName: String?
    @State private var canvasGlobalPartName: String?
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.externalPreviewAutoReload)
    private var externalPreviewAutoReload = false
    @AppStorage(AppPreferenceKey.previewApplication)
    private var previewApplicationIdentifier = PreviewApplicationSelection.systemDefault
    @AppStorage(AppPreferenceKey.automaticallyChecksPartUpdates)
    private var automaticallyChecksPartUpdates = false

    private var renderer: any PageRendering {
        HTMLPageRenderer(site: document.site, appearance: canvasAppearance, packageRevision: partCatalog.revision)
    }

    var body: some View {
        let _ = partCatalog.revision
        DockingWorkspaceView(
            layout: $workspaceLayout,
            canvasEditorOptions: $canvasEditorOptions,
            canvasViewportWidth: $canvasViewportWidth,
            canvasScreens: document.site.framework.screens,
            canvasAppearance: $selectedAppearance,
            appearanceMode: document.site.appearanceMode,
            openProjectSettings: {
                openSiteSettings(section: .general)
            },
            openFrameworkEditor: {
                FrameworkWindowRegistry.shared.register(
                    id: frameworkWindowID,
                    document: document,
                    undoManager: undoManager
                )
                openWindow(id: "framework-editor", value: frameworkWindowID)
            },
            previewSite: previewSite,
            publishSite: { publishSite() },
            publishingDestinations: validPublishingDestinations,
            defaultPublishingDestinationID: document.site.defaultPublishingDestinationID,
            selectPublishingDestination: { editor.setDefaultPublishingDestination(id: $0) },
            republishAllFiles: { publishSite(forceAllFiles: true) },
            openPublishingSetup: { openSiteSettings(section: .publishing) },
            showPartUpdates: {
                openWindow(id: "available-part-updates")
            }
        ) { panel in
            workspacePanel(panel)
        }
        .environment(\.canvasAppearance, canvasAppearance)
        .frame(
            minWidth: EditorWindowSize.minimumWidth,
            idealWidth: EditorWindowSize.idealWidth,
            maxWidth: .infinity,
            minHeight: EditorWindowSize.minimumHeight,
            idealHeight: EditorWindowSize.idealHeight,
            maxHeight: .infinity
        )
        .task {
            guard automaticallyChecksPartUpdates else { return }
            _ = await PartUpdateManager.shared.automaticCheckIfNeeded()
        }
        .onChange(of: workspaceLayout) {
            workspaceLayout.persist()
        }
        .background {
            DetachedPanelPresenter(
                layout: $workspaceLayout,
                coordinator: detachedPanelWindows,
                content: { panel in AnyView(workspacePanel(panel)) }
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            appearance.apply()
            selectedPageID = selectedPageID ?? document.site.pages.first?.id
            inspectedPageID = inspectedPageID ?? selectedPageID
            schedulePublishingChangeRefresh(immediately: true)
        }
        .onDisappear {
            dismissWindow(id: "framework-editor", value: frameworkWindowID)
            FrameworkWindowRegistry.shared.remove(id: frameworkWindowID)
            dismissWindow(id: "site-settings", value: siteSettingsWindowID)
            ProjectSettingsWindowRegistry.shared.remove(id: siteSettingsWindowID)
        }
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
        .onChange(of: externalPreviewAutoReload) { _, isEnabled in
            if !isEnabled {
                previewRefreshTask?.cancel()
            } else {
                schedulePreviewRefresh()
            }
        }
        .onChange(of: selectedPageID) { _, _ in
            schedulePreviewRefresh(selectionOnly: true)
        }
        .onChange(of: document.site.pages.map(\.id)) { _, pageIDs in
            if let selectedPageID, pageIDs.contains(selectedPageID) {
                return
            }
            selectedPageID = pageIDs.first
            selectedPartID = nil
        }
        .onChange(of: selectedPartID) { _, partID in
            if partID != nil {
                selectedTemplateNodeID = nil
                selectedGlobalNodeID = nil
            }
            Task { @MainActor in
                await Task.yield()
                guard selectedPartID == partID else { return }
                synchronizePrimaryPartSelection(partID)
            }
        }
        .onChange(of: inspectedPageID) { _, pageID in
            if pageID != nil {
                selectedTemplateNodeID = nil
                selectedGlobalNodeID = nil
            }
        }
        .onChange(of: selectedPartIDs) { previousPartIDs, partIDs in
            Task { @MainActor in
                await Task.yield()
                guard selectedPartIDs == partIDs else { return }
                synchronizePartSelection(previous: previousPartIDs, current: partIDs)
            }
        }
        .onDeleteCommand {
            if selectedPrimitive != nil { return }
            guard !selectedPartIDs.isEmpty else { return }
            deletePart()
        }
        .focusedSceneValue(\.publishingCommandDispatcher, publishingCommandDispatcher)
        .onChange(of: publishingCommandDispatcher.request?.id) {
            guard let command = publishingCommandDispatcher.request?.command else { return }
            handlePublishingCommand(command)
        }
        .onChange(of: document.mutationEvent.revision) {
            handleMutationImpact(document.mutationEvent.impact)
        }
        .onChange(of: partCatalog.revision) {
            handleMutationImpact(.package)
        }
        .onDisappear {
            previewRefreshTask?.cancel()
            publishingTask?.cancel()
            publishingChangeTask?.cancel()
            Task { await browserPreviewServer.stop() }
        }
        .sheet(isPresented: $showsPublishingProgress) {
            PublishingProgressView(
                siteName: document.site.name,
                state: publishingState,
                cancel: { publishingTask?.cancel() },
                dismiss: { showsPublishingProgress = false }
            )
            .interactiveDismissDisabled(publishingState.isActive)
        }
        .sheet(item: $htmlSourceEditRequest) { request in
            HTMLSourceEditorView(
                source: request.source,
                cancel: { htmlSourceEditRequest = nil },
                save: { source in
                    saveHTMLSource(source, request: request)
                    htmlSourceEditRequest = nil
                }
            )
        }
        .sheet(item: $pageTextEditRequest) { request in
            PageTextEditorView(
                value: request.value,
                framework: document.site.framework,
                pages: document.site.pages,
                folders: document.site.pageFolders,
                assets: document.site.assets,
                publicURL: document.site.publicURL,
                cancel: { pageTextEditRequest = nil },
                save: { value in
                    savePageText(value, request: request)
                    pageTextEditRequest = nil
                }
            )
        }
        .alert("Site Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "The site could not be generated.")
        }
        .alert(
            pageDeletionAlertTitle,
            isPresented: pageDeletionAlertBinding
        ) {
            Button("Delete Page Only", role: .destructive) {
                guard let request = pageDeletionRequest else { return }
                performPageDeletion(request.pageID, includingSubpages: false)
                pageDeletionRequest = nil
            }
            Button("Delete Page and Subpages", role: .destructive) {
                guard let request = pageDeletionRequest else { return }
                performPageDeletion(request.pageID, includingSubpages: true)
                pageDeletionRequest = nil
            }
            Button("Cancel", role: .cancel) {
                pageDeletionRequest = nil
            }
        } message: {
            let count = pageDeletionRequest?.subpageCount ?? 0
            Text(
                count == 1
                    ? "This page contains one subpage. Keeping it will move it up one level."
                    : "This page contains \(count) subpages. Keeping them will move its direct subpages up one level."
            )
        }
        .alert("Save Template", isPresented: canvasReusableAlertBinding) {
            TextField("Name", text: canvasReusableNameBinding)
            Button("Cancel", role: .cancel) { canvasReusablePartName = nil }
            Button("Save") {
                guard let name = canvasReusablePartName else { return }
                saveReusablePart(name)
                canvasReusablePartName = nil
            }
            .disabled(canvasReusablePartName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("The selected part and its children will be available in the Project library.")
        }
        .alert("Save Global Part", isPresented: canvasGlobalAlertBinding) {
            TextField("Name", text: canvasGlobalNameBinding)
            Button("Cancel", role: .cancel) { canvasGlobalPartName = nil }
            Button("Save") {
                guard let name = canvasGlobalPartName else { return }
                saveGlobalPart(name)
                canvasGlobalPartName = nil
            }
            .disabled(canvasGlobalPartName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        } message: {
            Text("Every linked instance will update when this global part is edited.")
        }
    }

    @ViewBuilder
    private func workspacePanel(_ panel: WorkspacePanel) -> some View {
        switch panel {
        case .pages:
            PagesPanel(
                pages: document.site.pages,
                folders: document.site.pageFolders,
                assets: document.site.assets,
                publishingChanges: publishingChangesByTreeItem,
                selectedPageID: inspectablePageSelection,
                selectedFolderID: inspectablePageFolderSelection,
                selectedAssetID: inspectablePageAssetSelection,
                expandedItemIDs: $expandedPageTreeItemIDs,
                addPage: { addPage(at: $0) },
                addFolder: addPageFolder,
                renameFolder: { editor.renamePageFolder(id: $0, name: $1) },
                deleteFolder: { editor.removePageFolder(id: $0, includingContents: $1) },
                duplicatePage: duplicatePage,
                renamePage: { editor.renamePageFromOutline(id: $0, title: $1) },
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                moveTreeItem: { editor.movePageTreeItem($0, to: $1) },
                importURLs: importPageTreeURLs
            )
        case .parts:
            PartLibraryPanel(
                selectedType: inspectableLibraryPartSelection,
                addToPageEnd: addPartToPageEnd
            )
        case .reusableParts:
            ReusablePartLibraryPanel(
                projectNodes: document.site.projectTemplateLibrary,
                librarySections: libraryTemplateSections,
                devSections: devTemplateSections,
                selectedNodeID: inspectableTemplateSelection,
                renameDefinition: renameTemplateNode(_:to:),
                deleteDefinition: deleteTemplateDefinition(_:),
                duplicateDefinition: duplicateTemplateDefinition(_:),
                revealDefinition: {
                    guard !isProjectTemplateNode($0) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([ReusablePartLibrary.shared.bundleURL(forID: $0)])
                },
                createFolder: createTemplateFolder(named:inSection:),
                renameFolder: renameTemplateFolder(_:to:),
                deleteFolder: deleteTemplateFolder(_:),
                moveNode: moveTemplateNode(_:toSection:placement:),
                saveDraggedParts: saveDraggedPartsAsTemplates(_:inSection:),
                addToLibrary: addProjectTemplateToLibrary(_:),
                addToProject: addLibraryTemplateToProject(_:)
            )
        case .globalParts:
            GlobalPartLibraryPanel(
                library: document.site.globalPartLibrary,
                selectedNodeID: inspectableGlobalSelection,
                renameDefinition: renameGlobalPart,
                deleteDefinition: deleteGlobalPart,
                duplicateDefinition: { _ = editor.duplicateGlobalPart(definitionID: $0) },
                createFolder: { _ = editor.createGlobalPartFolder(named: $0) },
                renameFolder: { editor.renameGlobalPartFolder(id: $0, to: $1) },
                deleteFolder: { editor.deleteGlobalPartFolder(id: $0) },
                moveNode: { editor.moveGlobalPartNode(id: $0, to: $1) },
                saveDraggedParts: saveDraggedPartsAsGlobals
            )
        case .structure:
            StructurePanel(
                page: selectedPage,
                globalPartNames: Dictionary(
                    uniqueKeysWithValues: document.site.globalParts.map { ($0.id, $0.name) }
                ),
                selectedPartIDs: $selectedPartIDs,
                selectedPartID: inspectablePartSelection,
                isPageSelected: inspectableStructurePageSelection,
                expandedPartIDs: $expandedStructurePartIDs,
                renamePart: renamePart,
                canMovePartsToPlacement: canMovePartsFromStructure,
                movePartsToPlacement: movePartsFromStructure,
                insertPart: insertPartFromLibrary,
                insertReusablePart: insertReusablePartFromLibrary,
                insertGlobalPart: insertGlobalPartFromLibrary,
                duplicatePart: duplicatePart,
                copyPart: copyPart,
                pastePart: pastePart,
                movePart: movePart,
                outdentPart: outdentPart,
                deletePart: deletePart,
                canPastePart: !copiedParts.isEmpty,
                saveReusablePart: saveReusablePart,
                saveGlobalPart: saveGlobalPart,
                setGlobalPartLinked: { partID, isLinked in
                    editor.setGlobalPartLinked(partID: partID, isLinked: isLinked)
                    selectedPartIDs = [partID]
                    selectedPartID = partID
                },
                explodeGlobalPart: { partID in
                    editor.explodeGlobalPart(partID: partID)
                    selectedPartIDs = [partID]
                    selectedPartID = partID
                }
            )
        case .assets:
            AssetsPanel(
                library: document.site.assetLibrary.resourcesOnly,
                assetContents: document.assetContents,
                selectedNodeID: inspectableAssetLibrarySelection,
                selectedCollectionItemID: inspectableAssetCollectionSelection,
                importFiles: importAssets,
                importURLs: importAssetURLs,
                importCollectionFiles: { files in
                    let importedIDs = AssetCollectionLibrary.shared.importFiles(
                        files,
                        into: document,
                        undoManager: undoManager
                    )
                    if let lastID = importedIDs.last {
                        selectedAssetLibraryNodeID = lastID
                    }
                },
                createFolder: { name in
                    let folderID = document.createAssetFolder(named: name, at: assetInsertionPlacement, undoManager: undoManager)
                    selectedAssetLibraryNodeID = folderID
                },
                moveNode: { document.moveAssetNodeToResources(id: $0, to: $1, undoManager: undoManager) },
                deleteNodes: deleteAssetLibraryNodes,
                renameAsset: { document.renameAsset(id: $0, filename: $1, undoManager: undoManager) },
                renameFolder: { document.renameAssetFolder(id: $0, name: $1, undoManager: undoManager) }
            )
            .onChange(of: selectedAssetLibraryNodeID) { _, selectedID in
                guard selectedID != nil else { return }
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedPartID = nil
                selectedTemplateNodeID = nil
                selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        case .developer:
            DeveloperPanel()
        case .canvas:
            CanvasView(
                site: document.site,
                page: selectedPage,
                language: document.site.language,
                framework: document.site.framework,
                assets: document.assetContents,
                assetRevision: document.assetRevision,
                mutationEvent: document.mutationEvent,
                partPackageRevision: partCatalog.revision,
                isPartCatalogReady: !partCatalog.isInitialLoading,
                selectedPartIDs: selectedPartIDs,
                primarySelectedPartID: selectedPartID,
                selectedPrimitive: selectedPrimitive,
                editorOptions: canvasEditorOptions,
                renderer: renderer,
                canPastePart: !copiedParts.isEmpty,
                canClearImage: canClearCanvasImage,
                handleMessage: handleCanvasMessage,
                handleContextMenuAction: handleCanvasContextMenuAction,
                viewportWidth: $canvasViewportWidth
            )
        case .inspector:
            if partCatalog.isInitialLoading,
               selectedPart != nil || selectedLibraryPartType != nil {
                PartCatalogLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InspectorView(
                    page: inspectedPage,
                    currentPage: selectedPage,
                    folder: selectedPageFolder,
                    asset: selectedPageAsset,
                    assetLibraryNode: selectedAssetLibraryNode,
                    assetLibrary: document.site.assetLibrary,
                    assetContents: document.assetContents,
                    folders: document.site.pageFolders,
                    pages: document.site.pages,
                    publicURL: document.site.publicURL,
                    part: selectedPart,
                    selectedParts: selectedParts,
                    allowsMultiPartEditing: allowsMultiPartEditing,
                    libraryPartType: selectedLibraryPartType,
                    assetCollectionSelection: selectedAssetCollectionContext,
                    importCollectionFiles: { files in
                        _ = AssetCollectionLibrary.shared.importFiles(
                            files,
                            into: document,
                            undoManager: undoManager
                        )
                    },
                    templateContext: selectedTemplateContext,
                    insertTemplate: { _ = insertReusablePartFromLibrary($0, .end) },
                    globalDefinition: selectedGlobalDefinition,
                    insertGlobalPart: { _ = insertGlobalPartFromLibrary($0, .end) },
                    framework: document.site.framework,
                    assets: document.site.assets,
                    editor: editor,
                    reusableDefinition: selectedReusableDefinition,
                    isGlobalOverride: selectedGlobalContext?.isOverridden == true,
                    setGlobalOverride: setSelectedGlobalOverride,
                    breakpoint: activeCanvasBreakpoint,
                    assetUsageCount: assetUsageCount,
                    renameAsset: { document.renameAsset(id: $0, filename: $1, undoManager: undoManager) },
                    renameAssetFolder: { document.renameAssetFolder(id: $0, name: $1, undoManager: undoManager) },
                    importMedia: importMediaAsset,
                    editsSharedDefinition: $editsSharedReusableDefinition
                )
            }
        }
    }

    private func schedulePublishingChangeRefresh(immediately: Bool = false) {
        guard !partCatalog.isLoading else { return }
        publishingChangeTask?.cancel()
        publishingChangeTask = Task {
            if !immediately {
                try? await Task.sleep(for: .milliseconds(750))
            }
            guard !Task.isCancelled else { return }
            guard !partCatalog.isLoading else { return }
            var site = document.site
            site.synchronizeLegacyPublishingFields()
            let assets = document.assetContents
            let manifests = document.publishingManifests
            let localDirectory = site.publishingDestination == .local
                ? site.defaultPublishingDestinationID.flatMap { PublishingDestinationStore.url(for: site.id, destinationID: $0) }
                : nil
            let renderTask = Task.detached(priority: .utility) {
                let bundle = StaticSiteRenderer().render(site: site, assets: assets)
                guard !Task.isCancelled else { return [UUID: PublishingChange]() }
                let previous = manifests.manifest(
                    for: site,
                    destinationID: site.defaultPublishingDestinationID,
                    localDirectory: localDirectory
                )
                let changesByPath = PublishingPlan.changes(bundle: bundle, previous: previous)
                var changes: [UUID: PublishingChange] = [:]
                for page in site.pages {
                    changes[page.id] = changesByPath[StaticSiteRenderer.outputPath(for: page, in: site)]
                }
                for asset in site.assets {
                    guard let path = StaticSiteRenderer.customExportPath(for: asset, in: site) else { continue }
                    changes[asset.id] = changesByPath[path]
                }
                return changes
            }
            let result = await withTaskCancellationHandler {
                await renderTask.value
            } onCancel: {
                renderTask.cancel()
            }
            guard !Task.isCancelled else { return }
            publishingChangesByTreeItem = result
        }
    }

    private func handleMutationImpact(_ impact: ProjectMutationImpact) {
        guard impact.affectsRenderedOutput else {
            schedulePublishingChangeRefresh()
            return
        }
        // Editing records dirtiness; it must not export the entire site after
        // every gesture just to recompute status badges. Exact file comparison
        // still runs when opening/configuring publishing and after publishing.
        publishingChangeTask?.cancel()
        markPublishingChangesDirty(for: impact)
        schedulePreviewRefresh()
    }

    private func markPublishingChangesDirty(for impact: ProjectMutationImpact) {
        func markModified(_ id: UUID) {
            if publishingChangesByTreeItem[id] != .new {
                publishingChangesByTreeItem[id] = .modified
            }
        }

        func markAllPages() {
            document.site.pages.forEach { markModified($0.id) }
        }

        switch impact {
        case .partProperty(let partID, _):
            if let page = document.site.pages.first(where: { $0.parts.node(withID: partID) != nil }) {
                markModified(page.id)
            } else {
                markAllPages()
            }
        case .partProperties(let partIDs, _):
            let affectedPageIDs = Set(document.site.pages.compactMap { page in
                partIDs.contains { page.parts.node(withID: $0) != nil } ? page.id : nil
            })
            if affectedPageIDs.isEmpty {
                markAllPages()
            } else {
                affectedPageIDs.forEach(markModified)
            }
        case .partStructure(let ownerID):
            if let ownerID,
               let page = document.site.pages.first(where: { $0.parts.node(withID: ownerID) != nil }) {
                markModified(page.id)
            } else {
                markAllPages()
            }
        case .assets:
            markAllPages()
            document.site.assets.forEach { markModified($0.id) }
        case .page, .framework, .package:
            markAllPages()
        case .publishingOnly:
            break
        }
    }

    private var editor: ProjectEditor {
        ProjectEditor(document: document, undoManager: undoManager)
    }

    private var pageDeletionAlertTitle: String {
        guard let pageDeletionRequest else { return "Delete Page?" }
        return "Delete “\(pageDeletionRequest.title)”?"
    }

    private var inspectablePageSelection: Binding<UUID?> {
        Binding(
            get: { inspectedPageID ?? selectedPageID },
            set: { pageID in
                inspectedPageID = pageID
                guard pageID != nil else { return }
                selectedPageID = pageID
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedPartID = nil
                selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private var inspectablePageFolderSelection: Binding<UUID?> {
        Binding(
            get: { selectedPageFolderID },
            set: { folderID in
                selectedPageFolderID = folderID
                guard folderID != nil else { return }
                inspectedPageID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedPartID = nil
                selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private var inspectablePageAssetSelection: Binding<UUID?> {
        Binding(
            get: { selectedPageAssetID },
            set: { assetID in
                selectedPageAssetID = assetID
                guard assetID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedAssetLibraryNodeID = nil
                selectedPartID = nil
                selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private var inspectableAssetLibrarySelection: Binding<UUID?> {
        Binding(
            get: { selectedAssetLibraryNodeID },
            set: { nodeID in
                selectedAssetLibraryNodeID = nodeID
                guard nodeID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedPartID = nil
                selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    /// Selecting a collection or file in the Library/Dev tabs takes over the
    /// Inspector, clearing every other inspectable selection.
    private var inspectableAssetCollectionSelection: Binding<String?> {
        Binding(
            get: { selectedAssetCollectionItemID },
            set: { itemID in
                selectedAssetCollectionItemID = itemID
                guard itemID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedPartID = nil
                selectedPrimitive = nil
                selectedLibraryPartType = nil
                selectedTemplateNodeID = nil
                selectedGlobalNodeID = nil
            }
        )
    }

    /// Resolves the Library/Dev tab selection against the loaded packs; a
    /// stale identifier resolves to nothing and the Inspector falls through.
    private var selectedAssetCollectionContext: AssetCollectionInspectorSelection? {
        guard let selectedAssetCollectionItemID else { return nil }
        for source in AssetCollectionLibrary.shared.sources {
            for collection in source.collections {
                if collection.identifier == selectedAssetCollectionItemID {
                    return .collection(collection, source: source)
                }
                if let file = collection.files.first(where: { $0.id == selectedAssetCollectionItemID }) {
                    return .file(file, collection: collection, source: source)
                }
            }
        }
        if let context = AssetCollectionLibrary.shared.folderContext(withID: selectedAssetCollectionItemID),
           let source = AssetCollectionLibrary.shared.source(containing: context.collection.identifier) {
            return .folder(context.folder, collection: context.collection, source: source)
        }
        return nil
    }

    private var inspectablePartSelection: Binding<UUID?> {
        Binding(
            get: { selectedPartID },
            set: { partID in
                selectedPrimitive = nil
                selectedPartID = partID
                guard partID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private var inspectableStructurePageSelection: Binding<Bool> {
        Binding(
            get: {
                guard let selectedPage else { return false }
                return selectedPartIDs.isEmpty && inspectedPageID == selectedPage.id
            },
            set: { isSelected in
                guard let selectedPage else { return }
                if isSelected {
                    selectedPrimitive = nil
                    selectedPartIDs = []
                    selectedPartID = nil
                    inspectedPageID = selectedPage.id
                    selectedPageFolderID = nil
                    selectedPageAssetID = nil
                    selectedAssetLibraryNodeID = nil
                    selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
                    selectedAssetCollectionItemID = nil
                } else if inspectedPageID == selectedPage.id {
                    inspectedPageID = nil
                }
            }
        )
    }

    private var inspectableLibraryPartSelection: Binding<PartType?> {
        Binding(
            get: { selectedLibraryPartType },
            set: { type in
                selectedLibraryPartType = type
                guard type != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedPartID = nil
                selectedPrimitive = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )
    }

    private var selectedPage: Page? {
        document.site.pages.first(where: { $0.id == selectedPageID })
            ?? document.site.pages.first
    }

    private var inspectedPage: Page? {
        guard let inspectedPageID else { return nil }
        return document.site.pages.first(where: { $0.id == inspectedPageID })
    }

    private var selectedPageFolder: PageFolder? {
        guard let selectedPageFolderID else { return nil }
        return document.site.pageFolders.first(where: { $0.id == selectedPageFolderID })
    }

    private var selectedPageAsset: ProjectAsset? {
        guard let selectedPageAssetID else { return nil }
        return document.site.assets.first(where: { $0.id == selectedPageAssetID })
    }

    private var selectedAssetLibraryNode: ProjectAssetNode? {
        guard let selectedAssetLibraryNodeID else { return nil }
        return document.site.assetLibrary.node(withID: selectedAssetLibraryNodeID)
    }

    private var activeCanvasBreakpoint: ResponsiveBreakpoint {
        ResponsiveBreakpoint.forViewportWidth(canvasViewportWidth, screens: document.site.framework.screens)
    }

    private var selectedPart: PartNode? {
        guard let selectedPartID else {
            return nil
        }
        return selectedPage?.parts.node(withID: selectedPartID)
    }

    private var selectedParts: [PartNode] {
        guard let selectedPage else { return [] }
        func flattened(_ nodes: [PartNode]) -> [PartNode] {
            nodes.flatMap { [$0] + flattened($0.children) }
        }
        let ordered = flattened(selectedPage.parts).filter { selectedPartIDs.contains($0.id) }
        let sourceOfTruthID = selectedPartSelectionOrder.last ?? selectedPartID
        guard let sourceOfTruthID,
              let primaryIndex = ordered.firstIndex(where: { $0.id == sourceOfTruthID }) else {
            return ordered
        }
        var result = ordered
        let primary = result.remove(at: primaryIndex)
        result.insert(primary, at: 0)
        return result
    }

    private func partDocumentOrderIndex(_ id: UUID) -> Int {
        guard let selectedPage else { return .max }
        func flattenedIDs(_ nodes: [PartNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        return flattenedIDs(selectedPage.parts).firstIndex(of: id) ?? .max
    }

    private func synchronizePrimaryPartSelection(_ partID: UUID?) {
        editsSharedReusableDefinition = false
        if selectedPrimitive?.partID != partID {
            selectedPrimitive = nil
        }
        guard let partID else {
            selectedPartIDs = []
            return
        }
        if !selectedPartIDs.contains(partID) {
            selectedPartIDs = [partID]
        }
        selectedLibraryPartType = nil
        selectedTemplateNodeID = nil
        selectedGlobalNodeID = nil
        inspectedPageID = nil
        selectedPageFolderID = nil
        selectedPageAssetID = nil
        selectedAssetLibraryNodeID = nil
    }

    private func synchronizePartSelection(previous previousPartIDs: Set<UUID>, current partIDs: Set<UUID>) {
        selectedPartSelectionOrder.removeAll { !partIDs.contains($0) }
        var addedPartIDs = partIDs.subtracting(previousPartIDs)
            .sorted { lhs, rhs in
                partDocumentOrderIndex(lhs) < partDocumentOrderIndex(rhs)
            }
        if let selectedPartID,
           let primaryIndex = addedPartIDs.firstIndex(of: selectedPartID) {
            addedPartIDs.append(addedPartIDs.remove(at: primaryIndex))
        }
        selectedPartSelectionOrder.append(contentsOf: addedPartIDs.filter {
            !selectedPartSelectionOrder.contains($0)
        })
        if partIDs.count != 1 || selectedPrimitive.map({ !partIDs.contains($0.partID) }) == true {
            selectedPrimitive = nil
        }
        if !addedPartIDs.isEmpty {
            selectedPartID = selectedPartSelectionOrder.last
        } else if let selectedPartID, !partIDs.contains(selectedPartID) {
            self.selectedPartID = selectedPartSelectionOrder.last
        } else if selectedPartID == nil {
            selectedPartID = selectedPartSelectionOrder.last
        }
        guard !partIDs.isEmpty else { return }
        selectedLibraryPartType = nil
        selectedTemplateNodeID = nil
        selectedGlobalNodeID = nil
        inspectedPageID = nil
        selectedPageFolderID = nil
        selectedPageAssetID = nil
        selectedAssetLibraryNodeID = nil
    }

    private var allowsMultiPartEditing: Bool {
        guard selectedParts.count > 1,
              let type = selectedParts.first?.type.rawValue,
              selectedParts.allSatisfy({ $0.type.rawValue == type }) else { return false }
        // A linked global edits its shared definition rather than just the selected
        // instance. Keep that wider operation explicit instead of hiding it inside
        // a local multi-edit.
        return selectedParts.allSatisfy { part in
            guard let context = document.site.globalPartContext(containing: part.id) else { return true }
            return context.isOverridden
        }
    }

    private var topLevelSelectedPartIDs: [UUID] {
        topLevelPartIDs(from: selectedPartIDs)
    }

    private func topLevelPartIDs(from requestedIDs: Set<UUID>) -> [UUID] {
        guard let selectedPage else { return [] }
        func flattenedIDs(_ nodes: [PartNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        return flattenedIDs(selectedPage.parts).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.parts.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
    }

    private var selectedReusableDefinition: ReusablePartDefinition? {
        guard let definitionID = selectedGlobalContext?.definitionID else { return nil }
        return document.site.globalParts.first(where: { $0.id == definitionID })
    }

    private var selectedGlobalContext: (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let selectedPartID else { return nil }
        return document.site.globalPartContext(containing: selectedPartID)
    }

    private func setSelectedGlobalOverride(_ isOverridden: Bool) {
        guard let selectedPartID else { return }
        editor.setGlobalPartLinked(partID: selectedPartID, isLinked: !isOverridden)
    }

    private func handleCanvasMessage(_ message: CanvasMessage) {
        guard let page = selectedPage else { return }

        switch message.event {
        case .clearSelection:
            selectedPrimitive = nil
            selectedPartIDs = []
            selectedPartID = nil
        case .selectPart:
            selectedPrimitive = nil
            guard let partID = message.partID,
                  page.parts.node(withID: partID) != nil else { return }
            selectedLibraryPartType = nil
            selectedTemplateNodeID = nil
            selectedGlobalNodeID = nil
            if message.extendsSelection == true {
                if selectedPartIDs.contains(partID) {
                    selectedPartIDs.remove(partID)
                } else {
                    selectedPartIDs.insert(partID)
                    selectedPartID = partID
                }
            } else {
                selectedPartIDs = [partID]
                selectedPartID = partID
            }
        case .selectPrimitive:
            guard let partID = message.partID,
                  let propertyKey = message.propertyKey,
                  let part = page.parts.node(withID: partID),
                  part.type.definition.properties.contains(where: { $0.key == propertyKey }) else { return }
            selectedPartIDs = [partID]
            selectedPartID = partID
            selectedPrimitive = .init(
                partID: partID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? []
            )
        case .deleteParts:
            deleteParts(message.partIDs ?? [])
        case .duplicateParts:
            guard selectCanvasParts(message.partIDs, on: page) else { return }
            duplicatePart()
        case .copyParts:
            guard selectCanvasParts(message.partIDs, on: page) else { return }
            copyPart()
        case .pasteParts:
            guard selectCanvasParts(message.partIDs, on: page) else { return }
            pastePart()
        case .insertPart:
            guard let type = message.partType,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertPart(type: type, on: page.id, placement: placement) else { return }
            selectedPartID = id
        case .insertReusablePart:
            guard let definitionID = message.reusableDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let definition = resolvedTemplateDefinition(definitionID),
                  let id = editor.insertTemplate(definition, on: page.id, placement: placement) else { return }
            selectedPartID = id
        case .insertGlobalPart:
            guard let definitionID = message.globalDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertGlobalPart(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedPartID = id
        case .setGlobalLink:
            guard let partID = message.partID,
                  let isLinked = message.isGlobalLinked,
                  document.site.globalPartContext(containing: partID) != nil else { return }
            editor.setGlobalPartLinked(partID: partID, isLinked: isLinked)
            selectedPartID = partID
        case .movePart:
            let partIDs = message.partIDs ?? message.partID.map { [$0] } ?? []
            guard partIDs.allSatisfy({ page.parts.node(withID: $0) != nil }),
                  let placement = validatedPlacement(message.placement, on: page),
                  movePartsFromStructure(partIDs, placement) else { return }
            workspaceLayout.activate(.structure)
        case .editHTMLPart:
            guard let partID = message.partID,
                  let propertyKey = message.propertyKey,
                  let source = message.propertyValue,
                  let part = page.parts.node(withID: partID),
                  let package = part.type.definition.package,
                  PartTemplateRenderer.htmlPrimitives(
                      in: package.htmlTemplate,
                      loopMaximums: package.loopMaximums
                  ).contains(where: {
                      $0.key == propertyKey.rawValue
                  }) else { return }
            selectedPartIDs = [partID]
            selectedPartID = partID
            selectedPrimitive = .init(partID: partID, propertyKey: propertyKey)
            htmlSourceEditRequest = HTMLSourceEditRequest(
                pageID: page.id,
                partID: partID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                source: .init(
                    html: source,
                    css: part.propertyValue(PartPackageAdapter.htmlCSSKey(for: propertyKey.rawValue))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? "",
                    javaScript: part.propertyValue(PartPackageAdapter.htmlJavaScriptKey(for: propertyKey.rawValue))
                        .value(at: message.propertyPath ?? [])?.stringValue ?? ""
                )
            )
        case .editPart:
            guard let partID = message.partID,
                  let propertyKey = message.propertyKey,
                  let part = page.parts.node(withID: partID),
                  part.type.definition.properties.contains(where: { definition in
                      guard definition.key == propertyKey else { return false }
                      switch definition.control {
                      case .singleLineText, .multilineText: return true
                      default: return false
                      }
                  }),
                  let value = message.propertyValue else { return }
            selectedPartIDs = [partID]
            selectedPartID = partID
            if part.type.definition.properties.contains(where: {
                $0.key == propertyKey && !$0.isInspectorVisible
            }) {
                selectedPrimitive = .init(
                    partID: partID,
                    propertyKey: propertyKey,
                    propertyPath: message.propertyPath ?? []
                )
            }
            pageTextEditRequest = PageTextEditRequest(
                pageID: page.id,
                partID: partID,
                propertyKey: propertyKey,
                propertyPath: message.propertyPath ?? [],
                value: value
            )
        case .importImageAsset:
            guard let propertyKey = message.propertyKey,
                  let partID = message.partID,
                  let part = page.parts.node(withID: partID) else { return }
            // A video property takes the movie itself; an image property — or
            // a manifest video control's poster companion — takes an image.
            let targetsVideo = part.type.definition.properties.contains(where: {
                if case .video = $0.control { return $0.key == propertyKey }
                return false
            })
            let targetsImage = part.type.definition.properties.contains(where: {
                if $0.key == propertyKey, case .image = $0.control { return true }
                if case .video = $0.control {
                    return PartVideoTemplateValues.posterPropertyKey(for: $0.key.rawValue) == propertyKey
                }
                return false
            })
            guard targetsVideo || targetsImage else { return }
            let expectedType: UTType = targetsVideo ? .movie : .image
            let byteLimit = targetsVideo ? 100_000_000 : 25_000_000
            undoManager?.beginUndoGrouping()
            let asset: ProjectAsset
            if let assetID = message.assetID {
                guard let existingAsset = document.site.assets.first(where: {
                    $0.id == assetID && UTType(mimeType: $0.mediaType)?.conforms(to: expectedType) == true
                }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = existingAsset
            } else {
                guard let filename = message.assetFilename,
                      let mediaType = message.assetMediaType,
                      let type = imageType(filename: filename, mediaType: mediaType),
                      type.conforms(to: expectedType),
                      let encoded = message.assetData,
                      let data = Data(base64Encoded: encoded),
                      data.count <= byteLimit else {
                    undoManager?.endUndoGrouping()
                    return
                }
                let assetID = document.importAsset(
                    data: data,
                    filename: filename,
                    mediaType: type.preferredMIMEType ?? mediaType,
                    reuseIdenticalContent: true,
                    undoManager: undoManager
                )
                guard let importedAsset = document.site.assets.first(where: { $0.id == assetID }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = importedAsset
            }
            setCanvasProperty(
                partID: partID,
                key: propertyKey,
                value: .url(asset.reference),
                at: message.propertyPath ?? [],
                defaultLeafValue: .url("")
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName(targetsVideo ? "Import Video" : "Import Image")
            if targetsVideo, asset.videoMetadata == nil,
               let videoData = document.assetContents[asset.id]?.data {
                // The canvas shows the generated poster frame, so analyse the
                // movie now rather than waiting for an inspector visit.
                let analysedID = asset.id
                let analysedFilename = asset.filename
                Task {
                    guard let result = await VideoPosterGenerator.metadata(
                        for: videoData,
                        filename: analysedFilename
                    ) else { return }
                    document.setVideoMetadata(id: analysedID, result: result)
                }
            }
            selectedPartID = partID
            selectedPrimitive = nil
            workspaceLayout.activate(.structure)
        case .insertImagePart:
            // One insert message serves both media kinds: the dropped file
            // decides whether an Image or a Video part is created.
            guard let placement = validatedPlacement(message.placement, on: page) else { return }
            let asset: ProjectAsset
            let isVideo: Bool
            undoManager?.beginUndoGrouping()
            if let assetID = message.assetID {
                guard let existingAsset = document.site.assets.first(where: { candidate in
                    guard candidate.id == assetID, let type = UTType(mimeType: candidate.mediaType) else { return false }
                    return type.conforms(to: .image) || type.conforms(to: .movie)
                }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = existingAsset
                isVideo = UTType(mimeType: existingAsset.mediaType)?.conforms(to: .movie) == true
            } else {
                guard let filename = message.assetFilename,
                      let mediaType = message.assetMediaType,
                      let type = imageType(filename: filename, mediaType: mediaType),
                      type.conforms(to: .image) || type.conforms(to: .movie),
                      let encoded = message.assetData,
                      let data = Data(base64Encoded: encoded),
                      data.count <= (type.conforms(to: .movie) ? 100_000_000 : 25_000_000) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                isVideo = type.conforms(to: .movie)
                let assetID = document.importAsset(
                    data: data,
                    filename: filename,
                    mediaType: type.preferredMIMEType ?? mediaType,
                    reuseIdenticalContent: true,
                    undoManager: undoManager
                )
                guard let importedAsset = document.site.assets.first(where: { $0.id == assetID }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = importedAsset
            }
            let partType: PartType = isVideo ? .video : .image
            guard let partID = editor.insertPart(type: partType, on: page.id, placement: placement) else {
                undoManager?.endUndoGrouping()
                return
            }
            guard let mediaProperty = partType.definition.properties.first(where: {
                      if case .image = $0.control { return !isVideo }
                      if case .video = $0.control { return isVideo }
                      return false
                  }) else {
                undoManager?.endUndoGrouping()
                return
            }
            editor.setProperty(id: partID, key: mediaProperty.key, value: .url(asset.reference))
            undoManager?.endUndoGrouping()
            undoManager?.setActionName(isVideo ? "Add Video" : "Add Image")
            if isVideo, asset.videoMetadata == nil,
               let videoData = document.assetContents[asset.id]?.data {
                let analysedID = asset.id
                let analysedFilename = asset.filename
                Task {
                    guard let result = await VideoPosterGenerator.metadata(
                        for: videoData,
                        filename: analysedFilename
                    ) else { return }
                    document.setVideoMetadata(id: analysedID, result: result)
                }
            }
            selectedPartIDs = [partID]
            selectedPartID = partID
            workspaceLayout.activate(.structure)
        }
    }

    @discardableResult
    private func selectCanvasParts(_ partIDs: [UUID]?, on page: Page) -> Bool {
        guard let partIDs, !partIDs.isEmpty,
              partIDs.allSatisfy({ page.parts.node(withID: $0) != nil }) else { return false }
        selectedPartIDs = Set(partIDs)
        selectedPartID = partIDs.last
        return true
    }

    private func handleCanvasContextMenuAction(
        _ action: CanvasContextMenuAction,
        partID: UUID,
        imageProperty: PartProperty.Key?,
        imagePropertyPath: [Int]
    ) {
        guard let part = selectedPage?.parts.node(withID: partID) else { return }
        selectedPrimitive = nil
        selectedLibraryPartType = nil
        selectedTemplateNodeID = nil
        selectedGlobalNodeID = nil
        if !selectedPartIDs.contains(partID) {
            selectedPartIDs = [partID]
        }
        selectedPartID = partID

        switch action {
        case .clearImage:
            guard let imageProperty,
                  let definition = part.type.definition.properties.first(where: {
                      guard $0.key == imageProperty else { return false }
                      if case .image = $0.control { return true }
                      if case .video = $0.control { return true }
                      return false
                  }) else { return }
            undoManager?.beginUndoGrouping()
            let defaultLeafValue: PartProperty.Value = definition.defaultValue.arrayValue == nil
                ? definition.defaultValue
                : .url("")
            setCanvasProperty(
                partID: partID,
                key: imageProperty,
                value: defaultLeafValue,
                at: imagePropertyPath,
                defaultLeafValue: defaultLeafValue
            )
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Clear Image")
        case .duplicate:
            duplicatePart()
        case .copy:
            copyPart()
        case .paste:
            pastePart()
        case .saveReusable:
            canvasReusablePartName = part.name
        case .saveGlobal:
            canvasGlobalPartName = part.name
        case .makeLocalOverride:
            editor.setGlobalPartLinked(partID: partID, isLinked: false)
        case .relinkGlobal:
            editor.setGlobalPartLinked(partID: partID, isLinked: true)
        case .explodeGlobal:
            editor.explodeGlobalPart(partID: partID)
        case .moveUp:
            movePart(-1)
        case .moveDown:
            movePart(1)
        case .outdent:
            outdentPart()
        case .delete:
            deletePart()
        }
    }

    private func canClearCanvasImage(
        partID: UUID,
        imageProperty: PartProperty.Key,
        imagePropertyPath: [Int]
    ) -> Bool {
        guard let part = selectedPage?.parts.node(withID: partID),
              let definition = part.type.definition.properties.first(where: {
                  guard $0.key == imageProperty else { return false }
                  if case .image = $0.control { return true }
                  if case .video = $0.control { return true }
                  return false
              }) else { return false }
        let currentValue = part.propertyValue(imageProperty).value(at: imagePropertyPath)
        let defaultLeafValue: PartProperty.Value = definition.defaultValue.arrayValue == nil
            ? definition.defaultValue
            : .url("")
        return currentValue != nil && currentValue != defaultLeafValue
    }

    private var canvasReusableAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasReusablePartName != nil },
            set: { if !$0 { canvasReusablePartName = nil } }
        )
    }

    private var canvasGlobalAlertBinding: Binding<Bool> {
        Binding(
            get: { canvasGlobalPartName != nil },
            set: { if !$0 { canvasGlobalPartName = nil } }
        )
    }

    private var canvasReusableNameBinding: Binding<String> {
        Binding(
            get: { canvasReusablePartName ?? "" },
            set: { canvasReusablePartName = $0 }
        )
    }

    private var canvasGlobalNameBinding: Binding<String> {
        Binding(
            get: { canvasGlobalPartName ?? "" },
            set: { canvasGlobalPartName = $0 }
        )
    }

    private func saveHTMLSource(_ source: HTMLPartSource, request: HTMLSourceEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let part = page.parts.node(withID: request.partID),
              let package = part.type.definition.package,
              PartTemplateRenderer.htmlPrimitives(
                  in: package.htmlTemplate,
                  loopMaximums: package.loopMaximums
              ).contains(where: {
                  $0.key == request.propertyKey.rawValue
              }) else { return }
        let values: [(PartProperty.Key, String)] = [
            (request.propertyKey, source.html),
            (PartPackageAdapter.htmlCSSKey(for: request.propertyKey.rawValue), source.css),
            (PartPackageAdapter.htmlJavaScriptKey(for: request.propertyKey.rawValue), source.javaScript)
        ]
        undoManager?.beginUndoGrouping()
        for (key, value) in values {
            let defaultLeafValue: PartProperty.Value
            if key == request.propertyKey,
               let primitive = PartTemplateRenderer.htmlPrimitives(
                   in: package.htmlTemplate,
                   loopMaximums: package.loopMaximums
               ).first(where: { $0.key == key.rawValue }) {
                defaultLeafValue = .string(primitive.defaultValue)
            } else {
                defaultLeafValue = .string("")
            }
            setCanvasProperty(
                partID: request.partID,
                key: key,
                value: .string(value),
                at: request.propertyPath,
                defaultLeafValue: defaultLeafValue
            )
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit HTML Part")
    }

    private func savePageText(_ value: String, request: PageTextEditRequest) {
        guard let page = document.site.pages.first(where: { $0.id == request.pageID }),
              let part = page.parts.node(withID: request.partID),
              part.type.definition.properties.contains(where: { definition in
                  guard definition.key == request.propertyKey else { return false }
                  switch definition.control {
                  case .singleLineText, .multilineText: return true
                  default: return false
                  }
              }) else { return }
        undoManager?.beginUndoGrouping()
        let defaultLeafValue = part.type.definition.package.flatMap { package in
            PartTemplateRenderer.textPrimitives(
                in: package.htmlTemplate,
                loopMaximums: package.loopMaximums
            ).first(where: { $0.key == request.propertyKey.rawValue })?.defaultValue
        } ?? ""
        setCanvasProperty(
            partID: request.partID,
            key: request.propertyKey,
            value: .string(value),
            at: request.propertyPath,
            defaultLeafValue: .string(defaultLeafValue)
        )
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Edit Text")
    }

    private func setCanvasProperty(
        partID: UUID,
        key: PartProperty.Key,
        value: PartProperty.Value,
        at indexPath: [Int],
        defaultLeafValue: PartProperty.Value
    ) {
        guard let part = selectedPage?.parts.node(withID: partID) else { return }
        let rootValue = indexPath.isEmpty
            ? value
            : part.propertyValue(key).settingValue(
                value,
                at: indexPath,
                defaultLeafValue: defaultLeafValue
            )
        if let context = document.site.globalPartContext(containing: partID), !context.isOverridden {
            editor.setSharedReusableProperty(partID: partID, key: key, value: rootValue)
        } else {
            editor.setProperty(id: partID, key: key, value: rootValue)
        }
    }

    private func imageType(filename: String, mediaType: String) -> UTType? {
        UTType(mimeType: mediaType) ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
    }

    private func validatedPlacement(_ value: CanvasMessage.Placement?, on page: Page) -> PartPlacement? {
        guard let value, let placement = value.partPlacement else { return nil }
        if let targetID = value.targetID,
           page.parts.node(withID: targetID) == nil {
            return nil
        }
        return placement
    }

    private func addPage() {
        addPage(at: nil)
    }

    private func addPage(at placement: PageTreePlacement?) {
        let pageID = editor.addPage()
        if let placement {
            _ = editor.movePageTreeItem(.page(pageID), to: placement)
        }
        selectedPageID = pageID
        selectedPageFolderID = nil
        selectedPageAssetID = nil
        inspectedPageID = pageID
        selectedPartID = nil
    }

    private func addPageFolder(_ name: String, at placement: PageTreePlacement?) {
        let folderID = editor.addPageFolder(named: name)
        if let placement {
            _ = editor.movePageTreeItem(.folder(folderID), to: placement)
        }
        selectedPageFolderID = folderID
        inspectedPageID = nil
        selectedPageAssetID = nil
        expandedPageTreeItemIDs.insert(folderID)
    }

    private func duplicatePage(_ pageID: UUID) {
        let duplicatedPageID = editor.duplicatePage(id: pageID)
        selectedPageID = duplicatedPageID
        inspectedPageID = duplicatedPageID
        selectedPartID = nil
    }

    private func deletePage(_ pageID: UUID) {
        let subpageCount = descendantPageIDs(of: pageID).count
        if subpageCount > 0,
           let page = document.site.pages.first(where: { $0.id == pageID }) {
            pageDeletionRequest = PageDeletionRequest(
                pageID: pageID,
                title: page.title,
                subpageCount: subpageCount
            )
        } else {
            performPageDeletion(pageID, includingSubpages: false)
        }
    }

    private func performPageDeletion(_ pageID: UUID, includingSubpages: Bool) {
        guard let nextPageID = editor.removePage(
            id: pageID,
            includingSubpages: includingSubpages
        ) else { return }
        selectedPageID = nextPageID
        inspectedPageID = nextPageID
        selectedPartID = nil
    }

    private func descendantPageIDs(of pageID: UUID) -> Set<UUID> {
        var descendants = Set<UUID>()
        var parents: Set<UUID> = [pageID]
        while !parents.isEmpty {
            let children = Set(document.site.pages.compactMap { page in
                page.parentPageID.map(parents.contains) == true ? page.id : nil
            }).subtracting(descendants)
            guard !children.isEmpty else { break }
            descendants.formUnion(children)
            parents = children
        }
        return descendants
    }

    private var pageDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pageDeletionRequest != nil },
            set: { if !$0 { pageDeletionRequest = nil } }
        )
    }

    private func movePage(_ pageID: UUID, _ offset: Int) {
        editor.movePage(id: pageID, offset: offset)
    }

    private func setHomePage(_ pageID: UUID) {
        editor.setHomePage(id: pageID)
        selectedPageID = pageID
        inspectedPageID = pageID
    }

    private func addPartToPageEnd(_ type: PartType) {
        // Context-menu actions can arrive while SwiftUI is completing the menu's
        // own update transaction. Apply the document and selection mutation on
        // the next main-actor turn so it does not publish during that update.
        Task { @MainActor in
            await Task.yield()
            guard insertPartFromLibrary(type, .end) else { return }
        }
    }

    private func insertPartFromLibrary(_ type: PartType, _ placement: PartPlacement) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertPart(type: type, on: pageID, placement: placement) else { return false }
        selectedPartID = id
        return true
    }

    @State private var selectedTemplateNodeID: UUID?
    @State private var selectedGlobalNodeID: UUID?

    /// The Templates panel's Library tab: My Library (always) plus installed
    /// read-only packs that actually carry templates.
    private var libraryTemplateSections: [TemplatePanelSection] {
        ReusablePartLibrary.shared.packs
            .filter { $0.isPersonal || (!$0.isEditable && !$0.nodes.isEmpty) }
            .map(templateSection(for:))
    }

    /// The Templates panel's Dev tab: every development pack other than My
    /// Library, always listed as authoring targets — the tab itself only
    /// appears when there are any.
    private var devTemplateSections: [TemplatePanelSection] {
        ReusablePartLibrary.shared.packs
            .filter { $0.isEditable && !$0.isPersonal }
            .map(templateSection(for:))
    }

    private func templateSection(for pack: ReusablePartLibraryPack) -> TemplatePanelSection {
        TemplatePanelSection(
            id: pack.id,
            title: pack.title,
            isEditable: pack.isEditable,
            nodes: pack.nodes
        )
    }

    /// The routing view over every tab: the project's templates plus every
    /// pack section, used to locate a node's home by id.
    private var templatePanelSections: [TemplatePanelSection] {
        [TemplatePanelSection(
            id: TemplatePanelSection.projectSectionID,
            title: "Project",
            isEditable: true,
            nodes: document.site.projectTemplateLibrary
        )] + libraryTemplateSections + devTemplateSections
    }

    /// Copies a project template into My Library under a fresh identity,
    /// embedding the document assets it references.
    private func addProjectTemplateToLibrary(_ id: UUID) {
        guard case .part(let definition)? = document.site.projectTemplateLibrary.node(withID: id) else {
            return
        }
        let copy = ReusablePartDefinition(
            name: definition.name,
            root: definition.root.duplicatedForReusableDefinition()
        )
        saveTemplateToPack(copy, packRootURL: nil)
    }

    /// Copies a library template into the project under a fresh identity,
    /// importing its embedded assets into the document.
    private func addLibraryTemplateToProject(_ id: UUID) {
        let library = ReusablePartLibrary.shared
        guard let entry = library.entry(withID: id),
              let imported = library.importedDefinition(for: entry, into: document, undoManager: undoManager) else {
            return
        }
        let copy = ReusablePartDefinition(name: imported.name, root: imported.root)
        _ = editor.addProjectTemplate(copy)
    }

    private func isProjectTemplateNode(_ id: UUID) -> Bool {
        document.site.projectTemplateLibrary.node(withID: id) != nil
    }

    private func packRootURL(forSection sectionID: String) -> URL? {
        ReusablePartLibrary.shared.packs.first { $0.id == sectionID }?.rootURL
    }

    private func renameTemplateNode(_ id: UUID, to name: String) {
        if isProjectTemplateNode(id) {
            editor.renameProjectTemplate(id: id, to: name)
        } else {
            ReusablePartLibrary.shared.rename(id: id, to: name)
        }
    }

    private func deleteTemplateDefinition(_ id: UUID) {
        if isProjectTemplateNode(id) {
            editor.removeProjectTemplate(id: id)
        } else {
            ReusablePartLibrary.shared.delete(id: id)
        }
    }

    private func duplicateTemplateDefinition(_ id: UUID) {
        if isProjectTemplateNode(id) {
            _ = editor.duplicateProjectTemplate(id: id)
        } else {
            _ = ReusablePartLibrary.shared.duplicate(id: id)
        }
    }

    private func createTemplateFolder(named name: String, inSection sectionID: String) {
        if sectionID == TemplatePanelSection.projectSectionID {
            _ = editor.createProjectTemplateFolder(named: name)
        } else {
            _ = ReusablePartLibrary.shared.createFolder(
                name: name,
                inPackRoot: packRootURL(forSection: sectionID)
            )
        }
    }

    private func renameTemplateFolder(_ id: UUID, to name: String) {
        if isProjectTemplateNode(id) {
            editor.renameProjectTemplateFolder(id: id, to: name)
        } else if let newID = ReusablePartLibrary.shared.renameFolder(id: id, to: name) {
            // Pack folders identify by path, so selection follows the rename.
            if selectedTemplateNodeID == id {
                selectedTemplateNodeID = newID
            }
        }
    }

    private func deleteTemplateFolder(_ id: UUID) {
        if isProjectTemplateNode(id) {
            editor.deleteProjectTemplateFolder(id: id)
        } else {
            ReusablePartLibrary.shared.deleteFolder(id: id)
        }
    }

    /// One drop, four meanings: a reorder inside a section, a move between
    /// editable sections, a copy out of a read-only pack, or a hand-off
    /// between the project and a pack (embedding or importing assets).
    /// Folders carry their whole subtree through the same routes.
    private func moveTemplateNode(
        _ id: UUID,
        toSection sectionID: String,
        placement: ReusablePartPlacement
    ) -> Bool {
        let library = ReusablePartLibrary.shared
        let sourceIsProject = isProjectTemplateNode(id)
        let targetIsProject = sectionID == TemplatePanelSection.projectSectionID

        if sourceIsProject && targetIsProject {
            return editor.moveProjectTemplateNode(id: id, to: placement)
        }
        if sourceIsProject {
            guard let node = document.site.projectTemplateLibrary.node(withID: id),
                  let packRootURL = packRootURL(forSection: sectionID) else { return false }
            switch node {
            case .part(let definition):
                // Project → pack: embed the document's assets into a bundle,
                // then drop the project copy.
                saveTemplateToPack(definition, packRootURL: packRootURL)
                editor.removeProjectTemplate(id: id)
                _ = library.moveNode(id: id, to: placement)
                return true
            case .folder(let folder):
                guard exportProjectFolderToPack(folder, packRootURL: packRootURL, at: placement) else { return false }
                editor.deleteProjectTemplateFolder(id: id)
                return true
            }
        }
        if targetIsProject {
            guard let sourceSection = templatePanelSections.first(where: { $0.nodes.node(withID: id) != nil }),
                  let node = sourceSection.nodes.node(withID: id),
                  let imported = importedProjectNode(node) else { return false }
            guard editor.addProjectTemplateNode(imported, at: placement) else { return false }
            // The section's editability decides move vs copy — folders have
            // no template-entry record, so asking the library by id would
            // wrongly answer "read-only" and leave the source behind.
            if sourceSection.isEditable {
                switch node {
                case .part: library.delete(id: id)
                case .folder: library.deleteFolder(id: id)
                }
            }
            return true
        }
        let sourceRootURL = library.packRootURL(forID: id)
            ?? templatePanelSections.first { $0.nodes.node(withID: id) != nil }
                .flatMap { packRootURL(forSection: $0.id) }
        let targetRootURL = packRootURL(forSection: sectionID)
        if sourceRootURL?.standardizedFileURL == targetRootURL?.standardizedFileURL {
            return library.moveNode(id: id, to: placement)
        }
        let sourceSection = templatePanelSections.first { $0.nodes.node(withID: id) != nil }
        let isFolder = if case .folder? = sourceSection?.nodes.node(withID: id) { true } else { false }
        if sourceSection?.isEditable == true {
            if isFolder {
                return library.moveFolder(id: id, toPackRoot: targetRootURL, at: placement)
            }
            guard library.moveTemplate(id: id, toPackRoot: targetRootURL) else { return false }
            _ = library.moveNode(id: id, to: placement)
            return true
        }
        // Read-only source: the drag copies content out, keeping its names.
        if isFolder {
            return library.copyFolder(id: id, toPackRoot: targetRootURL, at: placement)
        }
        return library.duplicate(id: id, to: targetRootURL, renaming: false) != nil
    }

    /// Recreates a project folder inside a pack: mirrored folder structure,
    /// each template embedded with its assets and given a rendered preview.
    private func exportProjectFolderToPack(
        _ folder: ReusablePartFolder,
        packRootURL: URL,
        at placement: ReusablePartPlacement
    ) -> Bool {
        let library = ReusablePartLibrary.shared
        guard let folderID = library.createFolder(name: folder.name, inPackRoot: packRootURL, at: placement) else {
            return false
        }
        for child in folder.children {
            switch child {
            case .part(let definition):
                saveTemplateToPack(definition, packRootURL: packRootURL)
                _ = library.moveNode(id: definition.id, to: .inside(folderID: folderID))
            case .folder(let subfolder):
                _ = exportProjectFolderToPack(subfolder, packRootURL: packRootURL, at: .inside(folderID: folderID))
            }
        }
        return true
    }

    /// Rebuilds a pack node for the project: embedded assets import into the
    /// document and every template arrives under a fresh identity, so copies
    /// out of read-only packs never collide with their originals.
    private func importedProjectNode(_ node: ReusablePartNode) -> ReusablePartNode? {
        let library = ReusablePartLibrary.shared
        switch node {
        case .part(let definition):
            guard let entry = library.entry(withID: definition.id),
                  let imported = library.importedDefinition(for: entry, into: document, undoManager: undoManager) else {
                return nil
            }
            return .part(ReusablePartDefinition(name: imported.name, root: imported.root))
        case .folder(let folder):
            return .folder(ReusablePartFolder(
                name: folder.name,
                children: folder.children.compactMap(importedProjectNode)
            ))
        }
    }

    private func saveDraggedPartsAsTemplates(_ partIDs: [UUID], inSection sectionID: String) -> Bool {
        guard let selectedPage else { return false }
        let requestedIDs = Set(partIDs)
        func flattenedIDs(_ nodes: [PartNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        let orderedTopLevelIDs = flattenedIDs(selectedPage.parts).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.parts.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
        guard !orderedTopLevelIDs.isEmpty else { return false }
        var savedCount = 0
        for partID in orderedTopLevelIDs {
            guard let part = document.site.part(withID: partID) else { continue }
            let trimmedName = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? part.type.displayName : trimmedName
            guard let definition = editor.templateDefinition(fromPartID: partID, name: name) else { continue }
            if sectionID == TemplatePanelSection.projectSectionID {
                guard editor.addProjectTemplate(definition) else { continue }
            } else if let packRootURL = packRootURL(forSection: sectionID) {
                saveTemplateToPack(definition, packRootURL: packRootURL)
            } else {
                continue
            }
            savedCount += 1
        }
        return savedCount == orderedTopLevelIDs.count
    }

    /// The template the Inspector shows when one is selected in the panel —
    /// folder selections resolve to nothing.
    private var selectedTemplateEntry: ReusablePartLibraryEntry? {
        guard let selectedTemplateNodeID else { return nil }
        if case .part(let definition)? = document.site.projectTemplateLibrary.node(withID: selectedTemplateNodeID) {
            return ReusablePartLibraryEntry(definition: definition, assets: [])
        }
        return ReusablePartLibrary.shared.entry(withID: selectedTemplateNodeID)
    }

    private var selectedTemplateContext: TemplateInspectorContext? {
        guard let entry = selectedTemplateEntry else { return nil }
        let isProject = isProjectTemplateNode(entry.id)
        return TemplateInspectorContext(
            entry: entry,
            isProjectTemplate: isProject,
            isEditable: isProject || ReusablePartLibrary.shared.isEditable(id: entry.id),
            rename: { renameTemplateNode(entry.id, to: $0) }
        )
    }

    /// The global part the Inspector shows when one is selected in the panel —
    /// folder selections resolve to nothing.
    private var selectedGlobalDefinition: ReusablePartDefinition? {
        guard let selectedGlobalNodeID,
              case .part(let definition)? = document.site.globalPartLibrary.node(withID: selectedGlobalNodeID) else {
            return nil
        }
        return definition
    }

    /// Selecting a template takes over the Inspector, clearing every other
    /// inspectable selection — matching how parts, pages and assets behave.
    private var inspectableTemplateSelection: Binding<UUID?> {
        Binding(
            get: { selectedTemplateNodeID },
            set: { nodeID in
                selectedTemplateNodeID = nodeID
                guard let nodeID,
                      ReusablePartLibrary.shared.entry(withID: nodeID) != nil
                        || document.site.projectTemplateLibrary.node(withID: nodeID) != nil else { return }
                selectedPrimitive = nil
                selectedPartIDs = []
                selectedPartID = nil
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedLibraryPartType = nil
                selectedGlobalNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    /// Selecting a global part takes over the Inspector the same way.
    private var inspectableGlobalSelection: Binding<UUID?> {
        Binding(
            get: { selectedGlobalNodeID },
            set: { nodeID in
                selectedGlobalNodeID = nodeID
                guard let nodeID,
                      case .part? = document.site.globalPartLibrary.node(withID: nodeID) else { return }
                selectedPrimitive = nil
                selectedPartIDs = []
                selectedPartID = nil
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedLibraryPartType = nil
                selectedTemplateNodeID = nil
                selectedAssetCollectionItemID = nil
            }
        )
    }

    private func insertReusablePartFromLibrary(
        _ definitionID: UUID,
        _ placement: PartPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let definition = resolvedTemplateDefinition(definitionID),
              let id = editor.insertTemplate(definition, on: pageID, placement: placement) else { return false }
        selectedPartID = id
        return true
    }

    /// Resolves a template for insertion. Project templates already reference
    /// this document's assets; pack templates import their embedded assets
    /// (deduplicated by content) and the returned definition references the
    /// imported copies.
    private func resolvedTemplateDefinition(_ definitionID: UUID) -> ReusablePartDefinition? {
        if case .part(let definition)? = document.site.projectTemplateLibrary.node(withID: definitionID) {
            return definition
        }
        guard let entry = ReusablePartLibrary.shared.entry(withID: definitionID) else { return nil }
        return ReusablePartLibrary.shared.importedDefinition(
            for: entry,
            into: document,
            undoManager: undoManager
        )
    }

    private func insertGlobalPartFromLibrary(
        _ definitionID: UUID,
        _ placement: PartPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertGlobalPart(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedPartID = id
        return true
    }

    /// Saving from the canvas or Structure targets the project's own template
    /// section; dragging the template to a pack afterwards makes it app-wide.
    private func saveReusablePart(_ name: String) {
        guard let partID = selectedPartID,
              let definition = editor.templateDefinition(
                fromPartID: partID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else { return }
        _ = editor.addProjectTemplate(definition)
        workspaceLayout.activate(.reusableParts)
    }

    /// Saves the bundle immediately and attaches the offscreen-rendered
    /// preview when it finishes painting.
    private func saveTemplateToPack(_ definition: ReusablePartDefinition, packRootURL: URL?) {
        ReusablePartLibrary.shared.save(
            definition: definition,
            assetContents: document.assetContents,
            to: packRootURL
        )
        TemplatePreviewRenderer.shared.capturePreview(
            definition: definition,
            site: document.site,
            assetContents: document.assetContents,
            pageBackground: selectedPage?.backgroundOverride
        ) { data in
            if let data {
                ReusablePartLibrary.shared.savePreview(data, forID: definition.id)
            }
        }
    }

    private func saveGlobalPart(_ name: String) {
        guard let partID = selectedPartID else { return }
        _ = editor.saveGlobalPart(
            partID: partID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        editsSharedReusableDefinition = true
        workspaceLayout.activate(.globalParts)
    }

    private func saveDraggedPartsAsGlobals(_ partIDs: [UUID]) -> Bool {
        guard let selectedPage else { return false }
        let requestedIDs = Set(partIDs)
        func flattenedIDs(_ nodes: [PartNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        let orderedTopLevelIDs = flattenedIDs(selectedPage.parts).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.parts.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
        guard !orderedTopLevelIDs.isEmpty else { return false }
        let createdIDs = editor.saveGlobalParts(partIDs: orderedTopLevelIDs)
        if !createdIDs.isEmpty {
            editsSharedReusableDefinition = true
        }
        return createdIDs.count == orderedTopLevelIDs.count
    }

    private func renamePart(_ partID: UUID, _ name: String) {
        if let definitionID = document.site.part(withID: partID)?.reusableDefinitionID,
           document.site.globalParts.contains(where: { $0.id == definitionID }) {
            editor.renameGlobalPart(definitionID: definitionID, name: name)
        } else {
            editor.renamePart(id: partID, name: name)
        }
    }

    private func renameGlobalPart(_ definitionID: UUID, _ name: String) {
        editor.renameGlobalPart(definitionID: definitionID, name: name)
    }

    private func deleteGlobalPart(_ definitionID: UUID) {
        editor.removeGlobalPart(definitionID: definitionID)
        if selectedPart?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func updateReusablePart() {
        guard let partID = selectedPartID else { return }
        _ = editor.updateReusablePart(from: partID)
    }

    private func detachReusablePart() {
        guard let partID = selectedPartID else { return }
        editor.detachReusablePart(partID: partID)
    }

    private func duplicatePart() {
        guard let pageID = selectedPage?.id else { return }
        let duplicateIDs = editor.duplicateParts(
            ids: topLevelSelectedPartIDs,
            on: pageID
        )
        selectedPartIDs = Set(duplicateIDs)
        selectedPartID = duplicateIDs.last
    }

    private func copyPart() {
        guard let selectedPage else {
            copiedParts = []
            return
        }
        copiedParts = topLevelSelectedPartIDs.compactMap {
            selectedPage.parts.node(withID: $0)
        }
    }

    private func pastePart() {
        guard let pageID = selectedPage?.id, !copiedParts.isEmpty else { return }
        let placement = topLevelSelectedPartIDs.last
            .map(PartPlacement.after)
            ?? .end
        let pastedIDs = editor.pasteParts(
            copiedParts,
            on: pageID,
            placement: placement
        )
        selectedPartIDs = Set(pastedIDs)
        selectedPartID = pastedIDs.last
    }

    private func movePart(_ offset: Int) {
        guard let pageID = selectedPage?.id,
              let partID = selectedPartID else {
            return
        }
        editor.movePartBySiblingOffset(
            id: partID,
            on: pageID,
            offset: offset
        )
    }

    private func outdentPart() {
        guard let pageID = selectedPage?.id,
              let partID = selectedPartID else {
            return
        }
        editor.outdentPart(id: partID, on: pageID)
    }

    private func movePartsFromStructure(_ sourceIDs: [UUID], _ placement: PartPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        let requestedIDs = Set(sourceIDs)
        let orderedIDs = topLevelSelectedPartIDs.filter { requestedIDs.contains($0) }
        let partIDs = orderedIDs.isEmpty ? sourceIDs : orderedIDs
        guard !partIDs.isEmpty else { return false }
        if let targetID = placement.targetID {
            let targetAncestors = Set(selectedPage?.parts.ancestorIDs(of: targetID) ?? [])
            guard !partIDs.contains(targetID),
                  targetAncestors.isDisjoint(with: partIDs) else { return false }
        }
        if editor.moveParts(ids: partIDs, on: pageID, to: placement) {
            selectedPartIDs = Set(partIDs)
            selectedPartID = partIDs.last
            return true
        }
        return false
    }

    private func canMovePartsFromStructure(_ sourceIDs: [UUID], _ placement: PartPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        return editor.canMoveParts(ids: sourceIDs, on: pageID, to: placement)
    }

    private func deletePart() {
        deleteParts(Array(selectedPartIDs))
    }

    private func deleteParts(_ requestedIDs: [UUID]) {
        let partIDs = topLevelPartIDs(from: Set(requestedIDs))
        guard !partIDs.isEmpty else { return }
        editor.removeParts(ids: partIDs)
        selectedPartIDs = []
        selectedPartID = nil
    }

    private func previewSite() {
        previewRefreshTask?.cancel()
        let site = document.site
        let assets = document.assetContents
        let revision = document.mutationEvent.revision
        let packageRevision = partCatalog.revision
        let selectedPageOutputPath = selectedPage.map {
            StaticSiteRenderer.outputPath(for: $0, in: site)
        }
        let applicationIdentifier = selectedPreviewApplicationIdentifier
        let sessionID: UUID
        if let previousApplicationIdentifier = previewSessionApplicationIdentifier,
           previousApplicationIdentifier != applicationIdentifier {
            let replacementSessionID = UUID()
            previewSessionID = replacementSessionID
            sessionID = replacementSessionID
        } else {
            sessionID = previewSessionID
        }
        previewRefreshTask = Task { @MainActor in
            do {
                let snapshot = try await buildBrowserPreview(site: site, assets: assets)
                guard !Task.isCancelled else { return }
                let serverURL = try await browserPreviewServer.publish(
                    snapshot,
                    notifyingClients: false,
                    preferredPort: site.previewServerPort.flatMap(UInt16.init(exactly:))
                )
                browserPreviewURL = serverURL
                browserPreviewRevision = revision
                browserPreviewPackageRevision = packageRevision
                guard !Task.isCancelled else { return }
                let pageURL = selectedPageOutputPath.map {
                    previewURL(for: $0, relativeTo: serverURL)
                } ?? serverURL
                let previewURL = previewURL(pageURL, sessionID: sessionID)
                isPreviewSessionOpen = true
                await presentPreview(
                    previewURL,
                    sessionID: sessionID,
                    applicationIdentifier: applicationIdentifier
                )
            } catch {
                guard !Task.isCancelled else { return }
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func schedulePreviewRefresh(selectionOnly: Bool = false) {
        guard externalPreviewAutoReload, isPreviewSessionOpen else { return }
        previewRefreshTask?.cancel()
        previewRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let site = document.site
            let assets = document.assetContents
            do {
                let revision = document.mutationEvent.revision
                let packageRevision = partCatalog.revision
                if !selectionOnly || browserPreviewRevision != revision || browserPreviewPackageRevision != packageRevision {
                    let snapshot = try await buildBrowserPreview(site: site, assets: assets)
                    try Task.checkCancellation()
                    // Navigation below also reloads an unchanged target. Avoid a
                    // competing reload event disconnecting the stream first.
                    browserPreviewURL = try await browserPreviewServer.publish(
                        snapshot,
                        notifyingClients: false,
                        preferredPort: site.previewServerPort.flatMap(UInt16.init(exactly:))
                    )
                    browserPreviewRevision = revision
                    browserPreviewPackageRevision = packageRevision
                }
                try Task.checkCancellation()
                if let page = selectedPage, let serverURL = browserPreviewURL {
                    let url = previewURL(
                        previewURL(for: StaticSiteRenderer.outputPath(for: page, in: document.site), relativeTo: serverURL),
                        sessionID: previewSessionID
                    )
                    // Live following never opens extra tabs or steals focus from editing.
                    _ = await browserPreviewServer.navigatePreview(sessionID: previewSessionID, to: previewTarget(for: url))
                }
            } catch {
                guard !Task.isCancelled else { return }
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func buildBrowserPreview(site: Site, assets: ProjectAssetContents) async throws -> PreviewDiskSnapshot {
        let previous = await browserPreviewServer.currentSnapshot()
        let task = Task.detached(priority: .utility) {
            try PreviewDiskSnapshot.build(previous: previous) { emit in
                try StaticSiteRenderer(environment: .preview).generate(site: site, assets: assets, emit: emit)
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func presentPreview(
        _ previewURL: URL,
        sessionID: UUID,
        applicationIdentifier: String?
    ) async {
        if previewSessionApplicationIdentifier == applicationIdentifier,
           await browserPreviewServer.navigatePreview(
            sessionID: sessionID,
            to: previewTarget(for: previewURL)
           ) {
            activatePreviewApplication(applicationIdentifier)
            return
        }
        previewSessionApplicationIdentifier = applicationIdentifier
        openPreview(previewURL)
    }

    private var selectedPreviewApplicationIdentifier: String? {
        if previewApplicationIdentifier == PreviewApplicationSelection.systemDefault {
            return PreviewApplicationCatalog.defaultApplication()?.bundleIdentifier
        }
        return previewApplicationIdentifier
    }

    private func previewURL(for outputPath: String, relativeTo serverURL: URL) -> URL {
        outputPath.split(separator: "/").reduce(serverURL) { url, part in
            url.appending(path: String(part))
        }
    }

    private func previewURL(_ pageURL: URL, sessionID: UUID) -> URL {
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return pageURL
        }
        var queryItems = parts.queryItems ?? []
        queryItems.removeAll { $0.name == foundryPreviewSessionQueryName }
        queryItems.append(URLQueryItem(name: foundryPreviewSessionQueryName, value: sessionID.uuidString))
        parts.queryItems = queryItems
        return parts.url ?? pageURL
    }

    private func previewTarget(for previewURL: URL) -> String {
        guard let parts = URLComponents(url: previewURL, resolvingAgainstBaseURL: false) else {
            return previewURL.path
        }
        return parts.percentEncodedQuery.map { "\(parts.percentEncodedPath)?\($0)" }
            ?? parts.percentEncodedPath
    }

    private func activatePreviewApplication(_ applicationIdentifier: String?) {
        guard let applicationIdentifier,
              let runningApplication = NSRunningApplication.runningApplications(
                withBundleIdentifier: applicationIdentifier
              ).first else { return }
        NSApp.yieldActivation(to: runningApplication)
        runningApplication.activate()
    }

    private func openPreview(_ previewURL: URL) {
            let defaultApplicationIdentifier = PreviewApplicationCatalog.defaultApplication()?.bundleIdentifier
            if previewApplicationIdentifier == PreviewApplicationSelection.systemDefault ||
                previewApplicationIdentifier == defaultApplicationIdentifier {
                NSWorkspace.shared.open(previewURL)
            } else if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: previewApplicationIdentifier
            ) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.promptsUserIfNeeded = true
                configuration.addsToRecentItems = false
                NSWorkspace.shared.open(
                    [previewURL],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    guard let error else { return }
                    Task { @MainActor in exportErrorMessage = error.localizedDescription }
                }
            } else {
                previewApplicationIdentifier = PreviewApplicationSelection.systemDefault
                NSWorkspace.shared.open(previewURL)
            }
    }

    private func handlePublishingCommand(_ command: PublishingCommandDispatcher.Command) {
        switch command {
        case .settings:
            openSiteSettings(section: .publishing)
        case .publishSite:
            publishSite()
        case .republishAllFiles:
            publishSite(forceAllFiles: true)
        case .markAllChanged:
            markAllPublishingFilesChanged()
        case .markAllUnchanged:
            markAllPublishingFilesUnchanged()
        }
    }

    private func openSiteSettings(section: ProjectSettingsSection) {
        ProjectSettingsWindowRegistry.shared.register(
            id: siteSettingsWindowID,
            document: document,
            undoManager: undoManager,
            selection: section,
            openPageMetadata: { pageID in
                inspectablePageSelection.wrappedValue = pageID
            }
        )
        openWindow(id: "site-settings", value: siteSettingsWindowID)
    }

    private var validPublishingDestinations: [PublishingDestination] {
        document.site.publishingDestinations.filter { destination in
            let nonempty: (String) -> Bool = {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            switch destination.kind {
            case .local:
                return PublishingDestinationStore.url(for: document.site.id, destinationID: destination.id) != nil
            case .sftp:
                return nonempty(destination.host) && nonempty(destination.username) && destination.port > 0
            case .ftp, .ftps:
                return nonempty(destination.host) && nonempty(destination.username) && destination.port > 0
                    && !PublishingCredentialStore.credential(siteID: document.site.id, destinationID: destination.id).isEmpty
            case .amazonS3:
                return nonempty(destination.s3Bucket) && nonempty(destination.s3Region)
                    && nonempty(destination.username)
                    && !PublishingCredentialStore.credential(siteID: document.site.id, destinationID: destination.id).isEmpty
            }
        }
    }

    private func publishSite(destinationID: UUID? = nil, forceAllFiles: Bool = false) {
        guard let nativeDocument = NSDocumentController.shared.currentDocument else { return }
        if nativeDocument.fileURL == nil {
            nativeDocument.save(nil)
            return
        }
        var site = document.site
        let selectedDestination = destinationID.flatMap { id in
            site.publishingDestinations.first { $0.id == id }
        } ?? site.defaultPublishingDestination
        if let selectedDestination {
            site.publishingDestination = selectedDestination.kind
            site.publishingHost = selectedDestination.host
            site.publishingPort = selectedDestination.port
            site.publishingUsername = selectedDestination.username
            site.publishingRemotePath = selectedDestination.remotePath
            site.publishingS3Bucket = selectedDestination.s3Bucket
            site.publishingS3Region = selectedDestination.s3Region
            site.cleansObsoleteExportFiles = selectedDestination.cleansObsoleteFiles
        }
        let selectedDestinationID = selectedDestination?.id
        let assets = document.assetContents
        var localDirectory = site.publishingDestination == .local
            ? selectedDestinationID.flatMap {
                PublishingDestinationStore.url(for: site.id, destinationID: $0)
            }
            : nil
        if site.publishingDestination == .local, localDirectory == nil {
            let panel = NSOpenPanel()
            panel.title = "Choose Publishing Folder"
            panel.message = "Choose the folder that will contain the published website."
            panel.prompt = "Choose"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            if let destinationID = selectedDestinationID {
                PublishingDestinationStore.setURL(directory, for: site.id, destinationID: destinationID)
            }
            localDirectory = directory
        }

        let credential = selectedDestinationID.map {
            PublishingCredentialStore.credential(siteID: site.id, destinationID: $0)
        } ?? PublishingCredentialStore.credential(site: site)
        publishingState = .preparing
        showsPublishingProgress = true
        publishingTask?.cancel()
        publishingTask = Task {
            await Task.yield()
            do {
                try await saveDocument(nativeDocument)
                let bundle = await Task.detached {
                    StaticSiteRenderer().render(site: site, assets: assets)
                }.value
                try Task.checkCancellation()
                publishingState = .publishing(nil)
                let result = try await SitePublisher().publish(
                    bundle: bundle,
                    site: site,
                    manifests: document.publishingManifests,
                    destinationID: selectedDestinationID,
                    localDirectory: localDirectory,
                    credential: credential,
                    forceAllFiles: forceAllFiles
                ) { progress in
                    Task { @MainActor in
                        publishingState = .publishing(progress)
                    }
                }
                // Persist the updated manifest through the document's own
                // save path; writing into the open package directly would be
                // treated by NSDocument as an external change.
                try await saveDocument(nativeDocument)
                publishingState = .completed(result)
                publishingChangeTask?.cancel()
                publishingChangesByTreeItem.removeAll()
                schedulePublishingChangeRefresh(immediately: true)
            } catch is CancellationError {
                publishingState = .cancelled
            } catch {
                publishingState = .failed(error.localizedDescription)
            }
            publishingTask = nil
        }
    }

    private func saveDocument(_ nativeDocument: NSDocument) async throws {
        guard let fileURL = nativeDocument.fileURL,
              let fileType = nativeDocument.fileType else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            nativeDocument.save(
                to: fileURL,
                ofType: fileType,
                for: .saveOperation
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func markAllPublishingFilesChanged() {
        var site = document.site
        site.synchronizeLegacyPublishingFields()
        document.publishingManifests.removeManifest(
            for: site,
            destinationID: site.defaultPublishingDestinationID
        )
        persistPublishingManifests()
        schedulePublishingChangeRefresh(immediately: true)
    }

    private func markAllPublishingFilesUnchanged() {
        var site = document.site
        site.synchronizeLegacyPublishingFields()
        let assets = document.assetContents
        let manifests = document.publishingManifests
        let localDirectory = site.publishingDestination == .local
            ? site.defaultPublishingDestinationID.flatMap { PublishingDestinationStore.url(for: site.id, destinationID: $0) }
            : nil
        publishingChangeTask?.cancel()
        publishingChangeTask = Task {
            let manifest = await Task.detached {
                let bundle = StaticSiteRenderer().render(site: site, assets: assets)
                return PublishingPlan.make(
                    bundle: bundle,
                    previous: nil,
                    removesObsoleteFiles: false
                ).nextManifest
            }.value
            manifests.setManifest(
                manifest,
                for: site,
                destinationID: site.defaultPublishingDestinationID,
                localDirectory: localDirectory
            )
            persistPublishingManifests()
            guard !Task.isCancelled else { return }
            publishingChangesByTreeItem.removeAll()
        }
    }

    /// Saves the document so an updated in-memory manifest reaches disk. A
    /// document that has never been saved has nowhere to persist to yet; its
    /// manifests simply live in memory until the first save.
    private func persistPublishingManifests() {
        guard let nativeDocument = NSDocumentController.shared.currentDocument,
              nativeDocument.fileURL != nil else { return }
        Task {
            do {
                try await saveDocument(nativeDocument)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    /// Where the Assets panel's header actions place new nodes: below the
    /// selected asset, at the top of a selected folder, or at the top of the
    /// library when nothing is selected.
    private var assetInsertionPlacement: AssetPlacement {
        let visible = document.site.assetLibrary.resourcesOnly
        guard let selectedID = selectedAssetLibraryNodeID,
              let node = visible.node(withID: selectedID) else {
            if let first = visible.first { return .before(nodeID: first.id) }
            return .end
        }
        switch node {
        case .asset:
            return .after(nodeID: selectedID)
        case .folder(let folder):
            if let first = folder.children.first { return .before(nodeID: first.id) }
            return .inside(folderID: folder.id)
        }
    }

    private func importAssets() {
        let panel = NSOpenPanel()
        panel.title = "Import Files or Folders"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importAssetURLs(panel.urls, placement: assetInsertionPlacement)
    }

    private func importAssetURLs(_ urls: [URL], placement: AssetPlacement) {
        guard !urls.isEmpty else { return }
        var sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let topURL = sorted.first
        // Repeated inserts after one anchor land in reverse; feed URLs backwards.
        if case .after = placement { sorted.reverse() }
        undoManager?.beginUndoGrouping()
        var topNodeID: UUID?
        for url in sorted {
            let nodeID = importAssetURL(url, placement: placement)
            if url == topURL { topNodeID = nodeID }
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Assets")
        // Selecting the topmost import reveals it, expanding a collapsed folder.
        if let topNodeID { selectedAssetLibraryNodeID = topNodeID }
    }

    private func importPageTreeURLs(_ urls: [URL], placement: PageTreePlacement) {
        guard !urls.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            importPageTreeURL(url, placement: placement)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Site Files")
    }

    private func importPageTreeURL(_ url: URL, placement: PageTreePlacement) {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]) else {
            return
        }
        if values.isDirectory == true {
            let folderID = editor.addPageFolder(named: url.lastPathComponent)
            guard editor.movePageTreeItem(.folder(folderID), to: placement) else { return }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                importPageTreeURL(child, placement: .end(parentFolderID: folderID))
            }
            selectedPageFolderID = folderID
            return
        }
        guard values.isRegularFile == true, let data = try? Data(contentsOf: url) else { return }
        let assetID = document.importAsset(
            data: data,
            filename: url.lastPathComponent,
            mediaType: (values.contentType ?? UTType(filenameExtension: url.pathExtension))?.preferredMIMEType
                ?? "application/octet-stream",
            undoManager: undoManager
        )
        guard editor.movePageTreeItem(.asset(assetID), to: placement) else { return }
        selectedPageAssetID = assetID
    }

    @discardableResult
    private func importAssetURL(_ url: URL, placement: AssetPlacement) -> UUID? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]) else {
            return nil
        }
        if values.isDirectory == true {
            let folderID = document.createAssetFolder(
                named: url.lastPathComponent,
                at: placement,
                undoManager: undoManager
            )
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                importAssetURL(child, placement: .inside(folderID: folderID))
            }
            return folderID
        }
        guard values.isRegularFile == true, let data = try? Data(contentsOf: url) else { return nil }
        return importAsset(
            data: data,
            filename: url.lastPathComponent,
            type: values.contentType ?? UTType(filenameExtension: url.pathExtension),
            placement: placement
        )
    }

    @discardableResult
    private func importAsset(data: Data, filename: String, type: UTType?, placement: AssetPlacement) -> UUID {
        document.importAsset(
            data: data,
            filename: filename,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            placement: placement,
            reuseIdenticalContent: true,
            undoManager: undoManager
        )
    }

    private func importMediaAsset(_ url: URL, expectedType: UTType) -> ProjectAsset? {
        let filename = url.lastPathComponent
        let dragPrefix = "foundry-asset-"
        if filename.hasPrefix(dragPrefix),
           let separator = filename.range(of: "--"),
           let id = UUID(uuidString: String(filename[filename.index(filename.startIndex, offsetBy: dragPrefix.count)..<separator.lowerBound])),
           let asset = document.site.assets.first(where: {
               $0.id == id && UTType(mimeType: $0.mediaType)?.conforms(to: expectedType) == true
           }) {
            return asset
        }

        let maximumByteCount = expectedType == .image ? 25_000_000 : 1_000_000_000
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey, .fileSizeKey]),
              values.isRegularFile == true,
              let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
              type.conforms(to: expectedType),
              (values.fileSize ?? 0) <= maximumByteCount,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let id = document.importAsset(
            data: data,
            filename: filename,
            mediaType: type.preferredMIMEType ?? "application/octet-stream",
            placement: .end,
            reuseIdenticalContent: true,
            undoManager: undoManager
        )
        return document.site.assets.first(where: { $0.id == id })
    }

    private func deleteAssetLibraryNodes(_ ids: [UUID]) {
        for id in ids {
            // A node vanishes when a selected ancestor folder was deleted first.
            guard let node = document.site.assetLibrary.node(withID: id) else { continue }
            switch node {
            case .asset:
                document.removeAsset(id: id, undoManager: undoManager)
            case .folder:
                document.removeAssetFolder(id: id, undoManager: undoManager)
            }
        }
        selectedAssetLibraryNodeID = nil
    }

    private func assetUsageCount(_ id: UUID) -> Int {
        document.site.pages.reduce(0) { total, page in
            total + page.parts.reduce(0) { $0 + assetUsageCount(id, in: $1) }
        }
    }

    private func assetUsageCount(_ id: UUID, in node: PartNode) -> Int {
        let directValues = node.properties.map(\.value)
            + (node.responsiveOverrides ?? []).map(\.value)
            + (node.responsiveDefaults ?? []).map(\.value)
        let directCount = directValues.reduce(0) { count, value in
            count + value.assetReferenceCount(to: id)
        }
        return directCount + node.children.reduce(0) { $0 + assetUsageCount(id, in: $1) }
    }
}

private extension PartProperty.Value {
    func assetReferenceCount(to id: UUID) -> Int {
        switch self {
        case .url(let value):
            return value.foundryAssetID == id ? 1 : 0
        case .array(let values):
            return values.reduce(0) { $0 + $1.assetReferenceCount(to: id) }
        case .link(let link):
            if case .resource(let resourceID) = link.destination, resourceID == id { return 1 }
            return 0
        default:
            return 0
        }
    }
}

private enum PublishingModalState {
    case preparing
    case publishing(PublishingProgress?)
    case completed(PublishingResult)
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .publishing: true
        case .completed, .failed, .cancelled: false
        }
    }
}

private struct PublishingProgressView: View {
    let siteName: String
    let state: PublishingModalState
    let cancel: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: statusSymbol)
                .font(.system(size: 36))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.semibold))

            statusContent
                .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Spacer()
                if state.isActive {
                    Button("Cancel", role: .cancel, action: cancel)
                } else {
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .frame(minHeight: 240)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .preparing:
            ProgressView()
                .controlSize(.small)
            Text("Preparing the site for publishing…")
                .foregroundStyle(.secondary)
        case .publishing(let progress):
            if let progress {
                ProgressView(value: progress.fractionCompleted)
                Text("\(formattedBytes(progress.uploadedBytes)) of \(formattedBytes(progress.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(progress.transfers) { transfer in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(transfer.file)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text("\(Int(transfer.fractionCompleted * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: transfer.fractionCompleted)
                        }
                    }
                }
                .font(.caption)
                Text("\(progress.completedFileCount) of \(progress.fileCount) files complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Starting upload…")
                    .foregroundStyle(.secondary)
            }
        case .completed(let result):
            Text(completionMessage(result))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        case .cancelled:
            Text("Publishing was cancelled.")
                .foregroundStyle(.secondary)
        }
    }

    private func completionMessage(_ result: PublishingResult) -> String {
        var parts = ["Uploaded \(result.uploadedFileCount)"]
        if result.unchangedFileCount > 0 { parts.append("skipped \(result.unchangedFileCount) unchanged") }
        if result.removedFileCount > 0 { parts.append("removed \(result.removedFileCount) obsolete") }
        return parts.joined(separator: ", ") + "."
    }

    private var title: String {
        switch state {
        case .preparing: "Preparing \(siteName)"
        case .publishing: "Publishing \(siteName)"
        case .completed: "Publishing Complete"
        case .failed: "Publishing Failed"
        case .cancelled: "Publishing Cancelled"
        }
    }

    private var statusSymbol: String {
        switch state {
        case .preparing, .publishing: "icloud.and.arrow.up"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state {
        case .completed: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    ContentView(document: FoundryDocument())
}

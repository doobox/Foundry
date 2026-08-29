import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: FoundryDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selectedPageID: UUID?
    @State private var inspectedPageID: UUID?
    @State private var selectedPageFolderID: UUID?
    @State private var selectedPageAssetID: UUID?
    @State private var selectedAssetLibraryNodeID: UUID?
    @State private var selectedComponentIDs: Set<UUID> = []
    @State private var selectedComponentID: UUID?
    @State private var copiedComponents: [ComponentNode] = []
    @State private var editsSharedReusableDefinition = false
    @State private var workspaceLayout = WorkspaceLayout.restored()
    @State private var detachedPanelWindows = DetachedPanelWindowCoordinator()
    @State private var themeWindow = ThemeWindowCoordinator()
    @State private var exportErrorMessage: String?
    @State private var showsProjectSettings = false
    @State private var previewSessionApplicationIdentifier: String?
    @State private var isPreviewSessionOpen = false
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var canvasViewportPreset: CanvasViewportPreset = .mobile
    @State private var canvasEditorOptions = CanvasEditorOptions()
    @State private var componentCatalog = ComponentPackageCatalog.shared
    @State private var canvasViewportWidth = CanvasViewportPreset.mobile.viewportWidth
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.externalPreviewAutoReload)
    private var externalPreviewAutoReload = false
    @AppStorage(AppPreferenceKey.previewApplication)
    private var previewApplicationIdentifier = PreviewApplicationSelection.systemDefault

    private let renderer: any PageRendering = HTMLPageRenderer()

    var body: some View {
        let _ = componentCatalog.revision
        DockingWorkspaceView(
            layout: $workspaceLayout,
            canvasViewportPreset: $canvasViewportPreset,
            canvasEditorOptions: $canvasEditorOptions,
            canvasViewportWidth: $canvasViewportWidth,
            openProjectSettings: { showsProjectSettings = true },
            openThemeEditor: {
                themeWindow.show(document: document, undoManager: undoManager)
            },
            previewSite: previewSite,
            exportSite: exportSite
        ) { panel in
            workspacePanel(panel)
        }
        .frame(
            minWidth: EditorWindowSize.minimumWidth,
            idealWidth: EditorWindowSize.idealWidth,
            maxWidth: .infinity,
            minHeight: EditorWindowSize.minimumHeight,
            idealHeight: EditorWindowSize.idealHeight,
            maxHeight: .infinity
        )
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
        }
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
        .onChange(of: externalPreviewAutoReload) { _, isEnabled in
            if !isEnabled {
                previewRefreshTask?.cancel()
            }
        }
        .onChange(of: document.site.pages.map(\.id)) { _, pageIDs in
            if let selectedPageID, pageIDs.contains(selectedPageID) {
                return
            }
            selectedPageID = pageIDs.first
            selectedComponentID = nil
        }
        .onChange(of: selectedComponentID) { _, componentID in
            editsSharedReusableDefinition = false
            guard let componentID else {
                selectedComponentIDs = []
                return
            }
            if !selectedComponentIDs.contains(componentID) {
                selectedComponentIDs = [componentID]
            }
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onChange(of: selectedComponentIDs) { _, componentIDs in
            if let selectedComponentID, !componentIDs.contains(selectedComponentID) {
                self.selectedComponentID = componentIDs.first
            } else if selectedComponentID == nil {
                selectedComponentID = componentIDs.first
            }
            guard !componentIDs.isEmpty else { return }
            inspectedPageID = nil
            selectedPageFolderID = nil
            selectedPageAssetID = nil
            selectedAssetLibraryNodeID = nil
        }
        .onDeleteCommand {
            guard !selectedComponentIDs.isEmpty else { return }
            deleteComponent()
        }
        .onChange(of: document.site) {
            schedulePreviewRefresh()
        }
        .onDisappear {
            previewRefreshTask?.cancel()
        }
        .sheet(isPresented: $showsProjectSettings) {
            ProjectSettingsView(
                siteName: document.site.name,
                language: document.site.language,
                editor: editor
            )
        }
        .alert("Site Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "The site could not be generated.")
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
                selectedPageID: inspectablePageSelection,
                selectedFolderID: inspectablePageFolderSelection,
                selectedAssetID: inspectablePageAssetSelection,
                addPage: addPage,
                addFolder: { _ = editor.addPageFolder(named: $0) },
                duplicatePage: duplicatePage,
                deletePage: deletePage,
                movePage: movePage,
                moveTreeItem: { editor.movePageTreeItem($0, to: $1) },
                importURLs: importPageTreeURLs
            )
        case .components:
            ComponentLibraryPanel(addToPageEnd: addComponentToPageEnd)
        case .reusableComponents:
            ReusableComponentLibraryPanel(
                definitions: document.site.reusableComponents,
                renameDefinition: renameReusableComponent,
                deleteDefinition: deleteReusableComponent
            )
        case .globalComponents:
            GlobalComponentLibraryPanel(
                definitions: document.site.globalComponents,
                renameDefinition: renameGlobalComponent,
                deleteDefinition: deleteGlobalComponent,
                saveDraggedComponents: saveDraggedComponentsAsGlobals
            )
        case .structure:
            StructurePanel(
                page: selectedPage,
                selectedComponentIDs: $selectedComponentIDs,
                selectedComponentID: inspectableComponentSelection,
                renameComponent: { editor.renameComponent(id: $0, name: $1) },
                moveComponentsToPlacement: moveComponentsFromStructure,
                insertComponent: insertComponentFromLibrary,
                insertReusableComponent: insertReusableComponentFromLibrary,
                insertGlobalComponent: insertGlobalComponentFromLibrary,
                duplicateComponent: duplicateComponent,
                copyComponent: copyComponent,
                pasteComponent: pasteComponent,
                moveComponent: moveComponent,
                outdentComponent: outdentComponent,
                deleteComponent: deleteComponent,
                canPasteComponent: !copiedComponents.isEmpty,
                saveReusableComponent: saveReusableComponent,
                saveGlobalComponent: saveGlobalComponent
            )
        case .assets:
            AssetsPanel(
                library: document.site.assetLibrary,
                selectedNodeID: inspectableAssetLibrarySelection,
                importFiles: importAssets,
                importURLs: importAssetURLs,
                createFolder: { name, placement in
                    _ = document.createAssetFolder(named: name, at: placement, undoManager: undoManager)
                },
                moveNode: { document.moveAssetNode(id: $0, to: $1, undoManager: undoManager) },
                deleteNode: deleteAssetLibraryNode
            )
            .onChange(of: selectedAssetLibraryNodeID) { _, selectedID in
                guard selectedID != nil else { return }
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedComponentID = nil
            }
        case .canvas:
            CanvasView(
                page: selectedPage,
                language: document.site.language,
                theme: document.site.theme,
                assets: document.assetContents,
                selectedComponentIDs: selectedComponentIDs,
                editorOptions: canvasEditorOptions,
                renderer: renderer,
                handleMessage: handleCanvasMessage,
                viewportWidth: $canvasViewportWidth
            )
        case .inspector:
            InspectorView(
                page: inspectedPage,
                folder: selectedPageFolder,
                asset: selectedPageAsset,
                assetLibraryNode: selectedAssetLibraryNode,
                assetLibrary: document.site.assetLibrary,
                assetContents: document.assetContents,
                folders: document.site.pageFolders,
                component: selectedComponent,
                componentSelectionCount: selectedComponentIDs.count,
                theme: document.site.theme,
                assets: document.site.assets,
                editor: editor,
                reusableDefinition: selectedReusableDefinition,
                isGlobalOverride: selectedGlobalContext?.isOverridden == true,
                setGlobalOverride: setSelectedGlobalOverride,
                breakpoint: activeCanvasBreakpoint,
                assetUsageCount: assetUsageCount,
                renameAsset: { document.renameAsset(id: $0, filename: $1, undoManager: undoManager) },
                renameAssetFolder: { document.renameAssetFolder(id: $0, name: $1, undoManager: undoManager) },
                editsSharedDefinition: $editsSharedReusableDefinition
            )
        }
    }

    private var editor: ProjectEditor {
        ProjectEditor(document: document, undoManager: undoManager)
    }

    private var inspectablePageSelection: Binding<UUID?> {
        Binding(
            get: { inspectedPageID },
            set: { pageID in
                inspectedPageID = pageID
                guard pageID != nil else { return }
                selectedPageID = pageID
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
                selectedComponentID = nil
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
                selectedComponentID = nil
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
                selectedComponentID = nil
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
                selectedComponentID = nil
            }
        )
    }

    private var inspectableComponentSelection: Binding<UUID?> {
        Binding(
            get: { selectedComponentID },
            set: { componentID in
                selectedComponentID = componentID
                guard componentID != nil else { return }
                inspectedPageID = nil
                selectedPageFolderID = nil
                selectedPageAssetID = nil
                selectedAssetLibraryNodeID = nil
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
        ResponsiveBreakpoint.forViewportWidth(canvasViewportWidth)
    }

    private var selectedComponent: ComponentNode? {
        guard let selectedComponentID else {
            return nil
        }
        return selectedPage?.components.node(withID: selectedComponentID)
    }

    private var topLevelSelectedComponentIDs: [UUID] {
        guard let selectedPage else { return [] }
        let selectedIDs = selectedComponentIDs
        func flattenedIDs(_ nodes: [ComponentNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        return flattenedIDs(selectedPage.components).filter { id in
            guard selectedIDs.contains(id) else { return false }
            return Set(selectedPage.components.ancestorIDs(of: id)).isDisjoint(with: selectedIDs)
        }
    }

    private var selectedReusableDefinition: ReusableComponentDefinition? {
        guard let definitionID = selectedGlobalContext?.definitionID else { return nil }
        return document.site.globalComponents.first(where: { $0.id == definitionID })
    }

    private var selectedGlobalContext: (definitionID: UUID, path: [Int], isOverridden: Bool, overrideOwnerID: UUID?)? {
        guard let selectedComponentID else { return nil }
        return document.site.globalComponentContext(containing: selectedComponentID)
    }

    private func setSelectedGlobalOverride(_ isOverridden: Bool) {
        guard let selectedComponentID else { return }
        editor.setGlobalComponentLinked(componentID: selectedComponentID, isLinked: !isOverridden)
    }

    private func handleCanvasMessage(_ message: CanvasMessage) {
        guard let page = selectedPage else { return }

        switch message.event {
        case .selectComponent:
            guard let componentID = message.componentID,
                  page.components.node(withID: componentID) != nil else { return }
            if message.extendsSelection == true {
                if selectedComponentIDs.contains(componentID) {
                    selectedComponentIDs.remove(componentID)
                } else {
                    selectedComponentIDs.insert(componentID)
                    selectedComponentID = componentID
                }
            } else {
                selectedComponentIDs = [componentID]
                selectedComponentID = componentID
            }
            workspaceLayout.activate(.structure)
        case .insertComponent:
            guard let type = message.componentType,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertComponent(type: type, on: page.id, placement: placement) else { return }
            selectedComponentID = id
        case .insertReusableComponent:
            guard let definitionID = message.reusableDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertReusableComponent(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedComponentID = id
        case .insertGlobalComponent:
            guard let definitionID = message.globalDefinitionID,
                  let placement = validatedPlacement(message.placement, on: page),
                  let id = editor.insertGlobalComponent(
                    definitionID: definitionID,
                    on: page.id,
                    placement: placement
                  ) else { return }
            selectedComponentID = id
        case .setGlobalLink:
            guard let componentID = message.componentID,
                  let isLinked = message.isGlobalLinked,
                  document.site.globalComponentContext(containing: componentID) != nil else { return }
            editor.setGlobalComponentLinked(componentID: componentID, isLinked: isLinked)
            selectedComponentID = componentID
        case .moveComponent:
            let componentIDs = message.componentIDs ?? message.componentID.map { [$0] } ?? []
            guard componentIDs.allSatisfy({ page.components.node(withID: $0) != nil }),
                  let placement = validatedPlacement(message.placement, on: page),
                  moveComponentsFromStructure(componentIDs, placement) else { return }
            workspaceLayout.activate(.structure)
        case .editComponent:
            guard let componentID = message.componentID,
                  let propertyKey = message.propertyKey,
                  let component = page.components.node(withID: componentID),
                  component.type.definition.properties.contains(where: { definition in
                      guard definition.key == propertyKey else { return false }
                      switch definition.control {
                      case .singleLineText, .multilineText: return true
                      default: return false
                      }
                  }),
                  let value = message.propertyValue else { return }
            if let context = document.site.globalComponentContext(containing: componentID), !context.isOverridden {
                editor.setSharedReusableProperty(componentID: componentID, key: propertyKey, value: .string(value))
            } else {
                editor.setProperty(id: componentID, key: propertyKey, value: .string(value))
            }
            selectedComponentID = componentID
            workspaceLayout.activate(.structure)
        case .importImageAsset:
            guard let componentID = message.componentID,
                  page.components.node(withID: componentID)?.type == .image,
                  let filename = message.assetFilename,
                  let mediaType = message.assetMediaType,
                  let type = imageType(filename: filename, mediaType: mediaType),
                  type.conforms(to: .image),
                  let encoded = message.assetData,
                  let data = Data(base64Encoded: encoded),
                  data.count <= 25_000_000 else { return }
            undoManager?.beginUndoGrouping()
            let assetID = document.importAsset(
                data: data,
                filename: filename,
                mediaType: type.preferredMIMEType ?? mediaType,
                undoManager: undoManager
            )
            if let asset = document.site.assets.first(where: { $0.id == assetID }) {
                if let context = document.site.globalComponentContext(containing: componentID), !context.isOverridden {
                    editor.setSharedReusableProperty(componentID: componentID, key: .source, value: .url(asset.reference))
                } else {
                    editor.setProperty(id: componentID, key: .source, value: .url(asset.reference))
                }
            }
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Import Image")
            selectedComponentID = componentID
            workspaceLayout.activate(.structure)
        case .insertImageComponent:
            guard let placement = validatedPlacement(message.placement, on: page) else { return }
            let asset: ProjectAsset
            undoManager?.beginUndoGrouping()
            if let assetID = message.assetID {
                guard let existingAsset = document.site.assets.first(where: {
                    $0.id == assetID && UTType(mimeType: $0.mediaType)?.conforms(to: .image) == true
                }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = existingAsset
            } else {
                guard let filename = message.assetFilename,
                      let mediaType = message.assetMediaType,
                      let type = imageType(filename: filename, mediaType: mediaType),
                      type.conforms(to: .image),
                      let encoded = message.assetData,
                      let data = Data(base64Encoded: encoded),
                      data.count <= 25_000_000 else {
                    undoManager?.endUndoGrouping()
                    return
                }
                let assetID = document.importAsset(
                    data: data,
                    filename: filename,
                    mediaType: type.preferredMIMEType ?? mediaType,
                    undoManager: undoManager
                )
                guard let importedAsset = document.site.assets.first(where: { $0.id == assetID }) else {
                    undoManager?.endUndoGrouping()
                    return
                }
                asset = importedAsset
            }
            guard let componentID = editor.insertComponent(type: .image, on: page.id, placement: placement) else {
                undoManager?.endUndoGrouping()
                return
            }
            editor.setProperty(id: componentID, key: .source, value: .url(asset.reference))
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Add Image")
            selectedComponentIDs = [componentID]
            selectedComponentID = componentID
            workspaceLayout.activate(.structure)
        }
    }

    private func imageType(filename: String, mediaType: String) -> UTType? {
        UTType(mimeType: mediaType) ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
    }

    private func validatedPlacement(_ value: CanvasMessage.Placement?, on page: Page) -> ComponentPlacement? {
        guard let value, let placement = value.componentPlacement else { return nil }
        if let targetID = value.targetID,
           page.components.node(withID: targetID) == nil {
            return nil
        }
        return placement
    }

    private func addPage() {
        let pageID = editor.addPage()
        selectedPageID = pageID
        inspectedPageID = pageID
        selectedComponentID = nil
    }

    private func duplicatePage() {
        guard let pageID = selectedPage?.id else {
            return
        }
        let duplicatedPageID = editor.duplicatePage(id: pageID)
        selectedPageID = duplicatedPageID
        inspectedPageID = duplicatedPageID
        selectedComponentID = nil
    }

    private func deletePage() {
        guard let pageID = selectedPage?.id,
              let nextPageID = editor.removePage(id: pageID) else {
            return
        }
        selectedPageID = nextPageID
        inspectedPageID = nextPageID
        selectedComponentID = nil
    }

    private func movePage(_ offset: Int) {
        guard let pageID = selectedPage?.id else {
            return
        }
        editor.movePage(id: pageID, offset: offset)
    }

    private func addComponentToPageEnd(_ type: ComponentType) {
        guard insertComponentFromLibrary(type, .end) else { return }
        workspaceLayout.activate(.structure)
    }

    private func insertComponentFromLibrary(_ type: ComponentType, _ placement: ComponentPlacement) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertComponent(type: type, on: pageID, placement: placement) else { return false }
        selectedComponentID = id
        return true
    }

    private func insertReusableComponentFromLibrary(
        _ definitionID: UUID,
        _ placement: ComponentPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertReusableComponent(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedComponentID = id
        return true
    }

    private func insertGlobalComponentFromLibrary(
        _ definitionID: UUID,
        _ placement: ComponentPlacement
    ) -> Bool {
        guard let pageID = selectedPage?.id,
              let id = editor.insertGlobalComponent(
                definitionID: definitionID,
                on: pageID,
                placement: placement
              ) else { return false }
        selectedComponentID = id
        return true
    }

    private func saveReusableComponent(_ name: String) {
        guard let componentID = selectedComponentID else { return }
        _ = editor.saveReusableComponent(
            componentID: componentID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        workspaceLayout.activate(.reusableComponents)
    }

    private func saveGlobalComponent(_ name: String) {
        guard let componentID = selectedComponentID else { return }
        _ = editor.saveGlobalComponent(
            componentID: componentID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        editsSharedReusableDefinition = true
        workspaceLayout.activate(.globalComponents)
    }

    private func saveDraggedComponentsAsGlobals(_ componentIDs: [UUID]) -> Bool {
        guard let selectedPage else { return false }
        let requestedIDs = Set(componentIDs)
        func flattenedIDs(_ nodes: [ComponentNode]) -> [UUID] {
            nodes.flatMap { [$0.id] + flattenedIDs($0.children) }
        }
        let orderedTopLevelIDs = flattenedIDs(selectedPage.components).filter { id in
            guard requestedIDs.contains(id) else { return false }
            return Set(selectedPage.components.ancestorIDs(of: id)).isDisjoint(with: requestedIDs)
        }
        guard !orderedTopLevelIDs.isEmpty else { return false }
        let createdIDs = editor.saveGlobalComponents(componentIDs: orderedTopLevelIDs)
        if !createdIDs.isEmpty {
            editsSharedReusableDefinition = true
        }
        return createdIDs.count == orderedTopLevelIDs.count
    }

    private func renameGlobalComponent(_ definitionID: UUID, _ name: String) {
        editor.renameGlobalComponent(definitionID: definitionID, name: name)
    }

    private func deleteGlobalComponent(_ definitionID: UUID) {
        editor.removeGlobalComponent(definitionID: definitionID)
        if selectedComponent?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func renameReusableComponent(_ definitionID: UUID, _ name: String) {
        editor.renameReusableComponent(definitionID: definitionID, name: name)
    }

    private func deleteReusableComponent(_ definitionID: UUID) {
        editor.removeReusableComponent(definitionID: definitionID)
        if selectedComponent?.reusableDefinitionID == nil {
            editsSharedReusableDefinition = false
        }
    }

    private func updateReusableComponent() {
        guard let componentID = selectedComponentID else { return }
        _ = editor.updateReusableComponent(from: componentID)
    }

    private func detachReusableComponent() {
        guard let componentID = selectedComponentID else { return }
        editor.detachReusableComponent(componentID: componentID)
    }

    private func duplicateComponent() {
        guard let pageID = selectedPage?.id else { return }
        let duplicateIDs = editor.duplicateComponents(
            ids: topLevelSelectedComponentIDs,
            on: pageID
        )
        selectedComponentIDs = Set(duplicateIDs)
        selectedComponentID = duplicateIDs.last
    }

    private func copyComponent() {
        guard let selectedPage else {
            copiedComponents = []
            return
        }
        copiedComponents = topLevelSelectedComponentIDs.compactMap {
            selectedPage.components.node(withID: $0)
        }
    }

    private func pasteComponent() {
        guard let pageID = selectedPage?.id, !copiedComponents.isEmpty else { return }
        let placement: ComponentPlacement
        if let selectedComponent {
            placement = selectedComponent.type.definition.allowsChildren
                ? .inside(selectedComponent.id)
                : .after(selectedComponent.id)
        } else {
            placement = .end
        }
        let pastedIDs = editor.pasteComponents(
            copiedComponents,
            on: pageID,
            placement: placement
        )
        selectedComponentIDs = Set(pastedIDs)
        selectedComponentID = pastedIDs.last
    }

    private func moveComponent(_ offset: Int) {
        guard let pageID = selectedPage?.id,
              let componentID = selectedComponentID else {
            return
        }
        editor.moveComponentBySiblingOffset(
            id: componentID,
            on: pageID,
            offset: offset
        )
    }

    private func outdentComponent() {
        guard let pageID = selectedPage?.id,
              let componentID = selectedComponentID else {
            return
        }
        editor.outdentComponent(id: componentID, on: pageID)
    }

    private func moveComponentsFromStructure(_ sourceIDs: [UUID], _ placement: ComponentPlacement) -> Bool {
        guard let pageID = selectedPage?.id else { return false }
        let requestedIDs = Set(sourceIDs)
        let orderedIDs = topLevelSelectedComponentIDs.filter { requestedIDs.contains($0) }
        let componentIDs = orderedIDs.isEmpty ? sourceIDs : orderedIDs
        guard !componentIDs.isEmpty else { return false }
        if let targetID = placement.targetID {
            let targetAncestors = Set(selectedPage?.components.ancestorIDs(of: targetID) ?? [])
            guard !componentIDs.contains(targetID),
                  targetAncestors.isDisjoint(with: componentIDs) else { return false }
        }
        if editor.moveComponents(ids: componentIDs, on: pageID, to: placement) {
            selectedComponentIDs = Set(componentIDs)
            selectedComponentID = componentIDs.last
            return true
        }
        return false
    }

    private func deleteComponent() {
        let componentIDs = topLevelSelectedComponentIDs
        guard !componentIDs.isEmpty else { return }
        editor.removeComponents(ids: componentIDs)
        selectedComponentIDs = []
        selectedComponentID = nil
    }

    private func previewSite() {
        previewRefreshTask?.cancel()
        let bundle = StaticSiteRenderer().render(site: document.site, assets: document.assetContents)
        Task {
            do {
                let previewURL = try await PreviewServer.shared.publish(bundle)
                isPreviewSessionOpen = true
                presentPreview(previewURL)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func schedulePreviewRefresh() {
        guard externalPreviewAutoReload, isPreviewSessionOpen else { return }
        previewRefreshTask?.cancel()
        previewRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let bundle = StaticSiteRenderer().render(site: document.site, assets: document.assetContents)
            do {
                _ = try await PreviewServer.shared.publish(bundle)
            } catch {
                guard !Task.isCancelled else { return }
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func presentPreview(_ previewURL: URL) {
        let applicationIdentifier = selectedPreviewApplicationIdentifier
        if previewSessionApplicationIdentifier == applicationIdentifier,
           let applicationIdentifier,
           let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: applicationIdentifier
           ).first {
            NSApp.yieldActivation(to: runningApplication)
            runningApplication.activate()
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

    private func exportSite() {
        let panel = NSOpenPanel()
        panel.title = "Export Static Site"
        panel.message = "Choose the folder that will contain the generated HTML and CSS files."
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            try SiteExportWriter().write(StaticSiteRenderer().render(site: document.site, assets: document.assetContents), to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([directory.appending(path: "index.html")])
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func importAssets() {
        let panel = NSOpenPanel()
        panel.title = "Import Files or Folders"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importAssetURLs(panel.urls, placement: .end)
    }

    private func importAssetURLs(_ urls: [URL], placement: AssetPlacement) {
        guard !urls.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            importAssetURL(url, placement: placement)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Import Assets")
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
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

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

    private func importAssetURL(_ url: URL, placement: AssetPlacement) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]) else {
            return
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
            return
        }
        guard values.isRegularFile == true, let data = try? Data(contentsOf: url) else { return }
        importAsset(
            data: data,
            filename: url.lastPathComponent,
            type: values.contentType ?? UTType(filenameExtension: url.pathExtension),
            placement: placement
        )
    }

    private func importAsset(data: Data, filename: String, type: UTType?, placement: AssetPlacement) {
        _ = document.importAsset(
            data: data,
            filename: filename,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            placement: placement,
            undoManager: undoManager
        )
    }

    private func deleteAssetLibraryNode(_ id: UUID) {
        guard let node = document.site.assetLibrary.node(withID: id) else { return }
        switch node {
        case .asset:
            document.removeAsset(id: id, undoManager: undoManager)
        case .folder:
            document.removeAssetFolder(id: id, undoManager: undoManager)
        }
        selectedAssetLibraryNodeID = nil
    }

    private func assetUsageCount(_ id: UUID) -> Int {
        document.site.pages.reduce(0) { total, page in
            total + page.components.reduce(0) { $0 + assetUsageCount(id, in: $1) }
        }
    }

    private func assetUsageCount(_ id: UUID, in node: ComponentNode) -> Int {
        (node.property(.source).foundryAssetID == id ? 1 : 0) + node.children.reduce(0) { $0 + assetUsageCount(id, in: $1) }
    }
}

#Preview {
    ContentView(document: FoundryDocument())
}

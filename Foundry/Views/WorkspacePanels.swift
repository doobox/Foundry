import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PagesPanel: View {
    let pages: [Page]
    let folders: [PageFolder]
    let assets: [ProjectAsset]
    let publishingChanges: [UUID: PublishingChange]
    @Binding var selectedPageID: UUID?
    @Binding var selectedFolderID: UUID?
    @Binding var selectedAssetID: UUID?
    @Binding var expandedItemIDs: Set<UUID>
    let addPage: (PageTreePlacement?) -> Void
    let addFolder: (String, PageTreePlacement?) -> Void
    let renameFolder: (UUID, String) -> Void
    let deleteFolder: (UUID, Bool) -> Void
    let duplicatePage: (UUID) -> Void
    let renamePage: (UUID, String) -> Void
    let deletePage: (UUID) -> Void
    let movePage: (UUID, Int) -> Void
    let setHomePage: (UUID) -> Void
    let moveTreeItem: (PageTreeItem, PageTreePlacement) -> Bool
    let importURLs: ([URL], PageTreePlacement) -> Void
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var folderPlacement: PageTreePlacement?
    @State private var folderPendingDeletion: UUID?
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Searching filters the same tree down to matching pages as a flat list;
    /// folders and page-placed assets drop out until the search clears.
    private var displayedPages: [Page] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return pages }
        return pages
            .filter { $0.title.localizedCaseInsensitiveContains(query) }
            .map { page in
                var flattened = page
                flattened.folderID = nil
                flattened.parentPageID = nil
                return flattened
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            PagesPanelHeader(
                addPage: {
                    addPage(selectedFolderID.map(PageTreePlacement.insideFolder))
                },
                addFolder: {
                    folderName = ""
                    folderPlacement = selectedFolderID.map(PageTreePlacement.insideFolder)
                    isNamingFolder = true
                }
            )
            Divider()

            PagesOutlineView(
                pages: displayedPages,
                folders: isSearching ? [] : folders,
                assets: isSearching ? [] : assets,
                publishingChanges: publishingChanges,
                selectedPageID: $selectedPageID,
                selectedFolderID: $selectedFolderID,
                selectedAssetID: $selectedAssetID,
                expandedItemIDs: $expandedItemIDs,
                addPage: addPage,
                requestAddFolder: { placement in
                    folderName = ""
                    folderPlacement = placement
                    isNamingFolder = true
                },
                renameFolder: renameFolder,
                requestDeleteFolder: { folderID in
                    if isFolderEmpty(folderID) {
                        deleteFolderAndClearSelection(folderID)
                    } else {
                        folderPendingDeletion = folderID
                    }
                },
                duplicatePage: duplicatePage,
                renamePage: renamePage,
                deletePage: deletePage,
                movePage: movePage,
                setHomePage: setHomePage,
                // Reordering a filtered list would silently reorganize the
                // real tree; moves resume when the search clears.
                moveItem: { item, placement in
                    isSearching ? false : moveTreeItem(item, placement)
                },
                importURLs: importURLs
            )
            .padding(.top, 12)
            .overlay {
                if isSearching, displayedPages.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .allowsHitTesting(false)
                } else if pages.isEmpty && folders.isEmpty {
                    ContentUnavailableView("No Pages", systemImage: "doc")
                        .allowsHitTesting(false)
                }
            }
            Divider()
            PanelSearchField(prompt: "Search Pages", text: $searchText)
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                addFolder(
                    folderName.trimmingCharacters(in: .whitespacesAndNewlines),
                    folderPlacement
                )
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
            Button("Move Contents Up") {
                guard let folderID = folderPendingDeletion else { return }
                deleteFolderAndClearSelection(folderID, includingContents: false)
                folderPendingDeletion = nil
            }
            Button("Delete All", role: .destructive) {
                guard let folderID = folderPendingDeletion else { return }
                deleteFolderAndClearSelection(folderID, includingContents: true)
                folderPendingDeletion = nil
            }
        } message: {
            Text("Move the folder’s contents up one level, or delete the folder and everything inside it.")
        }
    }

    private func isFolderEmpty(_ folderID: UUID) -> Bool {
        let containsPage = pages.contains { $0.folderID == folderID }
        let containsFolder = folders.contains { $0.parentID == folderID }
        let containsPublishedAsset = assets.contains { $0.exportDirectory == .folder(folderID) }
        return !containsPage && !containsFolder && !containsPublishedAsset
    }

    private func deleteFolderAndClearSelection(_ folderID: UUID, includingContents: Bool = false) {
        deleteFolder(folderID, includingContents)
        expandedItemIDs.remove(folderID)
        if selectedFolderID == folderID {
            selectedFolderID = nil
        }
    }
}

private struct PagesPanelHeader: View {
    let addPage: () -> Void
    let addFolder: () -> Void

    var body: some View {
        HStack {
            Text("Pages")
                .font(.headline)
            Spacer()
            Menu {
                Button("New Page", systemImage: "doc.badge.plus", action: addPage)
                Button("New Folder…", systemImage: "folder.badge.plus", action: addFolder)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Add Page or Folder")
            .help("Add a page or folder")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

struct PartLibraryPanel: View {
    @Binding var selectedType: PartType?
    let addToPageEnd: (PartType) -> Void
    /// Puts a Controls showcase part on the developer's playground page.
    let showControl: (PartType) -> Void
    @State private var catalog = PartPackageCatalog.shared
    @AppStorage(AppPreferenceKey.partLibrarySource)
    private var partSource = PartLibrarySource.parts
    @AppStorage(AppPreferenceKey.showsDeveloperPanel)
    private var enablesDeveloperTools = false
    @AppStorage(AppPreferenceKey.partLibraryIconSize)
    private var iconSizeValue = PartLibraryIconSize.small.rawValue
    @AppStorage(AppPreferenceKey.partLibraryArrangement)
    private var arrangementValue = PartLibraryArrangement.group.rawValue
    @AppStorage(AppPreferenceKey.showsHiddenParts)
    private var showsHiddenParts = false
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            PartLibraryPanelHeader(
                iconSize: iconSize,
                setIconSize: { iconSizeValue = $0.rawValue },
                arrangement: arrangement,
                setArrangement: { arrangementValue = $0.rawValue }
            )
            Divider()
            if catalog.isInitialLoading {
                PartCatalogLoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if enablesDeveloperTools {
                    Picker("Part source", selection: $partSource) {
                        ForEach(availableSources) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .buttonSizing(.flexible)
                    .pickerStyle(.palette)
                    .controlSize(.small)
                    .labelsHidden()
                    .padding(12)

                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(partSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Divider()

                                LazyVGrid(
                                    columns: [GridItem(
                                        .adaptive(
                                            minimum: iconSize.gridMinimumWidth,
                                            maximum: .infinity
                                        ),
                                        spacing: 0,
                                        alignment: .center
                                    )],
                                    alignment: .center,
                                    spacing: 10
                                ) {
                                    ForEach(section.types) { type in
                                        PartLibraryTile(
                                            type: type,
                                            iconSize: iconSize,
                                            isSelected: selectedType == type,
                                            select: {
                                                selectedType = type
                                                // A control is looked at, not
                                                // dragged: selecting it shows
                                                // the showcase straight away.
                                                if activePartSource == .controls { showControl(type) }
                                            }
                                        )
                                        .draggable(PartDragPayload.library(type).stringValue) {
                                            PartLibraryIcon(type: type, size: 54)
                                        }
                                        .contextMenu {
                                            Button("Add to Page End", systemImage: "plus") {
                                                addToPageEnd(type)
                                            }
                                            if let packageURL = type.definition.package?.rootURL {
                                                Divider()
                                                Button(
                                                    "Show in Finder",
                                                    systemImage: "macwindow.and.pointer.arrow"
                                                ) {
                                                    NSWorkspace.shared.activateFileViewerSelecting([packageURL])
                                                }
                                            }
                                        }
                                        .accessibilityAction(named: "Add to Page End") {
                                            addToPageEnd(type)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: .infinity)
                .overlay {
                    if isSearching, partSections.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .allowsHitTesting(false)
                    }
                }
                Divider()
                PanelSearchField(prompt: "Search Parts", text: $searchText)
            }

        }
        .onChange(of: catalog.revision, initial: true) {
            if let selectedType, availableTypes.contains(selectedType) {
                return
            }
            selectedType = availableTypes.first
        }
        .onChange(of: partSource) {
            selectedType = availableTypes.first
        }
        .onChange(of: enablesDeveloperTools) {
            selectedType = availableTypes.first
        }
        .onChange(of: showsHiddenParts) {
            if let selectedType, availableTypes.contains(selectedType) {
                return
            }
            selectedType = availableTypes.first
        }
    }

    private var partSections: [PartLibrarySection] {
        var types = availableTypes
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            types = types.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        }
        if activePartSource == .controls {
            return showcaseSections(for: types)
        }
        switch arrangement {
        case .group:
            return groupSections(for: types)
        case .author:
            return metadataSections(for: types) { type in
                type.definition.package?.manifest.author
            }
        case .tag:
            return metadataSections(for: types) { type in
                type.definition.package?.manifest.tags.first
            }
        case .title:
            return [
                makeSection(
                    id: "title-foundry",
                    title: "Foundry",
                    types: types.filter { $0.definition.package?.isBuiltIn == true }
                ),
                makeSection(
                    id: "title-third-party",
                    title: "Third Party",
                    types: types.filter { $0.definition.package?.isBuiltIn != true }
                )
            ]
            .filter { !$0.types.isEmpty }
        }
    }

    private func groupSections(for types: [PartType]) -> [PartLibrarySection] {
        let preferredCategories = PartPackageGroup.allCases.map(\.category)
        let remainingCategories = Set(types.map { $0.definition.category })
            .subtracting(preferredCategories)
            .sorted { $0.rawValue < $1.rawValue }
        return (preferredCategories + remainingCategories).compactMap { category in
            let categoryTypes = types.filter { $0.definition.category == category }
            guard !categoryTypes.isEmpty else { return nil }
            // makeSection sorts the parts alphabetically, like every other arrangement.
            return makeSection(
                id: "group-\(category.rawValue)",
                title: category.rawValue,
                types: categoryTypes
            )
        }
    }

    /// Showcase parts group by the manifest's `group`, in the order the
    /// developer reference lists controls, not alphabetically.
    private func showcaseSections(for types: [PartType]) -> [PartLibrarySection] {
        let preferredOrder = [
            "Text & Numbers", "Choices", "Colour", "Framework", "Spacing & Edges",
            "Media & Links", "Structure", "Presentation", "Control Groups"
        ]
        let grouped = Dictionary(grouping: types) { normalizedSectionTitle($0.definition.package?.manifest.category) }
        let remaining = grouped.keys.filter { !preferredOrder.contains($0) }.sorted()
        return (preferredOrder + remaining).compactMap { title in
            guard let groupTypes = grouped[title], !groupTypes.isEmpty else { return nil }
            return makeSection(id: "showcase-\(title)", title: title, types: groupTypes)
        }
    }

    private func metadataSections(
        for types: [PartType],
        value: (PartType) -> String?
    ) -> [PartLibrarySection] {
        var grouped: [String: [PartType]] = [:]
        var titles: [String: String] = [:]
        for type in types {
            let title = normalizedSectionTitle(value(type))
            let key = title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
            titles[key] = key == "other" ? "Other" : (titles[key] ?? title)
            grouped[key, default: []].append(type)
        }
        return grouped.map { key, groupedTypes in
            let title = titles[key] ?? "Other"
            return makeSection(
                id: "metadata-\(key)",
                title: title,
                types: groupedTypes
            )
        }
        .sorted { left, right in
            if left.title == "Other" { return false }
            if right.title == "Other" { return true }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    private func normalizedSectionTitle(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }

    private func makeSection(
        id: String,
        title: String,
        types: [PartType]
    ) -> PartLibrarySection {
        PartLibrarySection(
            id: id,
            title: title,
            types: types.sorted {
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                if comparison == .orderedSame { return $0.rawValue < $1.rawValue }
                return comparison == .orderedAscending
            }
        )
    }

    private var availableTypes: [PartType] {
        PartType.allCases.filter { type in
            let package = type.definition.package
            // Showcase parts live only in the Controls tab, never among the
            // parts a page is built from — even with hidden parts shown.
            if package?.isControlShowcase == true { return activePartSource == .controls }
            guard activePartSource != .controls else { return false }
            let isDevelopmentPack = package?.isDevelopmentPack == true
            let showsInLibrary = package?.manifest.showsInPartLibrary ?? true
            return (showsInLibrary || showsHiddenParts)
                && (activePartSource == .development ? isDevelopmentPack : !isDevelopmentPack)
        }
    }

    /// Dev Parts appears only when a development pack is loaded; Controls
    /// whenever developer tools are on.
    private var availableSources: [PartLibrarySource] {
        [.parts] + (hasDevelopmentParts ? [.development] : []) + [.controls]
    }

    private var activePartSource: PartLibrarySource {
        guard enablesDeveloperTools, availableSources.contains(partSource) else { return .parts }
        return partSource
    }

    private var hasDevelopmentParts: Bool {
        PartType.allCases.contains {
            $0.definition.package?.isDevelopmentPack == true
                && $0.definition.package?.isControlShowcase != true
                && (($0.definition.package?.manifest.showsInPartLibrary ?? true) || showsHiddenParts)
        }
    }

    private var iconSize: PartLibraryIconSize {
        PartLibraryIconSize(rawValue: iconSizeValue) ?? .medium
    }

    private var arrangement: PartLibraryArrangement {
        PartLibraryArrangement(rawValue: arrangementValue) ?? .group
    }
}

nonisolated private enum PartLibrarySource: String, CaseIterable, Identifiable {
    case parts
    case development
    case controls

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .parts: "Parts"
        case .development: "Dev Parts"
        case .controls: "Controls"
        }
    }
}

private struct PartLibraryPanelHeader: View {
    let iconSize: PartLibraryIconSize
    let setIconSize: (PartLibraryIconSize) -> Void
    let arrangement: PartLibraryArrangement
    let setArrangement: (PartLibraryArrangement) -> Void

    var body: some View {
        HStack {
            Text("Parts")
                .font(.headline)
            Spacer()
            Menu {
                Menu("Icon Size") {
                    ForEach(PartLibraryIconSize.allCases) { size in
                        Toggle(
                            size.title,
                            isOn: Binding(
                                get: { iconSize == size },
                                set: { isSelected in
                                    if isSelected {
                                        setIconSize(size)
                                    }
                                }
                            )
                        )
                    }
                }
                Menu("Arrange By") {
                    ForEach(PartLibraryArrangement.allCases) { option in
                        Toggle(
                            option.title,
                            isOn: Binding(
                                get: { arrangement == option },
                                set: { isSelected in
                                    if isSelected {
                                        setArrangement(option)
                                    }
                                }
                            )
                        )
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Part view options")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

nonisolated private enum PartLibraryArrangement: String, CaseIterable, Identifiable {
    case group
    case author
    case tag
    case title

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .group: "Group"
        case .author: "Author"
        case .tag: "Tag"
        case .title: "Title"
        }
    }
}

nonisolated private enum PartLibraryIconSize: String, CaseIterable, Identifiable {
    case list
    case small
    case medium

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .list: "List"
        case .small: "Default"
        case .medium: "Large"
        }
    }

    /// The icon slot's height; its width is 1.5× this — a 3:2 tile.
    var iconSize: CGFloat {
        switch self {
        case .list: 24
        case .small: 48
        case .medium: 60
        }
    }

    var tileWidth: CGFloat {
        switch self {
        case .list: 140
        case .small: 84
        case .medium: 102
        }
    }

    var tileHeight: CGFloat {
        switch self {
        case .list: 44
        case .small: 84
        case .medium: 96
        }
    }

    var gridMinimumWidth: CGFloat {
        switch self {
        case .list: 140
        case .small, .medium: tileWidth
        }
    }
}

struct DeveloperPanel: View {
    @State private var catalog = PartPackageCatalog.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = catalog.revision
        VStack(spacing: 0) {
            HStack {
                Text("Developer")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Parts Updater") {
                        openWindow(id: "part-updates")
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Developer tools")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Divider()

            DeveloperIssuesView(
                issues: issues,
                summaryTitle: summaryTitle,
                summaryDescription: summaryDescription,
                reload: catalog.reloadAllPacks
            )
        }
    }

    private var issues: [DeveloperPackageIssue] {
        catalog.diagnostics.compactMap { url, diagnostics in
            guard !diagnostics.isEmpty else { return nil }
            return DeveloperPackageIssue(url: url, diagnostics: diagnostics)
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var errorCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .error }
        }
    }

    private var warningCount: Int {
        issues.reduce(into: 0) { count, issue in
            count += issue.diagnostics.count { $0.severity == .warning }
        }
    }

    private var summaryTitle: String {
        guard !issues.isEmpty else { return "Parts are healthy" }
        return issues.count == 1 ? "1 part needs attention" : "\(issues.count) parts need attention"
    }

    private var summaryDescription: String {
        guard !issues.isEmpty else { return "All discovered part packages loaded successfully." }
        var parts: [String] = []
        if errorCount > 0 {
            parts.append(errorCount == 1 ? "1 error" : "\(errorCount) errors")
        }
        if warningCount > 0 {
            parts.append(warningCount == 1 ? "1 warning" : "\(warningCount) warnings")
        }
        return parts.joined(separator: ", ")
    }
}

private struct DeveloperIssuesView: View {
    let issues: [DeveloperPackageIssue]
    let summaryTitle: String
    let summaryDescription: String
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reload Parts", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .help("Reload part packages")
            }
            .padding(12)
            Divider()
            if issues.isEmpty {
                ContentUnavailableView(
                    "No Part Issues",
                    systemImage: "checkmark.circle",
                    description: Text("Package validation and loading issues will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(issues) { issue in
                            DeveloperPackageIssueCard(issue: issue)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

private struct ReleaseNoteDraft: Identifiable {
    let id = UUID()
    var text = ""
}

struct DeveloperReleasesView: View {
    let developmentPacks: [URL]
    @State private var selectedPackURL: URL?
    @State private var publishingDirectoryURL = ""
    @State private var releaseVersion = ""
    @State private var releaseNotes = [ReleaseNoteDraft()]
    @State private var isWorking = false
    @State private var operationProgress = 0.0
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var workingTask: Task<Void, Never>?

    var body: some View {
        content
            .onAppear {
                if selectedPackURL == nil { selectedPackURL = developmentPacks.first }
                resetReleaseVersion(for: selectedPack)
            }
            .onChange(of: developmentPacks) { _, packs in
                if selectedPackURL.map({ packs.contains($0) }) != true {
                    selectedPackURL = packs.first
                }
            }
            .onChange(of: selectedPackURL) {
                workingTask?.cancel()
                publishingDirectoryURL = publishingURL(for: selectedPackURL) ?? ""
                resetReleaseVersion(for: selectedPack)
                releaseNotes = [ReleaseNoteDraft()]
                resultMessage = nil
                errorMessage = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if developmentPacks.isEmpty {
            ContentUnavailableView(
                "No Development Pack",
                systemImage: PartDefinition.genericSystemImage,
                description: Text("Convert a part pack to .foundrydevpack before issuing updates.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    Picker("Development Pack", selection: $selectedPackURL) {
                        ForEach(developmentPacks, id: \.self) { url in
                            Text(url.deletingPathExtension().lastPathComponent).tag(Optional(url))
                        }
                    }
                }

                if let selectedPackURL {
                    if let configuration = selectedPack?.metadata.updates,
                       configuration.appcastURL.lastPathComponent == "appcast.php" {
                        issueUpdateView(
                            sourceURL: selectedPackURL,
                            configuration: configuration
                        )
                    } else {
                        prepareForUpdatesView(sourceURL: selectedPackURL)
                    }
                }

                if isWorking || resultMessage != nil || errorMessage != nil {
                    Section {
                        DeveloperReleaseStatus(
                            isWorking: isWorking,
                            progress: operationProgress,
                            resultMessage: resultMessage,
                            errorMessage: errorMessage
                        )
                        if isWorking {
                            Button("Cancel", role: .cancel) { workingTask?.cancel() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var selectedPack: FoundryPack? {
        selectedPackURL.flatMap { try? FoundryPackLoader.load(from: $0) }
    }

    private func prepareForUpdatesView(sourceURL: URL) -> some View {
        Section("Prepare for Updates") {
            Text("Foundry uses the publishing settings to derive the appcast and archive URLs and creates a signing identity in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Publishing URL", value: publishingDirectoryURL.isEmpty ? "Configure Publishing Settings" : publishingDirectoryURL)
            Button("Prepare and Publish Endpoint", systemImage: "checkmark.seal") {
                prepareForUpdates(sourceURL: sourceURL)
            }
            .disabled(!isValidPublishingDirectoryURL(publishingDirectoryURL) || !publisherIsConfigured || isWorking)
        }
    }

    @ViewBuilder
    private func issueUpdateView(
        sourceURL: URL,
        configuration: FoundryPackUpdateConfiguration
    ) -> some View {
        Section {
            if let currentVersion = selectedPack?.metadata.version {
                LabeledContent("Current Version", value: currentVersion)
                LabeledContent("Release Version") {
                    HStack(spacing: 10) {
                        TextField("Release Version", text: $releaseVersion, prompt: Text("1.0.1"))
                            .labelsHidden()
                            .frame(width: 110)
                            .textFieldStyle(.roundedBorder)
                        ControlGroup {
                            Button("Major") { incrementVersion(.major, from: currentVersion) }
                            Button("Minor") { incrementVersion(.minor, from: currentVersion) }
                            Button("Patch") { incrementVersion(.patch, from: currentVersion) }
                        }
                    }
                }
                if !releaseVersion.isEmpty && !isValidReleaseVersion {
                    Label("Enter a semantic version greater than \(currentVersion).", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Publishing Directory")
                    .font(.subheadline.weight(.semibold))
                Text(configuration.appcastURL.deletingLastPathComponent().absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Release")
        }

        Section {
            ForEach($releaseNotes) { $note in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    TextField(
                        "Describe a change",
                        text: $note.text,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    if releaseNotes.count > 1 {
                        Button("Remove Note", systemImage: "minus.circle") {
                            releaseNotes.removeAll { $0.id == note.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button("Add Another Note", systemImage: "plus") {
                releaseNotes.append(ReleaseNoteDraft())
            }
        } header: {
            Text("Release Notes")
        }

        Section {
            Button("Publish Update") {
                issueUpdate(sourceURL: sourceURL)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isWorking
                    || !isValidReleaseVersion
                    || releaseNotes.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }

    private func prepareForUpdates(sourceURL: URL) {
        guard let url = URL(string: publishingDirectoryURL),
              let packID = try? FoundryPackLoader.load(from: sourceURL).identifier else { return }
        let site = PartUpdatePublisherConfiguration.site
        let credential = PublishingCredentialStore.credential(site: site)
        let outputDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "Foundry-Update-Setup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        isWorking = true
        operationProgress = 0
        resultMessage = nil
        errorMessage = nil
        workingTask?.cancel()
        workingTask = Task {
            defer { try? FileManager.default.removeItem(at: outputDirectoryURL) }
            do {
                let setupDirectory = try FoundryPackReleaseBuilder.prepareForUpdates(
                    sourceURL: sourceURL,
                    publishingDirectoryURL: url,
                    outputDirectoryURL: outputDirectoryURL
                )
                try Task.checkCancellation()
                try await PartUpdatePublisher.publishSetup(
                    directory: setupDirectory,
                    packID: packID,
                    site: site,
                    credential: credential,
                    progress: { progress in
                        Task { @MainActor in
                            operationProgress = progress
                        }
                    }
                )
                try await verifyPublishedEndpoint(appcastURL: url.appending(path: "appcast.php"))
                try Task.checkCancellation()
                try FoundryPackReleaseBuilder.finalizeUpdatePreparation(
                    sourceURL: sourceURL,
                    publishingDirectoryURL: url
                )
                PartPackageCatalog.shared.reloadAllPacks()
                resetReleaseVersion(for: try? FoundryPackLoader.load(from: sourceURL))
                resultMessage = "Published the update endpoint successfully."
            } catch is CancellationError {
                errorMessage = "Preparation was cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func issueUpdate(sourceURL: URL) {
        guard let pack = try? FoundryPackLoader.load(from: sourceURL) else { return }
        let packID = pack.identifier
        let version = releaseVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = PartUpdatePublisherConfiguration.site
        let credential = PublishingCredentialStore.credential(site: site)
        let outputDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "Foundry-Release-Output-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let notes = releaseNotes.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let request = FoundryPackReleaseBuilder.Request(
            sourceURL: sourceURL,
            outputDirectoryURL: outputDirectoryURL,
            version: version,
            releaseNotes: notes
        )
        isWorking = true
        operationProgress = 0
        resultMessage = nil
        errorMessage = nil
        workingTask?.cancel()
        workingTask = Task {
            defer { try? FileManager.default.removeItem(at: outputDirectoryURL) }
            do {
                guard let configuration = pack.metadata.updates else {
                    throw FoundryPackUpdateError.invalidMetadata("Prepare this pack for updates before issuing a release.")
                }
                try validatePublishingDestination(site: site, configuration: configuration, packID: packID)
                let result = try await FoundryPackReleaseBuilder.create(request)
                try Task.checkCancellation()
                try await PartUpdatePublisher.publish(
                    directory: result.outputDirectoryURL,
                    packID: packID,
                    site: site,
                    credential: credential,
                    progress: { progress in
                        Task { @MainActor in
                            operationProgress = progress
                        }
                    }
                )
                try await verifyPublishedRelease(
                    appcastURL: configuration.appcastURL,
                    packID: packID,
                    version: version
                )
                resultMessage = "Published and verified version \(version)."
                releaseNotes = [ReleaseNoteDraft()]
                releaseVersion = version
                incrementVersion(.patch, from: version)
            } catch is CancellationError {
                errorMessage = "Publishing was cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private enum VersionComponent {
        case major
        case minor
        case patch
    }

    private var isValidReleaseVersion: Bool {
        guard let source = selectedPack?.metadata.version.flatMap(SemanticVersion.init),
              let release = SemanticVersion(releaseVersion.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return release > source
    }

    private func incrementVersion(_ part: VersionComponent, from fallback: String) {
        let value = SemanticVersion(releaseVersion) == nil ? fallback : releaseVersion
        let core = value.split(separator: "+", maxSplits: 1)[0]
            .split(separator: "-", maxSplits: 1)[0]
            .split(separator: ".")
            .compactMap { Int($0) }
        guard core.count == 3 else { return }

        switch part {
        case .major:
            releaseVersion = "\(core[0] + 1).0.0"
        case .minor:
            releaseVersion = "\(core[0]).\(core[1] + 1).0"
        case .patch:
            releaseVersion = "\(core[0]).\(core[1]).\(core[2] + 1)"
        }
    }

    private func resetReleaseVersion(for pack: FoundryPack?) {
        guard let currentVersion = pack?.metadata.version else {
            releaseVersion = ""
            return
        }
        releaseVersion = currentVersion
        if pack?.metadata.updates != nil {
            incrementVersion(.patch, from: currentVersion)
        }
    }

    private var publisherIsConfigured: Bool {
        let site = PartUpdatePublisherConfiguration.site
        return [.ftp, .ftps, .sftp].contains(site.publishingDestination)
            && !site.publishingHost.isEmpty
            && !site.publishingUsername.isEmpty
            && !site.publishingRemotePath.isEmpty
            && URL(string: site.publicURL)?.scheme == "https"
    }

    private func publishingURL(for sourceURL: URL?) -> String? {
        guard let sourceURL,
              let identifier = try? FoundryPackLoader.load(from: sourceURL).identifier else { return nil }
        return URL(string: PartUpdatePublisherConfiguration.site.publicURL)?
            .appending(path: identifier)
            .absoluteString
    }

    private func verifyPublishedRelease(appcastURL: URL, packID: String, version: String) async throws {
        var request = URLRequest(url: appcastURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The published appcast could not be reached.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: data)
        guard appcast.packID == packID else {
            throw FoundryPackUpdateError.wrongPack(appcast.packID)
        }
        let matches = appcast.releases.filter { $0.version == version }
        guard matches.count == 1 else {
            throw FoundryPackUpdateError.invalidMetadata("The published appcast does not contain version \(version).")
        }
        let releaseDirectoryURL = appcastURL
            .deletingLastPathComponent()
            .appending(path: "\(packID) \(version)", directoryHint: .isDirectory)
        let expectedDownloadURL = releaseDirectoryURL
            .appending(path: "\(packID) \(version).foundrypack.zip")
        let expectedReleaseNotesURL = releaseDirectoryURL.appending(path: "release-notes.html")
        guard matches[0].downloadURL == expectedDownloadURL,
              matches[0].releaseNotesURL == expectedReleaseNotesURL else {
            throw FoundryPackUpdateError.invalidMetadata(
                "The published release URLs do not match the configured publishing directory."
            )
        }
    }

    private func verifyPublishedEndpoint(appcastURL: URL) async throws {
        var request = URLRequest(url: appcastURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw FoundryPackUpdateError.invalidMetadata("The published update endpoint could not be reached.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let appcast = try decoder.decode(FoundryPackAppcast.self, from: data)
        guard appcast.formatVersion == FoundryPackAppcast.currentFormatVersion else {
            throw FoundryPackUpdateError.unsupportedAppcast(appcast.formatVersion)
        }
    }

    private func validatePublishingDestination(
        site: Site,
        configuration: FoundryPackUpdateConfiguration,
        packID: String
    ) throws {
        guard let configuredAppcastURL = URL(string: site.publicURL)?
            .appending(path: packID)
            .appending(path: "appcast.php"),
              configuredAppcastURL == configuration.appcastURL else {
            throw FoundryPackUpdateError.invalidMetadata(
                "Publishing settings have changed since this pack was prepared. Restore those settings or prepare the pack again before publishing."
            )
        }
    }

    private func isValidPublishingDirectoryURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.query == nil
            && url.fragment == nil
    }
}

private struct DeveloperReleaseStatus: View {
    let isWorking: Bool
    let progress: Double
    let resultMessage: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isWorking {
                ProgressView("Uploading…", value: progress, total: 1)
            }
            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct DeveloperPackageIssue: Identifiable {
    let url: URL
    let diagnostics: [PartPackageDiagnostic]
    let displayName: String
    let identifier: String?

    var id: URL { url }
    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    init(url: URL, diagnostics: [PartPackageDiagnostic]) {
        self.url = url
        self.diagnostics = diagnostics

        let manifestURL = url.appending(path: "manifest.json")
        let manifest: [String: Any]?
        if let data = try? Data(contentsOf: manifestURL),
           let object = try? JSONSerialization.jsonObject(with: data) {
            manifest = object as? [String: Any]
        } else {
            manifest = nil
        }
        let title = manifest?["title"] as? String
        let identifier = manifest?["id"] as? String
        displayName = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        self.identifier = identifier?.isEmpty == false ? identifier : nil
    }
}

private struct DeveloperPackageIssueCard: View {
    let issue: DeveloperPackageIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: issue.hasErrors ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.hasErrors ? .red : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.displayName)
                        .font(.headline)
                    Text(issue.hasErrors ? "Failed to load" : "Loaded with warnings")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(issue.hasErrors ? .red : .orange)
                    if let identifier = issue.identifier {
                        Text(identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                Button("Show in Finder", systemImage: "finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([issue.url])
                }
                .labelStyle(.iconOnly)
                .help("Show package in Finder")
            }

            Divider()

            ForEach(Array(issue.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnostic.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(diagnostic.location)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text(issue.url.path(percentEncoded: false))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PartLibrarySection: Identifiable {
    let id: String
    let title: String
    let types: [PartType]
}

/// The shared bottom-of-panel search field: filters the panel's own list in
/// place. The clear button is always laid out so the row never changes height.
struct PanelSearchField: View {
    let prompt: String
    @Binding var text: String

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
            .opacity(hasText ? 1 : 0)
            .allowsHitTesting(hasText)
            .accessibilityHidden(!hasText)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

/// The Pages-panel header pattern for the library panels: title on the left,
/// a plus menu with the panel's creation actions on the right.
private struct LibraryPanelHeader<MenuContent: View>: View {
    let title: String
    let accessibilityLabel: String
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Menu {
                menu()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .accessibilityLabel(accessibilityLabel)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// Which of a panel's content tabs is showing: the document's own content,
/// the app-wide library (My Library plus installed packs), or — only when
/// any exist — development packs, matching the Parts panel's Dev split.
enum LibraryPanelTab: String, CaseIterable, Identifiable {
    case project
    case library
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: "Project"
        case .library: "Library"
        case .dev: "Dev"
        }
    }
}

struct ReusablePartLibraryPanel: View {
    /// This document's own templates — the Project tab.
    let projectNodes: [ReusablePartNode]
    /// The Library tab: My Library plus installed packs with templates.
    let librarySections: [TemplatePanelSection]
    /// The Dev tab: every other development pack; the tab only appears when
    /// there are any, matching the Parts panel's Dev split.
    let devSections: [TemplatePanelSection]
    @Binding var selectedNodeID: UUID?
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    let duplicateDefinition: (UUID) -> Void
    let revealDefinition: (UUID) -> Void
    /// Creates a folder in the identified section's organization.
    let createFolder: (String, String) -> Void
    let renameFolder: (UUID, String) -> Void
    let deleteFolder: (UUID) -> Void
    /// A node dropped at a placement inside the identified section; the owner
    /// decides between reorder, cross-section move, and copy-out.
    let moveNode: (UUID, String, ReusablePartPlacement) -> Bool
    let saveDraggedParts: ([UUID], String) -> Bool
    /// Copies a project template into My Library.
    let addToLibrary: (UUID) -> Void
    /// Copies a library template into the project.
    let addToProject: (UUID) -> Void

    @State private var tab: LibraryPanelTab = .project
    @State private var searchText = ""
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var folderDestinationSectionID: String?
    @State private var nodesToDelete: [ReusablePartNode] = []

    private var availableTabs: [LibraryPanelTab] {
        devSections.isEmpty ? [.project, .library] : [.project, .library, .dev]
    }

    private var activeSections: [TemplatePanelSection] {
        switch tab {
        case .project:
            [TemplatePanelSection(
                id: TemplatePanelSection.projectSectionID,
                title: nil,
                isEditable: true,
                nodes: projectNodes
            )]
        case .library:
            librarySections
        case .dev:
            devSections
        }
    }

    private var definitions: [ReusablePartDefinition] {
        activeSections.flatMap(\.nodes).allDefinitions
    }

    private var searchResults: [ReusablePartDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return definitions.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Searching flattens the active tab down to matching templates in one
    /// headerless, read-only list; organizing resumes when the search clears.
    private var displayedSections: [TemplatePanelSection] {
        isSearching
            ? [TemplatePanelSection(
                id: "search",
                title: nil,
                isEditable: false,
                nodes: searchResults.map(ReusablePartNode.part)
            )]
            : activeSections
    }

    /// The sections New Folder can create into on the active tab — every
    /// editable section is an explicit menu target, never a silent default.
    private var folderCreationTargets: [TemplatePanelSection] {
        activeSections.filter(\.isEditable)
    }

    /// Everywhere a row can be sent from the Move/Copy to menu: the project
    /// plus every editable pack, across all tabs. Search results are
    /// transient rows, so the menu rests while searching.
    private var moveDestinations: [LibraryMoveDestination] {
        guard !isSearching else { return [] }
        return [LibraryMoveDestination(sectionID: TemplatePanelSection.projectSectionID, title: "Project")]
            + (librarySections + devSections)
                .filter(\.isEditable)
                .map { LibraryMoveDestination(sectionID: $0.id, title: $0.title ?? "My Library") }
    }

    private func beginNamingFolder(inSection sectionID: String) {
        folderName = ""
        folderDestinationSectionID = sectionID
        isNamingFolder = true
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryPanelHeader(title: "Templates", accessibilityLabel: "Add Template Folder") {
                if folderCreationTargets.count == 1, let target = folderCreationTargets.first {
                    Button("New Folder…", systemImage: "folder.badge.plus") {
                        beginNamingFolder(inSection: target.id)
                    }
                } else {
                    ForEach(folderCreationTargets, id: \.id) { target in
                        Button(
                            "New Folder in “\(target.title ?? "Project")”…",
                            systemImage: "folder.badge.plus"
                        ) {
                            beginNamingFolder(inSection: target.id)
                        }
                    }
                }
            }
            Divider()
            LibraryPanelTabPicker(tab: $tab, tabs: availableTabs)
            TemplatesOutlineView(
                kind: .templates,
                sections: displayedSections,
                selectedNodeID: $selectedNodeID,
                moveNode: { id, sectionID, placement in
                    isSearching ? false : moveNode(id, sectionID, placement)
                },
                saveDroppedParts: saveDraggedParts,
                renameDefinition: renameDefinition,
                renameFolder: renameFolder,
                duplicateDefinition: duplicateDefinition,
                revealDefinition: revealDefinition,
                canRevealDefinition: { id in
                    projectNodes.node(withID: id) == nil
                },
                transferActionTitle: tab == .project ? "Add to My Library" : "Add to Project",
                transferDefinition: tab == .project ? addToLibrary : addToProject,
                requestDelete: { ids in
                    nodesToDelete = ids.compactMap { id in
                        activeSections.lazy.compactMap { $0.nodes.node(withID: id) }.first
                    }
                },
                moveDestinations: moveDestinations,
                emptySectionPlaceholder: "Drop a part here to save a template"
            )
            .overlay {
                if isSearching && searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .allowsHitTesting(false)
                } else if !isSearching && tab == .project && projectNodes.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: WorkspacePanel.reusableParts.systemImage,
                        description: Text("Save a part as a template from Structure, or drop one here.")
                    )
                    .allowsHitTesting(false)
                }
            }
            Divider()
            PanelSearchField(prompt: "Search Templates", text: $searchText)
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                guard let sectionID = folderDestinationSectionID else { return }
                createFolder(
                    folderName.trimmingCharacters(in: .whitespacesAndNewlines),
                    sectionID
                )
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if let sectionID = folderDestinationSectionID,
               let title = activeSections.first(where: { $0.id == sectionID })?.title {
                Text("Creates the folder in \(title).")
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteAlertBinding) {
            Button(deleteButtonTitle, role: .destructive) {
                for node in nodesToDelete {
                    switch node {
                    case .part(let definition): deleteDefinition(definition.id)
                    case .folder(let folder): deleteFolder(folder.id)
                    }
                }
                nodesToDelete = []
            }
            Button("Cancel", role: .cancel) { nodesToDelete = [] }
        } message: {
            Text(deleteMessage)
        }
    }

    private func nodeName(_ node: ReusablePartNode) -> String {
        switch node {
        case .part(let definition): definition.name
        case .folder(let folder): folder.name
        }
    }

    private var deletesFolder: Bool {
        nodesToDelete.contains { if case .folder = $0 { true } else { false } }
    }

    private var deleteTitle: String {
        nodesToDelete.count > 1
            ? "Delete \(nodesToDelete.count) Items?"
            : "Delete \(nodesToDelete.first.map(nodeName) ?? "Template")?"
    }

    private var deleteButtonTitle: String {
        if nodesToDelete.count > 1 { return "Delete \(nodesToDelete.count) Items" }
        return deletesFolder ? "Delete Folder" : "Delete Template"
    }

    private var deleteMessage: String {
        let scope = tab == .project ? "this project" : "every project"
        if deletesFolder {
            return "Also deletes the templates inside, for \(scope). Parts already added to pages are unchanged."
        } else if nodesToDelete.count > 1 {
            return "Removes them from the library for \(scope). Parts already added to pages are unchanged."
        } else {
            return "Removes it from the library for \(scope). Parts already added to pages are unchanged."
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { !nodesToDelete.isEmpty }, set: { if !$0 { nodesToDelete = [] } })
    }

}

/// The Project | Library | Dev switch shared by the Templates and Assets
/// panels, styled like the Parts panel's source picker. The Dev tab appears
/// only when the caller has development content to show.
struct LibraryPanelTabPicker: View {
    @Binding var tab: LibraryPanelTab
    var tabs: [LibraryPanelTab] = [.project, .library]

    var body: some View {
        Picker("Content source", selection: $tab) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .buttonSizing(.flexible)
        .pickerStyle(.palette)
        .controlSize(.small)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: tabs) {
            if !tabs.contains(tab) { tab = .project }
        }
    }
}

private struct PartLibraryTile: View {
    let type: PartType
    let iconSize: PartLibraryIconSize
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Group {
                if iconSize == .list {
                    HStack(spacing: 8) {
                        partIcon
                        partTitle
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: iconSize.tileHeight, maxHeight: iconSize.tileHeight)
                } else {
                    VStack(spacing: 6) {
                        partIcon
                        partTitle
                            .frame(maxWidth: .infinity)
                    }
                    .padding(6)
                    .frame(width: iconSize.tileWidth, height: iconSize.tileHeight)
                }
            }
            // The accent ring carries the selection; the fill is the
            // system's, which reads as a subtle tonal step when unfocused.
            .background(
                isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.quinary),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quinary, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName), drag to add")
        .accessibilityIdentifier("part-library-\(type.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var partIcon: some View {
        PartLibraryIcon(
            type: type,
            size: iconSize.iconSize
        )
    }

    // One size for every tile: long names truncate rather than shrink, so
    // the grid never mixes text sizes. The tooltip carries the full name.
    // The title stays primary — the system selection colour can be pale
    // when unfocused, where white text vanishes in light appearance.
    private var partTitle: some View {
        Text(type.displayName)
            .lineLimit(1)
            .truncationMode(.tail)
            .font(.caption)
            .foregroundStyle(Color.primary)
            .help(type.displayName)
    }
}

/// One tinted tile behind a white stencil glyph — the shared rendering for
/// every part-icon surface except the structure tree. The composed image
/// gives SVG stencils and SF Symbols identical geometry on the tile.
private struct PartIconTile: View {
    let specification: PartIconSpecification
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(nsImage: specification.tileImage(size: NSSize(width: width, height: height)))
            .resizable()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// A part's artwork on the Parts panel's 3:2 landscape tile; `size` is the
/// tile height.
struct PartLibraryIcon: View {
    let type: PartType
    let size: CGFloat

    var body: some View {
        PartIconTile(specification: type.iconSpecification, width: size * 1.5, height: size)
    }
}

/// The part's square 1:1 icon — inspectors and other non-panel contexts.
struct PartSquareIcon: View {
    let type: PartType
    let size: CGFloat

    var body: some View {
        PartIconTile(specification: type.iconSpecification, width: size, height: size)
    }
}

private struct PartDragPreview: View {
    let name: String
    let systemImage: String

    var body: some View {
        Label(name, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 150, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}


struct GlobalPartLibraryPanel: View {
    let library: [ReusablePartNode]
    @Binding var selectedNodeID: UUID?
    let renameDefinition: (UUID, String) -> Void
    let deleteDefinition: (UUID) -> Void
    let duplicateDefinition: (UUID) -> Void
    let createFolder: (String) -> Void
    let renameFolder: (UUID, String) -> Void
    let deleteFolder: (UUID) -> Void
    let moveNode: (UUID, ReusablePartPlacement) -> Bool
    let saveDraggedParts: ([UUID]) -> Bool

    @State private var searchText = ""
    @State private var isNamingFolder = false
    @State private var folderName = ""
    @State private var nodesToDelete: [ReusablePartNode] = []

    private var definitions: [ReusablePartDefinition] { library.allDefinitions }

    private var searchResults: [ReusablePartDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return definitions.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Searching filters the same tree down to matching globals as a flat
    /// list — one outline, one presentation, whether filtered or not.
    private var displayedNodes: [ReusablePartNode] {
        isSearching ? searchResults.map(ReusablePartNode.part) : library
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryPanelHeader(title: "Globals", accessibilityLabel: "Add Global Folder") {
                Button("New Folder…", systemImage: "folder.badge.plus") {
                    folderName = ""
                    isNamingFolder = true
                }
            }
            Divider()
            TemplatesOutlineView(
                kind: .globals,
                // Globals have one source, so the outline renders headerless.
                sections: [TemplatePanelSection(
                    id: "globals",
                    title: nil,
                    isEditable: true,
                    nodes: displayedNodes
                )],
                selectedNodeID: $selectedNodeID,
                // Reordering a filtered list would silently reorganize the
                // real tree; moves resume when the search clears.
                moveNode: { id, _, placement in
                    isSearching ? false : moveNode(id, placement)
                },
                saveDroppedParts: { ids, _ in saveDraggedParts(ids) },
                renameDefinition: renameDefinition,
                renameFolder: renameFolder,
                duplicateDefinition: duplicateDefinition,
                revealDefinition: nil,
                canRevealDefinition: nil,
                transferActionTitle: nil,
                transferDefinition: nil,
                requestDelete: { ids in
                    nodesToDelete = ids.compactMap { library.node(withID: $0) }
                },
                moveDestinations: [],
                emptySectionPlaceholder: nil
            )
            .overlay {
                if displayedNodes.isEmpty {
                    if isSearching {
                        ContentUnavailableView.search(text: searchText)
                            .allowsHitTesting(false)
                    } else {
                        ContentUnavailableView(
                            "No Globals",
                            systemImage: WorkspacePanel.globalParts.systemImage,
                            description: Text("Save a part as global from Structure, or drop one here.")
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            Divider()
            PanelSearchField(prompt: "Search Globals", text: $searchText)
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                createFolder(folderName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(deleteTitle, isPresented: deleteAlertBinding) {
            Button(deleteButtonTitle, role: .destructive) {
                for node in nodesToDelete {
                    switch node {
                    case .part(let definition): deleteDefinition(definition.id)
                    case .folder(let folder): deleteFolder(folder.id)
                    }
                }
                nodesToDelete = []
            }
            Button("Cancel", role: .cancel) { nodesToDelete = [] }
        } message: {
            Text(deleteMessage)
        }
    }

    private func nodeName(_ node: ReusablePartNode) -> String {
        switch node {
        case .part(let definition): definition.name
        case .folder(let folder): folder.name
        }
    }

    private var deletesFolder: Bool {
        nodesToDelete.contains { if case .folder = $0 { true } else { false } }
    }

    private var deleteTitle: String {
        nodesToDelete.count > 1
            ? "Delete \(nodesToDelete.count) Items?"
            : "Delete \(nodesToDelete.first.map(nodeName) ?? "Global Part")?"
    }

    private var deleteButtonTitle: String {
        if nodesToDelete.count > 1 { return "Delete \(nodesToDelete.count) Items" }
        return deletesFolder ? "Delete Folder" : "Delete Global Part"
    }

    private var deleteMessage: String {
        if deletesFolder {
            "Also deletes the global parts inside. Existing instances will be detached and keep their current content."
        } else {
            "Existing instances will be detached and keep their current content."
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { !nodesToDelete.isEmpty }, set: { if !$0 { nodesToDelete = [] } })
    }
}

struct StructurePanel: View {
    let page: Page?
    let globalPartNames: [UUID: String]
    @Binding var selectedPartIDs: Set<UUID>
    @Binding var selectedPartID: UUID?
    @Binding var isPageSelected: Bool
    @Binding var expandedPartIDs: Set<UUID>
    let renamePart: (UUID, String) -> Void
    let canMovePartsToPlacement: ([UUID], PartPlacement) -> Bool
    let movePartsToPlacement: ([UUID], PartPlacement) -> Bool
    let insertPart: (PartType, PartPlacement) -> Bool
    let insertReusablePart: (UUID, PartPlacement) -> Bool
    let insertGlobalPart: (UUID, PartPlacement) -> Bool
    let duplicatePart: () -> Void
    let copyPart: () -> Void
    let pastePart: () -> Void
    let movePart: (Int) -> Void
    let outdentPart: () -> Void
    let deletePart: () -> Void
    let canPastePart: Bool
    let saveReusablePart: (String) -> Void
    let saveGlobalPart: (String) -> Void
    let setGlobalPartLinked: (UUID, Bool) -> Void
    let explodeGlobalPart: (UUID) -> Void
    @State private var isNamingReusablePart = false
    @State private var reusablePartName = ""
    @State private var isNamingGlobalPart = false
    @State private var globalPartName = ""
    @State private var isPageExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if let page {
                StructureOutlineView(
                    page: page,
                    globalPartNames: globalPartNames,
                    selectedPartIDs: $selectedPartIDs,
                    primarySelectedPartID: $selectedPartID,
                    isPageSelected: $isPageSelected,
                    isPageExpanded: $isPageExpanded,
                    expandedItemIDs: $expandedPartIDs,
                    renamePart: renamePart,
                    canMoveParts: canMovePartsToPlacement,
                    moveParts: movePartsToPlacement,
                    insertPart: insertPart,
                    insertReusablePart: insertReusablePart,
                    insertGlobalPart: insertGlobalPart,
                    duplicatePart: duplicatePart,
                    copyPart: copyPart,
                    pastePart: pastePart,
                    canPastePart: canPastePart,
                    saveAsReusablePart: {
                        reusablePartName = $0
                        isNamingReusablePart = true
                    },
                    saveAsGlobalPart: {
                        globalPartName = $0
                        isNamingGlobalPart = true
                    },
                    setGlobalPartLinked: setGlobalPartLinked,
                    explodeGlobalPart: explodeGlobalPart,
                    movePart: movePart,
                    outdentPart: outdentPart,
                    deletePart: deletePart
                )
            } else {
                ContentUnavailableView("No Page", systemImage: "doc")
            }
        }
        .alert("Save as Template", isPresented: $isNamingReusablePart) {
            TextField("Name", text: $reusablePartName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveReusablePart(reusablePartName) }
                .disabled(reusablePartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The selected part and its children will be available from the Templates panel.")
        }
        .alert("Save Global Part", isPresented: $isNamingGlobalPart) {
            TextField("Name", text: $globalPartName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveGlobalPart(globalPartName) }
                .disabled(globalPartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Every linked instance will update when this global part is edited.")
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let selectedPartID, let page else { return }
        expandedPartIDs.formUnion(page.parts.ancestorIDs(of: selectedPartID))
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(selectedPartID, anchor: .center)
        }
    }

    private func acceptAtEnd(_ payload: PartDragPayload) -> Bool {
        switch payload {
        case .library(let type): insertPart(type, .end)
        case .reusable(let id): insertReusablePart(id, .end)
        case .global(let id): insertGlobalPart(id, .end)
        case .node(let id): movePartsToPlacement([id], .end)
        case .nodes(let ids): movePartsToPlacement(ids, .end)
        }
    }

    private func visibleParts(in page: Page) -> [StructureTreeItem] {
        StructureTreeItem.flatten(page.parts, expandedIDs: expandedPartIDs)
    }

    private func applyReorder(
        _ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>
    ) {
        let placement: PartPlacement
        switch difference.destination.position {
        case .before(let targetID):
            placement = .before(targetID)
        case .end:
            placement = .end
        }
        for sourceID in difference.sources {
            _ = movePartsToPlacement([sourceID], placement)
        }
    }

}

nonisolated struct StructureTreeItem: Identifiable, Sendable {
    let part: PartNode
    let depth: Int

    var id: UUID { part.id }

    static func flatten(
        _ parts: [PartNode],
        expandedIDs: Set<UUID>,
        depth: Int = 0
    ) -> [StructureTreeItem] {
        parts.flatMap { part in
            var result = [StructureTreeItem(part: part, depth: depth)]
            if expandedIDs.contains(part.id) {
                result += flatten(part.children, expandedIDs: expandedIDs, depth: depth + 1)
            }
            return result
        }
    }
}

private struct StructureEndDropZone: View {
    let isEmpty: Bool
    let accept: (PartDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Label(
            isEmpty ? "Drop a part here" : "Drop at page end",
            systemImage: isEmpty ? "square.and.arrow.down" : "arrow.down.to.line"
        )
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity, minHeight: isEmpty ? 64 : 28)
        .background(
            isTargeted ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(isEmpty ? 0.35 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let payload = PartDragPayload(value) else { return false }
            return accept(payload)
        } isTargeted: {
            isTargeted = $0
        }
    }
}

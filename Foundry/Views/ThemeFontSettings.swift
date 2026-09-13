import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct ThemeFontCard<Content: View>: View {
    var title: String? = nil
    var showsCard: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(showsCard ? 12 : 0)
        .background {
            if showsCard {
                RoundedRectangle(cornerRadius: 12).fill(.background)
            }
        }
        .overlay {
            if showsCard {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ThemeFontSettings: View {
    let theme: Theme
    let assets: [ProjectAsset]
    let session: ThemeEditorSession

    @State private var selection: ThemeFontReference = .role(.body)
    @State private var fontPendingDeletion: ThemeCustomFont?
    @State private var googleFonts = GoogleFontsService.fallback
    @State private var search = ""
    @State private var category = GoogleFontCategory.all
    @State private var isLoadingGoogleFonts = false
    @State private var googleFontsError: String?
    @State private var googleFontsReloadID = 0
    @State private var isImportingFonts = false
    @State private var fontImportError: String?
    @State private var isFontDropTargeted = false
    @State private var previewFontAssetID: UUID?
    @State private var showsIncludedStyles = false

    private var editor: ProjectEditor { session.editor }
    private var definition: ThemeFontDefinition { session.font(for: selection) }

    var body: some View {
        HStack(spacing: 0) {
            fontSidebar
                .frame(width: 200)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                    assignmentCard
                    if isGoogleFont {
                        HSplitView {
                            googleFontCard
                                .padding(.trailing, 12)
                                .frame(minWidth: 210, idealWidth: 230, maxWidth: 320)
                            googlePreviewCard
                                .padding(.leading, 12)
                                .frame(minWidth: 200, maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                        .disabled(!canEditSelection)
                    } else {
                        ScrollView {
                        ThemeEditorColumns(equalColumns: true) {
                            switch definition.source {
                            case .system:
                                systemFontCard
                            case .remote:
                                googleFontCard
                            case .bundled(let files):
                                projectFontCard(files: files)
                            }
                        } preview: {
                            switch definition.source {
                            case .system:
                                systemPreviewCard
                            case .remote:
                                googlePreviewCard
                            case .bundled:
                                projectFontDetailsCard
                            }
                        }
                        .disabled(!canEditSelection)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("theme-section-Fonts")
        .controlSize(.regular)
        .task(id: googleCatalogueTaskID) {
            guard case .remote = definition.source else { return }
            await loadGoogleFonts()
        }
        .onChange(of: theme.typography.customFonts.map(\.id)) {
            if case .custom(let id) = selection,
               !theme.typography.customFonts.contains(where: { $0.id == id }) {
                selectFont(.role(.body))
            }
        }
        .onChange(of: session.document.site.themeSourceID) {
            selectFont(.role(.body))
        }
        .onChange(of: storedDefinition) {
            session.discardFontPreview()
        }
        .onChange(of: selection) { showsIncludedStyles = false }
        .onChange(of: definition.family) { showsIncludedStyles = false }
        .onDisappear { session.discardFontPreview() }
        .confirmationDialog(
            "Choose a replacement for \(fontPendingDeletion?.name ?? "this custom font")",
            isPresented: fontDeletionPresented,
            titleVisibility: .visible
        ) {
            ForEach(fontReplacementChoices) { replacement in
                Button("Replace with \(replacement.label)") {
                    guard let pending = fontPendingDeletion else { return }
                    session.discardFontPreview()
                    editor.removeThemeCustomFont(id: pending.id, replacingWith: replacement.value)
                    selection = .role(.body)
                    fontPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { fontPendingDeletion = nil }
        } message: {
            Text("Foundry will update every block using this font before deleting it.")
        }
        .fileImporter(
            isPresented: $isImportingFonts,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { importFontURL(url, reference: selection) }
            case .failure(let error):
                fontImportError = error.localizedDescription
            }
        }
        .alert("Couldn’t Import Font", isPresented: fontImportErrorPresented) {
            Button("OK", role: .cancel) { fontImportError = nil }
        } message: {
            Text(fontImportError ?? "The font file could not be read.")
        }
    }

    private var assignmentCard: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 12) {
            GridRow {
                Text("Name")
                if case .custom(let id) = selection {
                    TextField("Custom font name", text: customNameBinding(id: id))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                } else if case .role(let role) = selection {
                    HStack {
                        Text(role.title)
                        Spacer()
                        if !canEditSelection {
                            Image(systemName: "lock")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Built-in theme")
                                .help("Create a new theme to edit its fonts.")
                        }
                    }
                }
            }
            .frame(minHeight: 28)

            GridRow {
                Text("Source")
                Picker("Font source", selection: sourceKindBinding) {
                    ForEach(ThemeFontSourceChoice.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 28)
            .disabled(!canEditSelection)
        }
    }

    private var canEditSelection: Bool {
        if case .custom = selection { return true }
        return session.canEditTheme
    }

    private var isGoogleFont: Bool {
        if case .remote = definition.source { return true }
        return false
    }

    private var fontSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Fonts").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    session.discardFontPreview()
                    selection = .custom(editor.addThemeCustomFont())
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add Custom Font")
                .accessibilityLabel("Add Custom Font")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            List(selection: sidebarSelectionBinding) {
                ForEach(theme.typography.customFonts) { font in
                    Text(font.name.isEmpty ? "Untitled Font" : font.name)
                        .tag(ThemeFontReference.custom(font.id))
                        .contextMenu {
                            Button("Delete Font…", systemImage: "trash", role: .destructive) {
                                fontPendingDeletion = font
                            }
                        }
                }
                Section("Theme Fonts") {
                    ForEach(ThemeFontRole.allCases) { role in
                        Text(role.title).tag(ThemeFontReference.role(role))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            if case .custom(let id) = selection {
                HStack {
                    Button {
                        fontPendingDeletion = theme.typography.customFonts.first { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete Custom Font")
                    .accessibilityLabel("Delete Custom Font")
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var systemFontCard: some View {
        ThemeFontCard(title: "Font names") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("system-ui, sans-serif", text: fontNamesBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Font names, in order of preference")
                    .help("Separate names with commas. The browser uses the first available font on the visitor’s device.")
            }
        }
    }

    private var systemPreviewCard: some View {
        ThemeFontCard(title: "Preview") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aa Bb Cc").font(systemPreviewFont(size: 28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(systemPreviewFont(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789")
                    .font(systemPreviewFont(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Preview using fonts available on this Mac")
        }
    }

    private var googleFontCard: some View {
        ThemeFontCard(showsCard: false) {
            FontSearchField(text: $search) {
                    if let family = filteredGoogleFonts.first?.family {
                        googleFamilyBinding.wrappedValue = family
                    }
                }
                .frame(height: 24)
            Picker("Category", selection: $category) {
                ForEach(GoogleFontCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }

            if isLoadingGoogleFonts {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the catalogue…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let googleFontsError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(googleFontsError).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Retry") { googleFontsReloadID += 1 }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            List(filteredGoogleFonts, selection: googleFamilyBinding) { font in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(font.family).fontWeight(.medium)
                        Text("\(font.styleCount) style\(font.styleCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if font.family == storedDefinition.family {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Applied font")
                    }
                }
                .padding(.vertical, 3)
                .tag(font.family)
                .disabled(font.faces.isEmpty)
                .accessibilityElement(children: .combine)
            }
            .listStyle(.inset)
            .frame(minHeight: 160, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if filteredGoogleFonts.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .accessibilityLabel("Google font families")
        }
    }

    private var googlePreviewCard: some View {
        ThemeFontCard(showsCard: false) {
            HStack(spacing: 8) {
                Button("Choose included styles") {
                    if definition.googleConfiguration == nil,
                       let family = googleFonts.first(where: { $0.family == definition.family }), !family.faces.isEmpty {
                        applyIncludedStyles(.init(available: family.faces, included: family.faces))
                    }
                    showsIncludedStyles = true
                }
                .help("Choose which weights and styles this font includes.")
                .disabled(availableGoogleFaces.count <= 1 && !isVariableGoogleFont)
                .popover(isPresented: $showsIncludedStyles, arrowEdge: .top) {
                    ScrollView {
                        if let configuration = definition.googleConfiguration {
                            VStack(alignment: .leading, spacing: 12) {
                            GoogleFontFacesEditor(configuration: configuration) {
                                applyIncludedStyles($0)
                            }
                            GoogleFontFileSizeLabel(stylesheetURL: configuration.stylesheetURL(family: definition.family))
                            }
                            .padding(16)
                        } else {
                            Text("Load the Google Fonts catalogue to configure included styles.")
                                .padding(16)
                        }
                    }
                    .frame(width: 460, height: includedStylesHeight)
                }
                if isVariableGoogleFont {
                    Text("Variable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .help("This font supports a variable weight range.")
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            GoogleFontSpecimenView(family: definition.family, stylesheetURL: googleStylesheetURL,
                includedFaces: definition.googleConfiguration?.validIncluded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Rectangle()
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }

    private var availableGoogleFaces: [GoogleFontFace] {
        definition.googleConfiguration?.available
            ?? googleFonts.first(where: { $0.family == definition.family })?.faces
            ?? []
    }

    private var isVariableGoogleFont: Bool {
        availableGoogleFaces.contains(where: \.isVariable)
    }

    private func applyIncludedStyles(_ configuration: GoogleFontConfiguration) {
        guard !configuration.validIncluded.isEmpty else { return }
        var font = definition
        font.applyGoogleConfiguration(configuration)
        editor.setThemeFontDefinition(font, reference: selection, actionName: "Change Included Font Styles")
    }

    private var includedStylesHeight: CGFloat {
        guard let configuration = definition.googleConfiguration else { return 100 }
        let rowCount = [false, true].map { italic in
            configuration.available.filter { $0.italic == italic }
                .reduce(0) { $0 + ($1.isVariable ? 3 : 1) }
        }.max() ?? 1
        return min(360, 180 + CGFloat(rowCount) * 28)
    }

    private func projectFontCard(files: [String]) -> some View {
        ThemeFontCard(title: "Font files") {
            if let first = attachedFontAssets.first.flatMap({ fontMetadata(for: $0) }),
               attachedFontAssets.contains(where: { asset in
                   fontMetadata(for: asset).map { !$0.belongsToSameFamily(as: first) } ?? false
               }) {
                Label("These files contain different families. Remove the unrelated files and give each family its own Custom Font.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("\(files.count) file\(files.count == 1 ? "" : "s") selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Add Files…") {
                    Button("From Finder…") { isImportingFonts = true }
                    let available = fontAssets.filter { asset in !files.contains { $0.foundryAssetID == asset.id } }
                    if !available.isEmpty {
                        Divider()
                        Section("Project Resources") {
                            ForEach(available) { asset in
                                Button(asset.filename) { addFontResource(asset, reference: selection) }
                            }
                        }
                    }
                }
            }

            if files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "textformat")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Add a font file").font(.headline)
                    Text("Import a font, or drag one here from Finder or Project Resources.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(attachedFontAssets) { asset in
                        HStack {
                            Button { previewFontAssetID = asset.id } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fontMetadata(for: asset)?.family ?? asset.filename).lineLimit(2)
                                Text(fontMetadata(for: asset)?.summary ?? "Unreadable font file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(asset.filename).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Preview this font file")
                            Button("Remove File", systemImage: "minus.circle") {
                                editor.setThemeFontResources(files.filter { $0.foundryAssetID != asset.id }, reference: selection)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Detach this file without deleting the project resource")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        if asset.id != attachedFontAssets.last?.id { Divider() }
                    }
                    ForEach(missingFiles(in: files), id: \.self) { missingFile in
                        HStack {
                            Label("Missing font file", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove") {
                                editor.setThemeFontResources(files.filter { $0 != missingFile }, reference: selection)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }

            Text("Supported formats: OTF, TTF, WOFF and WOFF2.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isFontDropTargeted, perform: acceptFontProviders)
        .overlay {
            if isFontDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var projectFontDetailsCard: some View {
        ThemeFontCard {
            if let asset = attachedFontAssets.first(where: { $0.id == previewFontAssetID }) ?? attachedFontAssets.first,
               let content = session.document.assetContents[asset.id] {
                GoogleFontSpecimenView(
                    family: fontMetadata(for: asset)?.family ?? asset.filename,
                    stylesheetURL: nil,
                    fontContent: content
                )
                .frame(height: 240)
                .id(asset.id)
            } else {
                Text("Add a font file to preview it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var attachedFontAssets: [ProjectAsset] {
        let files = bundledFiles(for: selection)
        return fontAssets.filter { asset in files.contains { $0.foundryAssetID == asset.id } }
    }

    private func fontMetadata(for asset: ProjectAsset) -> FontFileMetadata? {
        session.document.assetContents[asset.id].flatMap { FontFileMetadata.read($0) }
    }

    private func validateFontData(_ data: Data, reference: ThemeFontReference) -> FontFileMetadata? {
        guard let metadata = FontFileMetadata.read(data) else {
            fontImportError = "Couldn’t read this as a supported font. Choose a TTF, OTF, WOFF or WOFF2 file containing one font family. Variable fonts are supported; font collections are not."
            return nil
        }
        for file in bundledFiles(for: reference) {
            guard let id = file.foundryAssetID, let content = session.document.assetContents[id],
                  let existing = FontFileMetadata.read(content) else {
                fontImportError = "Remove the missing or unreadable font file before adding another face."
                return nil
            }
            guard metadata.belongsToSameFamily(as: existing) else {
                fontImportError = "This entry uses \(existing.family). \(metadata.family) is a different family—add a separate Custom Font for it. Only weights and styles of the same family belong together."
                return nil
            }
        }
        return metadata
    }

    private var fontAssets: [ProjectAsset] {
        assets.filter(Self.isFontResource)
            .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    private var storedDefinition: ThemeFontDefinition {
        switch selection {
        case .role(.body): theme.typography.bodyFont
        case .role(.heading): theme.typography.headingFont
        case .role(.monospaced): theme.typography.monospacedFont
        case .custom(let id):
            theme.typography.customFonts.first { $0.id == id }?.font
                ?? .system(family: "system-ui", weights: [400])
        }
    }

    private var sidebarSelectionBinding: Binding<ThemeFontReference?> {
        Binding(get: { selection }, set: { if let reference = $0 { selectFont(reference) } })
    }

    private func selectFont(_ reference: ThemeFontReference) {
        session.discardFontPreview()
        selection = reference
    }

    private var googleFamilyBinding: Binding<String?> {
        Binding(
            get: { definition.family },
            set: { family in
                guard let family, family != definition.family else { return }
                guard let metadata = googleFonts.first(where: { $0.family == family }), !metadata.faces.isEmpty else { return }
                editor.setThemeGoogleFont(family, reference: selection, configuration: .init(available: metadata.faces, included: metadata.faces))
            }
        )
    }

    private var fontNamesBinding: Binding<String> {
        Binding(get: { definition.cssFamily }, set: { editor.setThemeFontNames($0, reference: selection) })
    }

    private func customNameBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { theme.typography.customFonts.first { $0.id == id }?.name ?? "" },
            set: { editor.setThemeCustomFontName(id: id, value: $0) }
        )
    }

    private var sourceKindBinding: Binding<ThemeFontSourceChoice> {
        Binding(
            get: { ThemeFontSourceChoice(definition.source) },
            set: { source in
                guard source != ThemeFontSourceChoice(definition.source) else { return }
                session.discardFontPreview()
                switch source {
                case .system:
                    editor.restoreThemeFontNames(reference: selection)
                case .project:
                    editor.setThemeFontSource(.bundled(files: []), reference: selection)
                case .google:
                    let family = googleFonts.first { $0.family == "ABeeZee" && !$0.faces.isEmpty } ?? GoogleFontsService.fallback[0]
                    editor.setThemeGoogleFont(family.family, reference: selection,
                        configuration: .init(available: family.faces, included: family.faces))
                }
            }
        )
    }

    private var fontReplacementChoices: [BlockPropertyChoice] {
        let pendingReference = fontPendingDeletion.map { "custom:\($0.id.uuidString.lowercased())" }
        return theme.fontFamilyChoices.filter { $0.value != pendingReference }
    }

    private var fontDeletionPresented: Binding<Bool> {
        Binding(get: { fontPendingDeletion != nil }, set: { if !$0 { fontPendingDeletion = nil } })
    }

    private var fontImportErrorPresented: Binding<Bool> {
        Binding(get: { fontImportError != nil }, set: { if !$0 { fontImportError = nil } })
    }

    private var googleStylesheetURL: URL? {
        guard case .remote(let url) = definition.source else { return nil }
        return url
    }

    private var googleCatalogueTaskID: String {
        "\(ThemeFontSourceChoice(definition.source).rawValue)-\(googleFontsReloadID)"
    }

    private var filteredGoogleFonts: [GoogleFontFamily] {
        googleFonts.filter {
            (search.isEmpty || $0.family.localizedCaseInsensitiveContains(search)) && category.includes($0.category)
        }
    }

    private func loadGoogleFonts() async {
        isLoadingGoogleFonts = true
        googleFontsError = nil
        defer { isLoadingGoogleFonts = false }
        do {
            googleFonts = try await GoogleFontsService.shared.families()
        } catch is CancellationError {
            return
        } catch {
            googleFontsError = "The complete catalogue is unavailable. Showing a limited offline list."
        }
    }

    private func systemPreviewFont(size: CGFloat) -> Font {
        for name in [definition.family] + definition.fallbacks {
            let family = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            switch family.lowercased() {
            case "monospace", "ui-monospace": return .system(size: size, design: .monospaced)
            case "serif", "ui-serif": return .system(size: size, design: .serif)
            case "system-ui", "sans-serif", "-apple-system", "blinkmacsystemfont": return .system(size: size)
            case "ui-rounded": return .system(size: size, design: .rounded)
            default:
                if NSFont(name: family, size: size) != nil { return .custom(family, size: size) }
            }
        }
        return .system(size: size)
    }

    private func missingFiles(in files: [String]) -> [String] {
        files.filter { file in !assets.contains { $0.id == file.foundryAssetID } }
    }

    private func bundledFiles(for reference: ThemeFontReference) -> [String] {
        guard case .bundled(let files) = session.font(for: reference).source else { return [] }
        return files
    }

    private func addFontResource(_ asset: ProjectAsset, reference: ThemeFontReference) {
        guard canAttachFontResource(to: reference), Self.isFontResource(asset) else { return }
        let files = bundledFiles(for: reference)
        guard !files.contains(where: { $0.foundryAssetID == asset.id }) else { return }
        guard let content = session.document.assetContents[asset.id],
              validateFontData(content.data, reference: reference) != nil else { return }
        editor.setThemeFontResources(files + [asset.reference], reference: reference)
    }

    private func importFontURL(_ url: URL, reference: ThemeFontReference) {
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            importFontData(data, filename: url.lastPathComponent, reference: reference)
        } catch {
            fontImportError = error.localizedDescription
        }
    }

    private func importFontData(_ data: Data, filename: String, reference: ThemeFontReference) {
        guard canAttachFontResource(to: reference) else { return }
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        guard Self.fontExtensions.contains(pathExtension) else { return }
        guard validateFontData(data, reference: reference) != nil else { return }
        let undoManager = editor.undoManager
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("Import Font Resources")
        }
        let type = UTType(filenameExtension: pathExtension)
        let id = session.document.importAsset(
            data: data,
            filename: filename,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            undoManager: undoManager
        )
        let files = bundledFiles(for: reference)
        editor.setThemeFontResources(files + ["foundry-asset:\(id.uuidString)"], reference: reference)
    }

    private func acceptFontProviders(_ providers: [NSItemProvider]) -> Bool {
        guard canEditSelection else { return false }
        let targetReference = selection
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let scopedAccess = url.startAccessingSecurityScopedResource()
                    defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return }
                    let filename = Self.preferredFilename(provider.suggestedName, sourceURL: url)
                    Task { @MainActor in
                        importFontData(data, filename: filename, reference: targetReference)
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value, let id = Self.assetID(from: value) else { return }
                    Task { @MainActor in
                        guard let asset = session.document.site.assets.first(where: { $0.id == id }) else { return }
                        addFontResource(asset, reference: targetReference)
                    }
                }
            }
        }
        return accepted
    }

    private func canAttachFontResource(to reference: ThemeFontReference) -> Bool {
        guard case .bundled = session.font(for: reference).source else { return false }
        guard case .custom(let id) = reference else { return session.canEditTheme }
        return session.document.site.theme.typography.customFonts.contains { $0.id == id }
    }

    nonisolated private static let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]
    private static var fontContentTypes: [UTType] {
        [.font] + fontExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    nonisolated private static func isFontResource(_ asset: ProjectAsset) -> Bool {
        fontExtensions.contains((asset.filename as NSString).pathExtension.lowercased()) ||
            asset.mediaType.lowercased().contains("font")
    }

    nonisolated private static func preferredFilename(_ suggestedName: String?, sourceURL: URL) -> String {
        guard let suggestedName, !suggestedName.isEmpty else { return sourceURL.lastPathComponent }
        if !(suggestedName as NSString).pathExtension.isEmpty { return suggestedName }
        return sourceURL.pathExtension.isEmpty ? suggestedName : "\(suggestedName).\(sourceURL.pathExtension)"
    }

    nonisolated private static func assetID(from value: String) -> UUID? {
        if let id = value.foundryAssetID { return id }
        let prefixes = ["foundry-asset-node:", "foundry-image-asset:"]
        guard let prefix = prefixes.first(where: value.hasPrefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}

private enum ThemeFontSourceChoice: String, CaseIterable, Identifiable {
    case system, google, project
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .google: "Google Fonts"
        case .project: "Project Files"
        }
    }

    init(_ source: ThemeFontSource) {
        switch source {
        case .system: self = .system
        case .remote: self = .google
        case .bundled: self = .project
        }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    private var editor: ProjectEditor { session.editor }
    private var definition: ThemeFontDefinition { session.font(for: selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            assignmentCard

            ThemeEditorColumns {
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
        }
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
            Text("Foundry will update every component using this font before deleting it.")
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
        ThemeEditorCard(title: "Font assignment", subtitle: "Choose a theme font to edit, or add a reusable font of your own.") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    fontPicker
                    Spacer(minLength: 12)
                    customFontActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    fontPicker
                    customFontActions
                }
            }

            if case .custom(let id) = selection {
                ThemeEditorPropertyRow(title: "Name") {
                    TextField("Custom font name", text: customNameBinding(id: id))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
            }

            Divider()

            ThemeEditorPropertyRow(title: "Source") {
                Picker("Font source", selection: sourceKindBinding) {
                    ForEach(ThemeFontSourceChoice.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        }
    }

    private var fontPicker: some View {
        ThemeEditorPropertyRow(title: "Font") {
            Picker("Font", selection: selectionBinding) {
                Section("Theme Fonts") {
                    ForEach(ThemeFontRole.allCases) { role in
                        Text(role.title).tag(ThemeFontReference.role(role))
                    }
                }
                if !theme.typography.customFonts.isEmpty {
                    Section("Custom Fonts") {
                        ForEach(theme.typography.customFonts) { font in
                            Text(font.name.isEmpty ? "Untitled Font" : font.name)
                                .tag(ThemeFontReference.custom(font.id))
                        }
                    }
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var customFontActions: some View {
        HStack(spacing: 8) {
            Button("Add Font", systemImage: "plus") {
                session.discardFontPreview()
                selection = .custom(editor.addThemeCustomFont())
            }
            if case .custom(let id) = selection {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    fontPendingDeletion = theme.typography.customFonts.first { $0.id == id }
                }
            }
        }
        .fixedSize()
    }

    private var systemFontCard: some View {
        ThemeEditorCard(title: "System font", subtitle: "Use fonts already available on your visitor’s device.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Font names").font(.subheadline.weight(.medium))
                TextField("system-ui, sans-serif", text: fontNamesBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Font names, in order of preference")
                Text("Separate names with commas. The browser uses the first available font.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var systemPreviewCard: some View {
        ThemeEditorCard(title: "Preview", subtitle: "Appearance on this Mac") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Aa Bb Cc").font(systemPreviewFont(size: 38))
                Text("Good typography brings your words to life.")
                    .font(systemPreviewFont(size: 19))
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789")
                    .font(systemPreviewFont(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private var googleFontCard: some View {
        ThemeEditorCard(title: "Google Fonts", subtitle: "Select a font to preview it, then choose Use Font to apply it.") {
            TextField("Search font families", text: $search)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let family = filteredGoogleFonts.first?.family {
                        session.previewGoogleFont(family, for: selection)
                    }
                }
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
                .accessibilityElement(children: .combine)
            }
            .listStyle(.inset)
            .frame(height: 300)
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
        ThemeEditorCard(title: "Preview", subtitle: definition.family) {
            GoogleFontSpecimenView(family: definition.family, stylesheetURL: googleStylesheetURL)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("Cancel") { session.discardFontPreview() }
                    .disabled(!session.hasUncommittedFontPreview)
                Spacer(minLength: 8)
                Button("Use Font") { session.commitFontPreview() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.hasUncommittedFontPreview)
            }
        }
    }

    private func projectFontCard(files: [String]) -> some View {
        ThemeEditorCard(title: "Project font files", subtitle: "Choose the font files to include when this font is used.") {
            HStack {
                Text("\(files.count) file\(files.count == 1 ? "" : "s") selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import…", systemImage: "square.and.arrow.down") {
                    isImportingFonts = true
                }
            }

            if fontAssets.isEmpty && files.isEmpty {
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
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(fontAssets) { asset in
                        Toggle(isOn: resourceMembershipBinding(asset: asset)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(asset.filename).lineLimit(2)
                                Text((asset.filename as NSString).pathExtension.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        if asset.id != fontAssets.last?.id { Divider() }
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
        ThemeEditorCard(title: "Font family", subtitle: "The name used for these files in your website.") {
            Text(definition.family)
                .font(.title3.weight(.medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("The first file you add supplies the family name. Include the files needed for the styles and weights you use.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var selectionBinding: Binding<ThemeFontReference> {
        Binding(get: { selection }, set: selectFont)
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
                session.previewGoogleFont(family, for: selection)
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
                    editor.setThemeGoogleFont(GoogleFontsService.fallback.first?.family ?? "ABeeZee", reference: selection)
                }
            }
        )
    }

    private var fontReplacementChoices: [ComponentPropertyChoice] {
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

    private func resourceMembershipBinding(asset: ProjectAsset) -> Binding<Bool> {
        Binding(
            get: { bundledFiles(for: selection).contains { $0.foundryAssetID == asset.id } },
            set: { included in
                let files = bundledFiles(for: selection)
                if included {
                    addFontResource(asset, reference: selection)
                } else {
                    editor.setThemeFontResources(files.filter { $0.foundryAssetID != asset.id }, reference: selection)
                }
            }
        )
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
        editor.setThemeFontResources(files + [asset.reference], reference: reference)
        if files.isEmpty {
            editor.setThemeFontFamily((asset.filename as NSString).deletingPathExtension, reference: reference)
        }
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
        if files.isEmpty {
            editor.setThemeFontFamily((filename as NSString).deletingPathExtension, reference: reference)
        }
    }

    private func acceptFontProviders(_ providers: [NSItemProvider]) -> Bool {
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
        guard case .custom(let id) = reference else { return true }
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

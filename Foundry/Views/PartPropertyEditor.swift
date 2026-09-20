import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PartPropertyEditor: View {
    @Environment(\.canvasAppearance) private var appearance
    @State private var videoPosterTask: Task<Void, Never>?
    @State private var generatedVideoPoster: NSImage?
    @State private var isAnalysingVideo = false
    @State private var videoAnalysisError: String?
    @Namespace private var themeSpacingFocusNamespace
    let definition: PartPropertyDefinition
    let part: PartNode
    let selectedParts: [PartNode]
    let currentPage: Page?
    let theme: Theme
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?

    init(
        definition: PartPropertyDefinition,
        part: PartNode,
        selectedParts: [PartNode],
        currentPage: Page?,
        theme: Theme,
        assets: [ProjectAsset],
        assetContents: ProjectAssetContents,
        pages: [Page],
        folders: [PageFolder],
        publicURL: String,
        editor: ProjectEditor,
        editsSharedDefinition: Bool,
        breakpoint: ResponsiveBreakpoint,
        importMedia: @escaping (URL, UTType) -> ProjectAsset?
    ) {
        self.definition = definition
        self.part = part
        self.selectedParts = selectedParts
        self.currentPage = currentPage
        self.theme = theme
        self.assets = assets
        self.assetContents = assetContents
        self.pages = pages
        self.folders = folders
        self.publicURL = publicURL
        self.editor = editor
        self.editsSharedDefinition = editsSharedDefinition
        self.breakpoint = breakpoint
        self.importMedia = importMedia
    }

    @ViewBuilder
    var body: some View {
        if let subtitle = definition.subtitle,
           !subtitle.isEmpty,
           !definition.control.isArray,
           !isDateControl,
           !isNoteControl,
           !isLinkControl {
            VStack(alignment: .leading, spacing: 4) {
                editorControl
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            editorControl
        }
    }

    private var isDateControl: Bool {
        if case .date = definition.control { return true }
        return false
    }

    private var isNoteControl: Bool {
        if case .note = definition.control { return true }
        return false
    }

    private var isLinkControl: Bool {
        if case .link = definition.control { return true }
        return false
    }

    @ViewBuilder
    private var editorControl: some View {
        switch definition.control {
        case .array(let element, let count, let subtitles, let buttonTexts, let buttonIcons, let activeButtonTexts, let activeButtonIcons, let buttonSelectionMode, let units, let help):
            if case .slider = element {
                controlArrayRow(element: element, count: count, subtitles: subtitles, buttonTexts: buttonTexts, buttonIcons: buttonIcons, activeButtonTexts: activeButtonTexts, activeButtonIcons: activeButtonIcons, buttonSelectionMode: buttonSelectionMode, units: units, help: help)
                    .contextMenu {
                        resetButton
                    }
            } else {
                controlArrayRow(element: element, count: count, subtitles: subtitles, buttonTexts: buttonTexts, buttonIcons: buttonIcons, activeButtonTexts: activeButtonTexts, activeButtonIcons: activeButtonIcons, buttonSelectionMode: buttonSelectionMode, units: units, help: help)
            }
        case .singleLineText:
            TextPartControl(label: definition.label, indicator: responsiveIndicator, text: stringBinding(as: .string))
        case .multilineText:
            TextAreaPartControl(label: definition.label, indicator: responsiveIndicator, text: stringBinding(as: .string))
        case .link(let absoluteURL):
            LinkPartControl(
                label: definition.label,
                subtitle: definition.subtitle,
                currentLink: currentLink,
                summary: linkSummary,
                indicator: responsiveIndicator,
                pages: pages,
                folders: folders,
                assets: assets,
                assetLibrary: editor.document.site.assetLibrary,
                anchorsForPage: { page in
                    let site = editor.document.site
                    let renderedPage: Page
                    if let currentPage, currentPage.id == page.id {
                        renderedPage = currentPage
                    } else {
                        renderedPage = site.pages.first { $0.id == page.id } ?? page
                    }
                    return Self.anchorIDs(
                        in: HTMLPageRenderer(site: site).render(
                            page: renderedPage,
                            theme: theme,
                            assets: assetContents
                        )
                    )
                },
                publicURL: publicURL,
                absoluteURL: absoluteURL,
                update: { setProperty(.link($0)) }
            )
        case .number(let range, let step, let unit):
            Group {
                NumberPartControl(
                    label: definition.label,
                    range: range,
                    step: step,
                    unit: unit,
                    indicator: responsiveIndicator,
                    value: numberBinding
                )
            }
        case .slider(let range, let step, let ticks, let unit, let showsValueField):
            SliderPartControl(
                label: definition.label,
                range: range,
                step: step,
                ticks: ticks,
                unit: unit,
                showsValueField: showsValueField,
                indicator: responsiveIndicator,
                value: numberBinding
            )
            .contextMenu {
                resetButton
            }
        case .date:
            DatePartControl(
                label: definition.label,
                subtitle: definition.subtitle,
                minimum: definition.dateMinimum,
                maximum: definition.dateMaximum,
                indicator: responsiveIndicator,
                value: dateBinding
            )
        case .note(let systemImage):
            NotePartControl(
                title: definition.label.isEmpty ? nil : definition.label,
                text: definition.subtitle ?? "",
                systemImage: systemImage
            )
        case .button(let icon, let text, let activeIcon, let activeText):
            ButtonPartControl(
                label: definition.label,
                buttonText: text,
                systemImage: icon,
                activeButtonText: activeText,
                activeSystemImage: activeIcon,
                indicator: responsiveIndicator,
                isActive: booleanBinding
            )
        case .derived:
            EmptyView()
        case .color:
            BasicColorPartControl(
                label: definition.label,
                selectedToken: selectedToken,
                indicator: responsiveIndicator,
                color: colorBinding
            ) {
                tokenPicker(tokens: DesignToken.colorTokens, customLabel: "Custom colour")
            }
        case .colorWithOpacity:
            InspectorRow(title: definition.label, alignment: .center, indicator: responsiveIndicator) {
                InspectorColorWell(color: colorBinding, supportsAlpha: true)
            }
        case .literalColor(let allowsOpacity):
            ColorPartControl(
                label: definition.label,
                allowsOpacity: allowsOpacity,
                indicator: responsiveIndicator,
                color: colorBinding
            )
        case .icon:
            IconPartControl(label: definition.label, indicator: responsiveIndicator, selection: stringBinding(as: .choice))
        case .packageColor(let themeValues, let opacity, _, _):
            ThemeColorPartControl(
                label: definition.label,
                choices: themeValues ? theme.colorChoices : [],
                allowsCustom: definition.allowsCustomThemeValue,
                theme: theme,
                source: packageColorSourceBinding,
                shade: packageColorShadeBinding,
                customColor: packageCustomColorBinding,
                allowsOpacity: opacity,
                indicator: responsiveIndicator
            )
        case .choice(let choices):
            if definition.selectPresentation == .segmented {
                InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                    InspectorSegmentedControl(
                        selection: stringBinding(as: .choice),
                        segments: segmentedOptions(for: choices)
                    )
                }
            } else {
                SelectPartControl(
                    label: definition.label,
                    options: choices.map {
                        .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                    },
                    indicator: responsiveIndicator,
                    selection: stringBinding(as: .choice)
                )
            }
        case .themeFont:
            ThemeFontPartControl(label: definition.label, theme: theme, indicator: responsiveIndicator, selection: stringBinding(as: .choice))
        case .themeSpacing:
            InspectorRow(title: definition.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Spacing" : definition.label, indicator: responsiveIndicator) {
                ThemeSpacingInput<PaddingPolicy>(binding: Binding(get: {
                    if case .themeSpacing(let value) = displayPart.propertyValue(definition.key) { return value.selection }
                    if case .themeSpacing(let value) = definition.defaultValue { return value.selection }
                    return ThemePaddingValue.EdgeValue()
                }, set: { setProperty(.themeSpacing(.init(selection: $0))) }), title: definition.label.isEmpty ? "Spacing" : definition.label, theme: theme, focusNamespace: themeSpacingFocusNamespace)
            }
            .focusScope(themeSpacingFocusNamespace)
            .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Spacing")
            .contextMenu { resetButton }
        case .themeBorderWidth:
            ThemeBorderWidthPartControl(label: definition.label, theme: theme, indicator: responsiveIndicator,
                value: Binding(get: {
                    if case .themeBorderWidth(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .themeBorderWidth(let value) = definition.defaultValue { return value }
                    return ThemeBorderWidthValue()
                }, set: { setProperty(.themeBorderWidth($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == (definition.inspectorControlID ?? definition.key.rawValue) }?.tooltip ?? "Border")
                .contextMenu { resetButton }
        case .themeRadius:
            ThemeRadiusPartControl(label: definition.label, theme: theme, indicator: responsiveIndicator,
                value: Binding(get: {
                    if case .themeRadius(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .themeRadius(let value) = definition.defaultValue { return value }
                    return ThemeRadiusValue()
                }, set: { setProperty(.themeRadius($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Radius")
                .contextMenu { resetButton }
        case .themeMargin:
            ThemeMarginPartControl(label: definition.label, theme: theme, indicator: responsiveIndicator,
                value: Binding(get: {
                    if case .themeMargin(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .themeMargin(let value) = definition.defaultValue { return value }
                    return ThemeMarginValue()
                }, set: { setProperty(.themeMargin($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Margin")
                .contextMenu { resetButton }
        case .themePadding:
            ThemePaddingPartControl(label: definition.label, theme: theme, indicator: responsiveIndicator,
                value: Binding(get: {
                    if case .themePadding(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .themePadding(let value) = definition.defaultValue { return value }
                    return ThemePaddingValue()
                }, set: { setProperty(.themePadding($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Padding")
                .contextMenu { resetButton }
        case .fontWeight(let font):
            FontFacePartControl(label: definition.label,
                options: fontFaceOptions(font: font, editsWeight: true),
                indicator: responsiveIndicator, weight: numberBinding, style: .constant("normal"), editsWeight: true)
        case .fontStyle(let font):
            FontFacePartControl(label: definition.label,
                options: fontFaceOptions(font: font, editsWeight: false),
                indicator: responsiveIndicator, weight: .constant(400), style: stringBinding(as: .choice), editsWeight: false)
        case .themeFontSize:
            SelectPartControl(
                label: definition.label,
                options: theme.fontSizeChoices.map { .init(title: $0.label, value: $0.value) },
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .packageShadow:
            ShadowPartControl(
                label: definition.label,
                choices: theme.shadowChoices,
                source: packageShadowSourceBinding,
                customLayers: packageShadowLayersBinding,
                indicator: responsiveIndicator
            )
        case .textAlignment:
            TextAlignmentPartControl(
                label: definition.label,
                segments: alignmentSegments,
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .divider:
            DividerPartControl()
        case .toggle:
            TogglePartControl(label: definition.label, indicator: responsiveIndicator, isOn: booleanBinding)
        case .image:
            ImagePartControl(
                label: definition.label,
                previewImage: previewImage,
                supportsFocalPoint: definition.supportsImageFocalPoint,
                focalPoint: imageFocalPoint,
                focalPointIndicator: imageFocalPointResponsiveIndicator,
                isClearDisabled: displayPart.propertyValue(definition.key) == definition.defaultValue,
                altText: imageAltBinding,
                chooseImage: chooseImageFromFinder,
                clearImage: { setProperty(definition.defaultValue) },
                importImage: { url in
                    guard let asset = importMedia(url, .image) else { return false }
                    setProperty(.url(asset.reference))
                    return true
                },
                setFocalPoint: setImageFocalPoint
            )
        case .video:
            VideoPartControl(
                label: definition.label,
                filename: selectedVideoFilename,
                posterImage: selectedVideoPoster,
                hasCustomPoster: !displayPart.property(videoPosterKey).isEmpty,
                details: selectedVideoDetails,
                compatibilityWarning: selectedVideoCompatibilityWarning,
                isProcessing: isAnalysingVideo,
                errorMessage: videoAnalysisError,
                choices: availableVideos.map { .init(id: $0.id, title: $0.filename) },
                indicator: responsiveIndicator,
                showsPlaybackOptions: showsVideoPlaybackOptions,
                autoplay: videoAutoplayBinding,
                muted: videoBooleanBinding(videoMutedKey, fallback: false),
                showsControls: videoBooleanBinding(videoControlsKey, fallback: true),
                loops: videoBooleanBinding(videoLoopKey, fallback: false),
                startAt: videoStartAtBinding,
                isClearDisabled: displayPart.propertyValue(definition.key) == definition.defaultValue,
                importVideoFromMac: chooseVideoFromFinder,
                selectVideo: selectExistingVideo,
                clearVideo: clearVideo,
                importVideo: { url in
                    guard let asset = importMedia(url, .movie) else { return false }
                    selectVideo(asset)
                    return true
                },
                choosePoster: chooseVideoPosterFromFinder,
                clearPoster: { setProperty(.url(""), key: videoPosterKey) }
            )
            .task(id: selectedAsset?.id) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                videoPosterTask?.cancel()
                isAnalysingVideo = false
                generatedVideoPoster = nil
                videoAnalysisError = nil
                if let asset = selectedAsset { analyseVideoIfNeeded(asset) }
            }
            .onDisappear { videoPosterTask?.cancel() }
        }
    }

    private static func anchorIDs(in html: String) -> [String] {
        PartAnchorDiscovery.identifiers(in: html)
    }

    private var previewImage: NSImage? {
        let source = displayPart.property(definition.key)
        if let id = source.foundryAssetID,
           let data = assetContents[id]?.data {
            return NSImage(data: data)
        }
        guard !source.isEmpty,
              let package = part.type.definition.package,
              package.manifest.assetDeclaration(containing: source) != nil else { return nil }
        return NSImage(contentsOf: package.resourceRootURL.appending(path: source))
    }

    private var selectedAsset: ProjectAsset? {
        guard let id = displayPart.property(definition.key).foundryAssetID else { return nil }
        return assets.first { $0.id == id }
    }

    private var selectedVideoFilename: String? {
        if let filename = selectedAsset?.filename { return filename }
        let source = displayPart.property(definition.key)
        guard !source.isEmpty else { return nil }
        return (source as NSString).lastPathComponent
    }

    private var selectedVideoPoster: NSImage? {
        let source = displayPart.property(videoPosterKey)
        if let id = source.foundryAssetID,
           let data = assetContents[id]?.data,
           let image = NSImage(data: data) {
            return image
        }
        return generatedVideoPoster ?? selectedAsset?.videoMetadata.flatMap { NSImage(data: $0.posterJPEG) }
    }

    private var videoPosterKey: PartProperty.Key {
        PartVideoTemplateValues.posterPropertyKey(for: definition.key.rawValue)
    }

    private var showsVideoPlaybackOptions: Bool {
        guard let package = part.type.definition.package else { return true }
        return !package.manifest.controlGroups
            .flatMap(\.properties)
            .contains { $0.id == definition.key.rawValue && $0.control.type == .video }
    }

    private var videoAutoplayKey: PartProperty.Key {
        PartVideoTemplateValues.autoplayPropertyKey(for: definition.key.rawValue)
    }

    private var videoMutedKey: PartProperty.Key {
        PartVideoTemplateValues.mutedPropertyKey(for: definition.key.rawValue)
    }

    private var videoControlsKey: PartProperty.Key {
        PartVideoTemplateValues.controlsPropertyKey(for: definition.key.rawValue)
    }

    private var videoLoopKey: PartProperty.Key {
        PartVideoTemplateValues.loopPropertyKey(for: definition.key.rawValue)
    }

    private var videoStartAtKey: PartProperty.Key {
        PartVideoTemplateValues.startAtPropertyKey(for: definition.key.rawValue)
    }

    private var videoAutoplayBinding: Binding<String> {
        Binding(
            get: { displayPart.property(videoAutoplayKey) == "onLoad" ? "onLoad" : "never" },
            set: { setProperty(.choice($0), key: videoAutoplayKey) }
        )
    }

    private func videoBooleanBinding(_ key: PartProperty.Key, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { displayPart.propertyValue(key).booleanValue ?? fallback },
            set: { setProperty(.boolean($0), key: key) }
        )
    }

    private var videoStartAtBinding: Binding<Double> {
        Binding(
            get: { max(displayPart.propertyValue(videoStartAtKey).numberValue ?? 0, 0) },
            set: { setProperty(.number(max($0, 0)), key: videoStartAtKey) }
        )
    }

    private var selectedVideoDetails: String? {
        guard let asset = selectedAsset else { return nil }
        var components: [String] = []
        if let width = asset.pixelWidth, let height = asset.pixelHeight {
            components.append("\(width) × \(height)")
        }
        if let duration = asset.videoMetadata?.duration {
            let seconds = max(Int(duration.rounded()), 0)
            components.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        components.append(asset.byteCount.formatted(.byteCount(style: .file)))
        return components.joined(separator: " · ")
    }

    private var selectedVideoCompatibilityWarning: String? {
        guard let asset = selectedAsset else { return nil }
        let ext = (asset.filename as NSString).pathExtension.lowercased()
        guard ["mp4", "m4v", "webm"].contains(ext) else {
            return "This format may not play in every browser"
        }
        return nil
    }

    private var availableVideos: [ProjectAsset] {
        assets.filter { asset in
            UTType(mimeType: asset.mediaType)?.conforms(to: .movie) == true
                || asset.mediaType.hasPrefix("video/")
        }
        .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    private var imageFocalPoint: CGPoint {
        let point = PartImageTemplateValues.focalPoint(
            from: part.propertyValue(imageFocalPointKey, at: effectiveBreakpoint(for: imageFocalPointKey), screens: theme.screens)
        )
        return CGPoint(x: point.x / 100, y: point.y / 100)
    }

    private func setImageFocalPoint(_ point: CGPoint) {
        setProperty(
            .array([
                .number(min(max(point.x * 100, 0), 100)),
                .number(min(max(point.y * 100, 0), 100))
            ]),
            key: imageFocalPointKey
        )
    }

    private var imageFocalPointKey: PartProperty.Key {
        PartPackageAdapter.imageFocalPointKey(for: definition.key.rawValue)
    }

    private var imageAltKey: PartProperty.Key {
        PartPackageAdapter.imageAltKey(for: definition.key.rawValue)
    }

    private var imageAltBinding: Binding<String> {
        Binding(
            get: { displayPart.property(imageAltKey) },
            set: { setProperty(.string($0), key: imageAltKey) }
        )
    }

    private func chooseImageFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let asset = importMedia(url, .image) else { return }
        setProperty(.url(asset.reference))
    }

    private func chooseVideoFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Video"
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let asset = importMedia(url, .movie) else { return }
        selectVideo(asset)
    }

    private func chooseVideoPosterFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Poster Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importVideoPoster(url)
    }

    private func importVideoPoster(_ url: URL) -> Bool {
        guard let asset = importMedia(url, .image) else { return false }
        setProperty(.url(asset.reference), key: videoPosterKey)
        return true
    }

    private func selectExistingVideo(_ id: UUID) {
        guard let asset = assets.first(where: { $0.id == id }) else { return }
        selectVideo(asset)
    }

    private func selectVideo(_ asset: ProjectAsset) {
        videoPosterTask?.cancel()
        generatedVideoPoster = nil
        videoAnalysisError = nil
        let wasAlreadySelected = selectedAsset?.id == asset.id
        setProperty(.url(asset.reference))
        if wasAlreadySelected { analyseVideoIfNeeded(asset) }
    }

    private func analyseVideoIfNeeded(_ asset: ProjectAsset) {
        guard asset.videoMetadata == nil else {
            isAnalysingVideo = false
            return
        }
        guard let data = editor.document.assetContents[asset.id]?.data else {
            isAnalysingVideo = false
            videoAnalysisError = "Video data is unavailable"
            return
        }
        isAnalysingVideo = true
        videoPosterTask = Task {
            let result = await VideoPosterGenerator.metadata(for: data, filename: asset.filename)
            guard !Task.isCancelled else { return }
            isAnalysingVideo = false
            guard let result else {
                videoAnalysisError = "Couldn’t read this video"
                return
            }
            generatedVideoPoster = NSImage(data: result.metadata.posterJPEG)
            editor.document.setVideoMetadata(id: asset.id, result: result)
        }
    }

    private func clearVideo() {
        videoPosterTask?.cancel()
        generatedVideoPoster = nil
        isAnalysingVideo = false
        videoAnalysisError = nil
        setProperty(.url(""), key: videoPosterKey)
        setProperty(definition.defaultValue)
    }

    private var assetBinding: Binding<UUID?> {
        Binding(
            get: { displayPart.property(definition.key).foundryAssetID },
            set: { id in
                let reference = id.flatMap { selectedID in
                    assets.first(where: { $0.id == selectedID })?.reference
                } ?? ""
                setProperty(.url(reference))
            }
        )
    }

    private func stringBinding(as kind: StringValueKind) -> Binding<String> {
        Binding(
            get: { displayPart.property(definition.key) },
            set: { setProperty(kind.value($0)) }
        )
    }

    private func fontFaceOptions(font: String?, editsWeight: Bool) -> FontFaceOptions {
        let companions = displayPart.type.definition.properties.filter { property in
            guard let font else { return false }
            switch property.control {
            case .fontStyle(let linked): return editsWeight && linked == font
            case .fontWeight(let linked): return !editsWeight && linked == font
            default: return false
            }
        }
        let companion = companions.count == 1 ? companions.first.map { displayPart.propertyValue($0.key) } : nil
        return FontFaceOptions(
            reference: font.map { PartPackageFontControl.familyReference($0, node: displayPart) },
            theme: theme, assets: assetContents,
            selectedWeight: editsWeight ? nil : companion?.numberValue.map(Int.init),
            selectedStyle: editsWeight ? companion?.stringValue : nil)
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { displayPart.numberProperty(definition.key, theme: theme) },
            set: { setProperty(.number($0)) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: displayPart.colorProperty(definition.key, theme: theme)) ?? .white },
            set: {
                setProperty(.color(
                    definition.control.allowsLiteralColorOpacity
                        ? ($0.hexStringWithAlpha ?? "#FFFFFFFF")
                        : ($0.hexString ?? "#FFFFFF")
                ))
            }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { displayPart.propertyValue(definition.key).booleanValue ?? false },
            set: { setProperty(.boolean($0)) }
        )
    }

    private var currentLink: PartLink {
        guard case .link(let link) = displayPart.propertyValue(definition.key) else { return .init() }
        return link
    }

    private var linkSummary: String {
        switch currentLink.destination {
        case .none: "Choose Link…"
        case .url(let value), .plainText(let value): value.isEmpty ? "Choose Link…" : value
        case .page(let id): pages.first(where: { $0.id == id })?.title ?? "Missing Page"
        case .resource(let id): assets.first(where: { $0.id == id })?.filename ?? "Missing Resource"
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { PartDateValue(displayPart.property(definition.key))?.date ?? .now },
            set: { setProperty(.string(PartDateValue.string(from: $0))) }
        )
    }

    private func arrayElementBinding(_ index: Int) -> Binding<PartProperty.Value> {
        arrayElementBinding(index, key: definition.key, fallback: .string(""))
    }

    private func arrayBinding(count: Int) -> Binding<[PartProperty.Value]> {
        Binding(
            get: {
                var values = displayPart.propertyValue(definition.key).arrayValue ?? []
                while values.count < count { values.append(.boolean(false)) }
                return Array(values.prefix(count))
            },
            set: { values in
                setProperty(.array(Array(values.prefix(count))))
            }
        )
    }

    private func arrayElementBinding(
        _ index: Int,
        key: PartProperty.Key,
        fallback: PartProperty.Value
    ) -> Binding<PartProperty.Value> {
        Binding(
            get: {
                let values = displayPart.propertyValue(key).arrayValue ?? []
                return values.indices.contains(index) ? values[index] : fallback
            },
            set: { newValue in
                var values = displayPart.propertyValue(key).arrayValue ?? []
                while values.count <= index { values.append(fallback) }
                values[index] = newValue
                setProperty(.array(values), key: key)
            }
        )
    }

    private var packageColorValue: PartPackageColorValue {
        if case .packageColor(let value) = displayPart.propertyValue(definition.key) { return value }
        if case .packageColor(let value) = definition.defaultValue { return value }
        return .init(source: PartThemeValueSelection.manualCustom, customColor: "#000000", opacity: 1)
    }

    private var packageColorSourceBinding: Binding<String> {
        Binding(
            get: { packageColorValue.source },
            set: { source in
                var value = packageColorValue
                value.source = source
                if let palette = theme.colourPalettes.resolvedPalette(id: value.paletteID) {
                    value.shade = palette.lightDefaultShade
                    value.darkShade = palette.darkDefaultShade
                }
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageColorShadeBinding: Binding<ColourShade> {
        Binding(get: { appearance == .light ? packageColorValue.shade : packageColorValue.darkShade }, set: { shade in
            var value = packageColorValue
            if appearance == .light { value.shade = shade } else { value.darkShade = shade }
            setProperty(.packageColor(value))
        })
    }

    private var packageCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                (Color(hex: appearance == .light ? packageColorValue.customColor : packageColorValue.darkCustomColor) ?? .black)
                    .opacity(appearance == .light ? packageColorValue.opacity : packageColorValue.darkOpacity)
            },
            set: { color in
                var value = packageColorValue
                let hex = color.hexString ?? "#000000"
                let alpha = Double(NSColor(color).usingColorSpace(.sRGB)?.alphaComponent ?? 1)
                if appearance == .light { value.customColor = hex; value.opacity = alpha }
                else { value.darkCustomColor = hex; value.darkOpacity = alpha }
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageShadowValue: PartPackageShadowValue {
        if case .packageShadow(let value) = displayPart.propertyValue(definition.key) { return value }
        if case .packageShadow(let value) = definition.defaultValue { return value }
        return .defaultCustom
    }

    private var packageShadowSourceBinding: Binding<String> {
        Binding(
            get: { packageShadowValue.source },
            set: { source in
                var value = packageShadowValue
                value.source = source
                setProperty(.packageShadow(value))
            }
        )
    }

    private var packageShadowLayersBinding: Binding<[ThemeShadowLayer]> {
        Binding(
            get: { packageShadowValue.customLayers },
            set: { layers in
                var value = packageShadowValue
                value.customLayers = layers
                setProperty(.packageShadow(value))
            }
        )
    }


    @ViewBuilder
    private func controlArrayRow(
        element: PartPropertyControl,
        count: Int,
        subtitles: [String],
        buttonTexts: [String],
        buttonIcons: [String],
        activeButtonTexts: [String],
        activeButtonIcons: [String],
        buttonSelectionMode: PartPackageControl.ButtonSelectionMode,
        units: [String],
        help: String?
    ) -> some View {
        if case .date = element {
            DateArrayPartControl(
                label: definition.label,
                subtitles: subtitles,
                help: help,
                minimum: definition.dateMinimum,
                maximum: definition.dateMaximum,
                indicator: responsiveIndicator,
                values: (0..<count).map(dateArrayBinding)
            )
        } else if case .button = element, buttonSelectionMode == .single {
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                InspectorSegmentedButtonControl(
                    subtitles: subtitles,
                    buttonTexts: buttonTexts,
                    buttonIcons: buttonIcons,
                    activeButtonTexts: activeButtonTexts,
                    activeButtonIcons: activeButtonIcons,
                    help: help,
                    values: arrayBinding(count: count)
                )
            }
        } else {
            InspectorRow(title: definition.label, alignment: .top, indicator: responsiveIndicator) {
                InspectorControlArray(
                    count: count,
                    subtitles: subtitles,
                    buttonTexts: buttonTexts,
                    buttonIcons: buttonIcons,
                    activeButtonTexts: activeButtonTexts,
                    activeButtonIcons: activeButtonIcons,
                    units: units,
                    help: help,
                    values: (0..<count).map(arrayElementBinding),
                    element: element,
                    assets: assets
                )
            }
        }
    }

    private func dateArrayBinding(at index: Int) -> Binding<Date> {
        let binding = arrayElementBinding(index)
        return Binding(
            get: { PartDateValue(binding.wrappedValue.stringValue)?.date ?? .now },
            set: { binding.wrappedValue = .string(PartDateValue.string(from: $0)) }
        )
    }

    private var resetButton: some View {
        Button("Reset") {
            if effectiveBreakpoint != .mobile { removeOverride(for: definition.key) }
            else { setProperty(definition.defaultValue) }
        }
        .disabled(effectiveBreakpoint != .mobile
            ? !part.hasResponsiveOverride(definition.key, at: effectiveBreakpoint)
            : part.propertyValue(definition.key) == definition.defaultValue)
    }

    private var responsiveIndicator: InspectorRowIndicator {
        InspectorRowIndicator(
            isVisible: breakpoint != .mobile && definition.isResponsive,
            isOverridden: part.hasResponsiveOverride(definition.key, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: toggleResponsiveOverride
        )
    }

    private var imageFocalPointResponsiveIndicator: InspectorRowIndicator {
        let focalPointDefinition = part.type.definition.properties.first { $0.key == imageFocalPointKey }
        return InspectorRowIndicator(
            isVisible: breakpoint != .mobile && focalPointDefinition?.isResponsive == true,
            isOverridden: part.hasResponsiveOverride(imageFocalPointKey, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: { toggleResponsiveOverride(for: imageFocalPointKey) }
        )
    }


    private var selectedToken: DesignToken? {
        displayPart.propertyValue(definition.key).tokenValue
    }

    private var alignmentSegments: [InspectorSegment<String>] {
        [
            InspectorSegment(value: "start", systemImage: "text.alignleft", accessibilityLabel: "Start", help: "Align text to the start"),
            InspectorSegment(value: "center", systemImage: "text.aligncenter", accessibilityLabel: "Centre", help: "Centre text"),
            InspectorSegment(value: "end", systemImage: "text.alignright", accessibilityLabel: "End", help: "Align text to the end"),
            InspectorSegment(value: "justify", systemImage: "text.justify", accessibilityLabel: "Justify", help: "Justify text")
        ]
    }

    private func segmentedOptions(for choices: [PartPropertyChoice]) -> [InspectorSegment<String>] {
        choices.map { choice in
            return InspectorSegment(
                value: choice.value,
                title: choice.systemImage == nil ? choice.label : nil,
                systemImage: choice.systemImage,
                accessibilityLabel: choice.label,
                help: choice.label
            )
        }
    }

    private func tokenPicker(tokens: [DesignToken], customLabel: String) -> some View {
        Picker("", selection: tokenBinding(allowedTokens: tokens)) {
            Text(customLabel).tag(nil as DesignToken?)
            ForEach(tokens) { token in
                Text(token.displayName).tag(token as DesignToken?)
            }
        }
        .labelsHidden()
    }

    private func tokenBinding(allowedTokens: [DesignToken]) -> Binding<DesignToken?> {
        Binding(
            get: {
                guard let token = selectedToken, allowedTokens.contains(token) else { return nil }
                return token
            },
            set: { token in
                if let token {
                    setProperty(.token(token))
                } else {
                    setProperty(.color(displayPart.colorProperty(definition.key, theme: theme)))
                }
            }
        )
    }

    private func setProperty(
        _ value: PartProperty.Value,
        key: PartProperty.Key? = nil
    ) {
        let key = key ?? definition.key
        let effectiveBreakpoint = effectiveBreakpoint(for: key)
        if selectedParts.count > 1 {
            let ids = selectedParts.map(\.id)
            if effectiveBreakpoint == .mobile {
                editor.setProperties(ids: ids, key: key, value: value)
            } else {
                editor.setResponsiveProperties(
                    ids: ids,
                    key: key,
                    value: value,
                    breakpoint: effectiveBreakpoint
                )
            }
            return
        }
        if effectiveBreakpoint == .mobile {
            if editsSharedDefinition {
                editor.setSharedReusableProperty(partID: part.id, key: key, value: value)
            } else {
                editor.setProperty(id: part.id, key: key, value: value)
            }
        } else if editsSharedDefinition {
            editor.setSharedReusableResponsiveProperty(
                partID: part.id,
                key: key,
                value: value,
                breakpoint: effectiveBreakpoint
            )
        } else {
            editor.setResponsiveProperty(id: part.id, key: key, value: value, breakpoint: effectiveBreakpoint)
        }
    }

    private func removeOverride(for key: PartProperty.Key) {
        if selectedParts.count > 1 {
            editor.removeResponsiveOverrides(
                ids: selectedParts.map(\.id),
                key: key,
                breakpoint: breakpoint
            )
            return
        }
        if editsSharedDefinition {
            editor.removeSharedReusableResponsiveOverride(
                partID: part.id,
                key: key,
                breakpoint: breakpoint
            )
        } else {
            editor.removeResponsiveOverride(id: part.id, key: key, breakpoint: breakpoint)
        }
    }

    private func toggleResponsiveOverride() {
        toggleResponsiveOverride(for: definition.key)
    }

    private func toggleResponsiveOverride(for key: PartProperty.Key) {
        if part.hasResponsiveOverride(key, at: breakpoint) {
            removeOverride(for: key)
        } else {
            setProperty(part.propertyValue(key, at: breakpoint, screens: theme.screens), key: key)
        }
    }

    private var displayPart: PartNode {
        part.resolved(at: effectiveBreakpoint, screens: theme.screens)
    }

    private var effectiveBreakpoint: ResponsiveBreakpoint {
        effectiveBreakpoint(for: definition.key)
    }

    private func effectiveBreakpoint(for key: PartProperty.Key) -> ResponsiveBreakpoint {
        let propertyDefinition = part.type.definition.properties.first { $0.key == key }
        return propertyDefinition?.isResponsive == true ? breakpoint : .mobile
    }

    private enum StringValueKind {
        case string
        case choice

        func value(_ string: String) -> PartProperty.Value {
            switch self {
            case .string: .string(string)
            case .choice: .choice(string)
            }
        }
    }
}

private struct InspectorUnitLabel: View {
    let unit: String

    var body: some View {
        CharacterWidthText(
            value: unit,
            characterCount: 3,
            fontSize: NSFont.smallSystemFontSize
        )
            .foregroundStyle(.secondary)
            .accessibilityHidden(unit.isEmpty)
    }
}

private struct CharacterWidthText: View {
    let value: String
    let characterCount: Int
    let fontSize: CGFloat

    private var reservedWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(
            ofSize: fontSize,
            weight: .regular
        )

        let characterWidth = ("0" as NSString).size(
            withAttributes: [.font: font]
        ).width

        return characterWidth * CGFloat(characterCount)
    }

    var body: some View {
        Text(value)
            .font(
                .system(
                    size: fontSize,
                    design: .monospaced
                )
            )
            .frame(
                width: reservedWidth,
                alignment: .leading
            )
    }
}

private struct InspectorControlArray: View {
    let count: Int
    let subtitles: [String]
    let buttonTexts: [String]
    let buttonIcons: [String]
    let activeButtonTexts: [String]
    let activeButtonIcons: [String]
    let units: [String]
    let help: String?
    let values: [Binding<PartProperty.Value>]
    let element: PartPropertyControl
    let assets: [ProjectAsset]

    @ViewBuilder
    var body: some View {
        if case .slider = element {
            VStack(spacing: 8) {
                arrayItems
            }
        } else if case .icon = element, count > 2 {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        arrayItem(at: row * 2)
                        if row * 2 + 1 < count {
                            arrayItem(at: row * 2 + 1)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                arrayItems
            }
        }
    }

    @ViewBuilder
    private var arrayItems: some View {
        ForEach(0..<count, id: \.self) { index in
            arrayItem(at: index)
        }
    }

    private func arrayItem(at index: Int) -> some View {
        InspectorControlArrayItem(
            subtitle: subtitles.indices.contains(index) ? subtitles[index] : nil,
            buttonText: buttonTexts.indices.contains(index) ? buttonTexts[index] : "",
            buttonIcon: buttonIcons.indices.contains(index) ? buttonIcons[index] : nil,
            activeButtonText: activeButtonTexts.indices.contains(index) ? activeButtonTexts[index] : nil,
            activeButtonIcon: activeButtonIcons.indices.contains(index) ? activeButtonIcons[index] : nil,
            unit: units.indices.contains(index) ? units[index] : "",
            help: help,
            value: values[index],
            element: element,
            assets: assets
        )
        .frame(maxWidth: .infinity)
    }
}

private struct InspectorControlArrayItem: View {
    let subtitle: String?
    let buttonText: String
    let buttonIcon: String?
    let activeButtonText: String?
    let activeButtonIcon: String?
    let unit: String
    let help: String?
    @Binding var value: PartProperty.Value
    let element: PartPropertyControl
    let assets: [ProjectAsset]

    @ViewBuilder
    var body: some View {
        if case .slider(let range, let step, let ticks, let fallbackUnit, let showsValueField) = element {
            sliderGrid(
                range: range,
                step: step,
                ticks: ticks,
                unit: unit.isEmpty ? fallbackUnit : unit,
                showsValueField: showsValueField
            )
            .controlSize(.small)
            .help(help ?? subtitle ?? "")
        } else {
            VStack(spacing: 4) {
                control
                if let subtitle, !subtitle.isEmpty {
                    subtitleText(subtitle)
                }
            }
            .controlSize(.small)
            .help(help ?? subtitle ?? "")
        }
    }

    private func sliderGrid(
        range: ClosedRange<Double>,
        step: Double,
        ticks: Int,
        unit: String,
        showsValueField: Bool
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow {
                InspectorSlider(
                    value: numberBinding,
                    range: range,
                    step: step,
                    tickMarkCount: ticks,
                    accessibilityLabel: subtitle ?? "Slider",
                    help: help
                )
                .frame(maxWidth: .infinity)

                if showsValueField {
                    InspectorNumberField(
                        value: numberBinding,
                        range: range,
                        step: step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: unit)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                GridRow {
                    subtitleText(subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsValueField {
                        Color.clear.frame(width: 64, height: 0)
                        InspectorUnitLabel(unit: "").hidden()
                    }
                }
            }
        }
    }

    private func subtitleText(_ subtitle: String) -> some View {
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(subtitle)
    }

    @ViewBuilder
    private var control: some View {
        switch element {
        case .color:
            InspectorColorWell(color: colorBinding)
        case .colorWithOpacity:
            InspectorColorWell(color: colorBinding, supportsAlpha: true)
        case .literalColor(let allowsOpacity):
            InspectorColorWell(color: colorBinding, supportsAlpha: allowsOpacity)
        case .icon:
            FoundryIconPicker(
                selection: iconBinding,
                accessibilityLabel: subtitle ?? "Icon"
            )
        case .singleLineText:
            InspectorTextField(text: stringBinding, accessibilityLabel: subtitle ?? "Text value", help: help)
        case .number(let range, let step, let unit):
            HStack(spacing: 4) {
                InspectorNumberField(
                    value: numberBinding,
                    range: range,
                    accessibilityLabel: subtitle ?? "Number value",
                    help: help
                )
                InspectorStepper(value: numberBinding, range: range, increment: step, accessibilityLabel: subtitle ?? "Number value")
                InspectorUnitLabel(unit: self.unit.isEmpty ? unit : self.unit)
            }
        case .slider(let range, let step, let ticks, let unit, let showsValueField):
            HStack(spacing: 8) {
                InspectorSlider(value: numberBinding, range: range, step: step, tickMarkCount: ticks, accessibilityLabel: subtitle ?? "Slider", help: help)
                if showsValueField {
                    InspectorNumberField(
                        value: numberBinding,
                        range: range,
                        step: step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: self.unit.isEmpty ? unit : self.unit)
                }
            }
        case .date:
            EmptyView()
        case .button:
            ButtonArrayItemPartControl(
                buttonText: buttonText,
                systemImage: buttonIcon,
                activeButtonText: activeButtonText,
                activeSystemImage: activeButtonIcon,
                isActive: booleanBinding
            )
        case .toggle:
            Toggle("", isOn: booleanBinding).labelsHidden()
        case .choice(let choices):
            InspectorPopup(
                selection: stringBinding,
                options: choices.map {
                    .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                },
                accessibilityLabel: subtitle ?? "Choice",
                help: help
            )
        case .image:
            InspectorPopup(selection: assetBinding, options: [InspectorPopupOption(title: "None", value: nil)] + assets.map { .init(title: $0.filename, value: $0.id as UUID?) }, accessibilityLabel: subtitle ?? "Image", help: help)
        default:
            Text("Unsupported")
                .foregroundStyle(.secondary)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { value.stringValue },
            set: { newValue in
                if case .choice = element {
                    value = .choice(newValue)
                } else {
                    value = .string(newValue)
                }
            }
        )
    }

    private var iconBinding: Binding<String> {
        Binding(get: { value.stringValue }, set: { value = .choice($0) })
    }

    private var numberBinding: Binding<Double> {
        Binding(get: { value.numberValue ?? 0 }, set: { value = .number($0) })
    }

    private var booleanBinding: Binding<Bool> {
        Binding(get: { value.booleanValue ?? false }, set: { value = .boolean($0) })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: value.stringValue) ?? .black },
            set: {
                value = .color(
                    element.allowsLiteralColorOpacity
                        ? ($0.hexStringWithAlpha ?? "#000000FF")
                        : ($0.hexString ?? "#000000")
                )
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { PartDateValue(value.stringValue)?.date ?? .now },
            set: { value = .string(PartDateValue.string(from: $0)) }
        )
    }

    private var assetBinding: Binding<UUID?> {
        Binding(
            get: { value.stringValue.foundryAssetID },
            set: { id in
                let reference = id.flatMap { selectedID in assets.first(where: { $0.id == selectedID })?.reference } ?? ""
                value = .url(reference)
            }
        )
    }
}

private extension PartPropertyControl {
    var allowsLiteralColorOpacity: Bool {
        switch self {
        case .colorWithOpacity, .literalColor(allowsOpacity: true): true
        default: false
        }
    }
}

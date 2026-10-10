import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PartPropertyEditor: View {
    @Environment(\.canvasAppearance) private var appearance
    @State private var videoPosterTask: Task<Void, Never>?
    @State private var generatedVideoPoster: NSImage?
    @State private var isAnalysingVideo = false
    @State private var videoAnalysisError: String?
    @Namespace private var frameworkSpacingFocusNamespace
    let definition: PartPropertyDefinition
    let part: PartNode
    let selectedParts: [PartNode]
    let currentPage: Page?
    let framework: Framework
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?
    /// When present, this editor reads and writes one collection record rather
    /// than the selected part. The control UI remains exactly the same.
    let collectionRecord: Binding<PartProperty.Value>?
    let collectionDefinitions: [PartPropertyDefinition]
    let selectedPrimitive: CanvasPrimitiveSelection?
    let selectPrimitive: (CanvasPrimitiveSelection?) -> Void

    init(
        definition: PartPropertyDefinition,
        part: PartNode,
        selectedParts: [PartNode],
        currentPage: Page?,
        framework: Framework,
        assets: [ProjectAsset],
        assetContents: ProjectAssetContents,
        pages: [Page],
        folders: [PageFolder],
        publicURL: String,
        editor: ProjectEditor,
        editsSharedDefinition: Bool,
        breakpoint: ResponsiveBreakpoint,
        importMedia: @escaping (URL, UTType) -> ProjectAsset?,
        collectionRecord: Binding<PartProperty.Value>? = nil,
        collectionDefinitions: [PartPropertyDefinition] = [],
        selectedPrimitive: CanvasPrimitiveSelection? = nil,
        selectPrimitive: @escaping (CanvasPrimitiveSelection?) -> Void = { _ in }
    ) {
        self.definition = definition
        self.part = part
        self.selectedParts = selectedParts
        self.currentPage = currentPage
        self.framework = framework
        self.assets = assets
        self.assetContents = assetContents
        self.pages = pages
        self.folders = folders
        self.publicURL = publicURL
        self.editor = editor
        self.editsSharedDefinition = editsSharedDefinition
        self.breakpoint = breakpoint
        self.importMedia = importMedia
        self.collectionRecord = collectionRecord
        self.collectionDefinitions = collectionDefinitions
        self.selectedPrimitive = selectedPrimitive
        self.selectPrimitive = selectPrimitive
    }

    @ViewBuilder
    var body: some View {
        Group {
            if let subtitle = definition.subtitle,
               !subtitle.isEmpty,
               !definition.control.isArray,
               !isDateControl,
               !isNoteControl,
               !isLinkControl {
                // Keep the control's GridRow directly in the inspector grid.
                // A stack here detaches its label and field from their columns.
                editorControl
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellUnsizedAxes(.horizontal)
                }
            } else {
                editorControl
            }
        }
        .environment(\.inspectorControlReset, InspectorControlReset(
            isEnabled: canResetControl,
            action: resetControl
        ))
        .environment(\.inspectorControlModified, controlHasChanges)
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
            controlArrayRow(element: element, count: count, subtitles: subtitles, buttonTexts: buttonTexts, buttonIcons: buttonIcons, activeButtonTexts: activeButtonTexts, activeButtonIcons: activeButtonIcons, buttonSelectionMode: buttonSelectionMode, units: units, help: help)
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
                            framework: framework,
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
        case .slider(let options):
            SliderPartControl(
                label: definition.label,
                options: options,
                indicator: responsiveIndicator,
                value: numberBinding
            )
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
        case .packageColor(let frameworkValues, let opacity, _, _):
            FrameworkColorPartControl(
                label: definition.label,
                choices: frameworkValues ? framework.colorChoices : [],
                allowsCustom: definition.allowsCustomFrameworkValue,
                framework: framework,
                source: packageColorSourceBinding,
                shade: packageColorShadeBinding,
                customColor: packageCustomColorBinding,
                opacityPercent: packageColorOpacityBinding,
                allowsOpacity: opacity,
                indicator: responsiveIndicator
            )
        case .themeColor:
            ThemeColorPartControl(label: definition.label, framework: framework,
                indicator: responsiveIndicator,
                tokenSections: colourTokenSections,
                linksOnly: isLinkColour,
                allowsInherit: part.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource.map { [.foreground, .linkStyling].contains($0.type) } ?? true,
                selection: stringBinding(as: .choice))
        case .choice(let choices):
            let availableChoices = choicesForCurrentContext(choices)
            if definition.presentation == .segmented {
                InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                    InspectorSegmentedControl(
                        selection: stringBinding(as: .choice),
                        segments: segmentedOptions(for: availableChoices)
                    )
                }
            } else {
                SelectPartControl(
                    label: definition.label,
                    options: availableChoices.map {
                        .init(title: $0.label, value: $0.value, separatorBefore: $0.separatorBefore)
                    },
                    indicator: responsiveIndicator,
                    selection: stringBinding(as: .choice)
                )
            }
        case .frameworkFont:
            FrameworkFontPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator, selection: stringBinding(as: .choice))
        case .frameworkSpacing:
            let singleSpacingSelection: FrameworkPaddingValue.EdgeValue = {
                if case .frameworkSpacing(let value) = displayPart.propertyValue(definition.key) { return value.selection }
                if case .frameworkSpacing(let value) = definition.defaultValue { return value.selection }
                return FrameworkPaddingValue.EdgeValue()
            }()
            InspectorRow(title: definition.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Spacing" : definition.label, indicator: responsiveIndicator) {
                HStack(spacing: 8) {
                    FrameworkSpacingInput<PaddingPolicy>(binding: Binding(get: {
                        if case .frameworkSpacing(let value) = displayPart.propertyValue(definition.key) { return value.selection }
                        if case .frameworkSpacing(let value) = definition.defaultValue { return value.selection }
                        return FrameworkPaddingValue.EdgeValue()
                    }, set: { setProperty(.frameworkSpacing(.init(selection: $0))) }), title: definition.label.isEmpty ? "Spacing" : definition.label, framework: framework, focusNamespace: frameworkSpacingFocusNamespace, bootstrapSpacing: bootstrapGapPrefix != nil, bootstrapClassPrefix: bootstrapGapPrefix ?? "gap")

                    if bootstrapGapPrefix == nil {
                        FrameworkModeToggle(usesFrameworkTokens: !singleSpacingSelection.isCustom) {
                            var value = FrameworkSingleSpacingValue(selection: singleSpacingSelection)
                            value.setUsesFrameworkTokens(singleSpacingSelection.isCustom)
                            setProperty(.frameworkSpacing(value))
                        }
                    }
                }
            }
            .focusScope(frameworkSpacingFocusNamespace)
            .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Spacing")
        case .frameworkBorderWidth:
            FrameworkBorderWidthPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                bootstrapBorders: part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.control.type == .borderSides,
                value: Binding(get: {
                    if case .frameworkBorderWidth(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkBorderWidth(let value) = definition.defaultValue { return value }
                    return FrameworkBorderWidthValue()
                }, set: { setProperty(.frameworkBorderWidth($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == (definition.inspectorControlID ?? definition.key.rawValue) }?.tooltip ?? "Border")
        case .frameworkRadius:
            FrameworkRadiusPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                value: Binding(get: {
                    if case .frameworkRadius(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkRadius(let value) = definition.defaultValue { return value }
                    return FrameworkRadiusValue()
                }, set: { setProperty(.frameworkRadius($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Radius")
        case .frameworkMargin:
            FrameworkMarginPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                bootstrapSpacing: isBootstrapSpacing,
                value: Binding(get: {
                    if case .frameworkMargin(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkMargin(let value) = definition.defaultValue { return value }
                    return FrameworkMarginValue()
                }, set: { setProperty(.frameworkMargin($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Margin")
        case .frameworkPadding:
            FrameworkPaddingPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                bootstrapSpacing: isBootstrapSpacing,
                value: Binding(get: {
                    if case .frameworkPadding(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkPadding(let value) = definition.defaultValue { return value }
                    return FrameworkPaddingValue()
                }, set: { setProperty(.frameworkPadding($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Padding")
        case .edges(let units):
            FrameworkMarginPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                allowsFrameworkTokens: false, unitChoices: units, fallbackLabel: "Edges",
                value: Binding(get: {
                    if case .frameworkMargin(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkMargin(let value) = definition.defaultValue { return value }
                    return PartPackageFrameworkMarginControl.customZero(units: units)
                }, set: { setProperty(.frameworkMargin($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Edges")
        case .corners(let units):
            FrameworkRadiusPartControl(label: definition.label, framework: framework, indicator: responsiveIndicator,
                allowsFrameworkTokens: false, unitChoices: units, fallbackLabel: "Corners",
                value: Binding(get: {
                    if case .frameworkRadius(let value) = displayPart.propertyValue(definition.key) { return value }
                    if case .frameworkRadius(let value) = definition.defaultValue { return value }
                    return PartPackageFrameworkRadiusControl.customZero(units: units)
                }, set: { setProperty(.frameworkRadius($0)) }))
                .help(part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.tooltip ?? "Corners")
        case .fontWeight(let font):
            FontFacePartControl(label: definition.label,
                options: fontFaceOptions(font: font, editsWeight: true),
                indicator: responsiveIndicator, weight: numberBinding, style: .constant("normal"), editsWeight: true)
        case .fontStyle(let font):
            FontFacePartControl(label: definition.label,
                options: fontFaceOptions(font: font, editsWeight: false),
                indicator: responsiveIndicator, weight: .constant(400), style: stringBinding(as: .choice), editsWeight: false)
        case .frameworkFontSize:
            SelectPartControl(
                label: definition.label,
                options: framework.fontSizeChoices.map { .init(title: $0.label, value: $0.value) },
                indicator: responsiveIndicator,
                selection: stringBinding(as: .choice)
            )
        case .pageFolder:
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                if folders.isEmpty {
                    Text("No folders in this project")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let selection = displayPart.propertyValue(definition.key).stringValue
                    Picker(definition.label, selection: stringBinding(as: .choice)) {
                        Text("None").tag("")
                        if !selection.isEmpty, !folders.contains(where: { $0.id.uuidString == selection }) {
                            Text("Missing folder").tag(selection)
                        }
                        ForEach(folders.sorted(by: { folderPathName($0) < folderPathName($1) })) { folder in
                            Text(folderPathName(folder)).tag(folder.id.uuidString)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(definition.label)
                }
            }
        case .frameworkStackingOrder:
            let stackingValue: PartPackageStackingOrderValue = {
                if case .packageStackingOrder(let value) = displayPart.propertyValue(definition.key) { return value }
                return .init(source: displayPart.propertyValue(definition.key).stringValue)
            }()
            InspectorRow(title: definition.label, indicator: responsiveIndicator) {
                HStack(spacing: 8) {
                    if stackingValue.isCustom {
                        TextField(definition.label, value: Binding(
                            get: { stackingValue.customValue },
                            set: { setProperty(.packageStackingOrder(.init(source: stackingValue.source, customValue: $0.rounded()))) }
                        ), format: .number.grouping(.never).precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    } else {
                        Picker(definition.label, selection: Binding(
                            get: { stackingValue.source },
                            set: { setProperty(.packageStackingOrder(.init(source: $0, customValue: stackingValue.customValue))) }
                        )) {
                            if !framework.zIndexes.predefined.contains(where: { $0.id == stackingValue.source }),
                               !framework.zIndexes.custom.contains(where: { $0.reference == stackingValue.source }) {
                                Text("Missing value").tag(stackingValue.source)
                            }
                            if !framework.zIndexes.custom.isEmpty {
                                Section("Custom") {
                                    ForEach(framework.zIndexes.custom) { token in
                                        Text("\(token.name) - \(Int(token.value))").tag(token.reference)
                                    }
                                }
                            }
                            Section("Framework values") {
                                ForEach(framework.zIndexes.predefined) { token in
                                    Text("\(token.title) - \(Int(token.value))").tag(token.id)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(definition.label)
                    }
                    FrameworkModeToggle(usesFrameworkTokens: !stackingValue.isCustom) {
                        if stackingValue.isCustom {
                            // Back to framework: select the token closest to the entered value.
                            let tokens = framework.zIndexes.predefined.map { ($0.id, $0.value) }
                                + framework.zIndexes.custom.map { ($0.reference, $0.value) }
                            let nearest = tokens.min {
                                abs($0.1 - stackingValue.customValue) < abs($1.1 - stackingValue.customValue)
                            }?.0 ?? "base"
                            setProperty(.packageStackingOrder(.init(source: nearest, customValue: stackingValue.customValue)))
                        } else {
                            // To custom: carry the selected token's own value.
                            let amount = framework.zIndexes.predefined.first { $0.id == stackingValue.source }?.value
                                ?? framework.zIndexes.custom.first { $0.reference == stackingValue.source }?.value
                                ?? 0
                            setProperty(.packageStackingOrder(.init(
                                source: PartFrameworkValueSelection.manualCustom,
                                customValue: amount
                            )))
                        }
                    }
                }
            }
        case .packageShadow:
            FrameworkShadowPartControl(
                label: definition.label,
                choices: framework.shadowChoices,
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
        case .spacer(let height):
            Color.clear
                .frame(height: height)
                .accessibilityHidden(true)
        case .toggle:
            TogglePartControl(
                label: definition.label,
                indicator: responsiveIndicator,
                isOn: booleanBinding,
                usesSwitch: definition.presentation == .switch
            )
        case .image, .svg:
            ImagePartControl(
                label: definition.label,
                previewImage: previewImage,
                remoteURL: remoteImageURL,
                allowsRemoteSource: !isSVGControl,
                supportsFocalPoint: definition.supportsImageFocalPoint,
                focalPoint: imageFocalPoint,
                focalPointIndicator: imageFocalPointResponsiveIndicator,
                isClearDisabled: displayPart.propertyValue(definition.key) == definition.defaultValue,
                altText: imageAltBinding,
                chooseImage: chooseImageFromFinder,
                clearImage: { setProperty(definition.defaultValue) },
                importImage: { url in
                    guard let asset = importMedia(url, isSVGControl ? .svg : .image) else { return false }
                    setProperty(.url(asset.reference))
                    return true
                },
                linkImage: { setProperty(.url($0.absoluteString)) },
                importRemoteImage: importRemoteImage,
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
                indicator: responsiveIndicator,
                showsPlaybackOptions: showsVideoPlaybackOptions,
                showsPosterOptions: allowsCustomVideoPoster,
                autoplay: videoAutoplayBinding,
                muted: videoBooleanBinding(videoMutedKey, fallback: false),
                showsControls: videoBooleanBinding(videoControlsKey, fallback: true),
                loops: videoBooleanBinding(videoLoopKey, fallback: false),
                startAt: videoStartAtBinding,
                isClearDisabled: displayPart.propertyValue(definition.key) == definition.defaultValue,
                importVideoFromMac: chooseVideoFromFinder,
                clearVideo: clearVideo,
                importVideo: { url in
                    guard let asset = importMedia(url, .movie) else { return false }
                    selectVideo(asset)
                    return true
                },
                choosePoster: chooseVideoPosterFromFinder,
                clearPoster: { setProperty(.url(""), key: videoPosterKey) },
                remoteURL: RemoteVideoImport.webURL(displayPart.property(definition.key)),
                allowsYouTube: showsVideoPlaybackOptions,
                posterFirst: videoBooleanBinding(PartVideoTemplateValues.posterFirstPropertyKey(for: definition.key.rawValue), fallback: true),
                linkVideo: linkRemoteVideo,
                importRemoteVideo: importRemoteVideo
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
        case .collection(let itemLabel, let fields):
            CollectionPartControl(
                label: definition.label,
                collectionKey: definition.key,
                itemLabel: itemLabel,
                fields: fields,
                values: Binding(
                    get: { displayPart.propertyValue(definition.key).arrayValue ?? [] },
                    set: { setProperty(.array($0)) }
                ),
                part: part,
                selectedParts: selectedParts,
                currentPage: currentPage,
                framework: framework,
                assets: assets,
                assetContents: assetContents,
                pages: pages,
                folders: folders,
                publicURL: publicURL,
                editor: editor,
                editsSharedDefinition: editsSharedDefinition,
                breakpoint: breakpoint,
                importMedia: importMedia,
                selectedPrimitive: selectedPrimitive,
                selectPrimitive: selectPrimitive
            )
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
        let source = allowsCustomVideoPoster ? displayPart.property(videoPosterKey) : ""
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

    private var allowsCustomVideoPoster: Bool {
        part.type.definition.package?.renderDefinition.properties
            .first { $0.id == definition.key.rawValue }?.usesAutomaticVideoPoster != true
    }

    private var showsVideoPlaybackOptions: Bool {
        guard let package = part.type.definition.package else { return true }
        return !package.manifest.controlGroups
            .flatMap(\.properties)
            .contains { $0.id == definition.key.rawValue && $0.controlGroupSource?.type == .background && $0.control.type == .video }
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

    private var imageFocalPoint: CGPoint {
        let point = PartImageTemplateValues.focalPoint(
            from: displayPart.propertyValue(imageFocalPointKey)
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

    /// The value when it links to an image on the web rather than an asset.
    private var remoteImageURL: URL? {
        let source = displayPart.property(definition.key)
        guard source.foundryAssetID == nil else { return nil }
        return ImagePartControl.webURL(source)
    }

    /// Downloads a web image and imports it like a dropped file, so the same
    /// type check, size limit and de-duplication apply.
    private func importRemoteImage(_ url: URL) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source),
              let type = UTType(typeIdentifier as String), type.conforms(to: .image) else { return false }
        // The import reads the type from the file's extension, so give the
        // download one that matches its bytes.
        var filename = url.lastPathComponent
        if filename.isEmpty || filename == "/" { filename = "image" }
        if UTType(filenameExtension: (filename as NSString).pathExtension)?.conforms(to: .image) != true,
           let preferred = type.preferredFilenameExtension {
            filename = (filename as NSString).deletingPathExtension + "." + preferred
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "foundry-remote-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file)
        } catch {
            return false
        }
        guard let asset = importMedia(file, .image) else { return false }
        setProperty(.url(asset.reference))
        return true
    }

    private var isSVGControl: Bool {
        if case .svg = definition.control { return true }
        return false
    }

    private func chooseImageFromFinder() {
        let panel = NSOpenPanel()
        panel.title = isSVGControl ? "Choose SVG" : "Choose Image"
        panel.allowedContentTypes = [isSVGControl ? .svg : .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let asset = importMedia(url, isSVGControl ? .svg : .image) else { return }
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

    private func selectVideo(_ asset: ProjectAsset) {
        videoPosterTask?.cancel()
        generatedVideoPoster = nil
        videoAnalysisError = nil
        let wasAlreadySelected = selectedAsset?.id == asset.id
        setProperty(.url(asset.reference))
        if wasAlreadySelected { analyseVideoIfNeeded(asset) }
    }

    private func linkRemoteVideo(_ url: URL) {
        if YouTubeVideo.isYouTubeAddress(url.absoluteString) {
            guard showsVideoPlaybackOptions, YouTubeVideo.id(from: url.absoluteString) != nil else { return }
        }
        videoPosterTask?.cancel()
        generatedVideoPoster = nil
        isAnalysingVideo = false
        videoAnalysisError = nil
        setProperty(.url(url.absoluteString))
    }

    private func importRemoteVideo(_ url: URL) async -> Bool {
        let original = displayPart.propertyValue(definition.key)
        guard let file = try? await RemoteVideoImport.download(url) else { return false }
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        guard !Task.isCancelled else { return false }
        if let collectionRecord {
            let current = PartCollectionValue.value(
                fieldID: definition.key.rawValue,
                in: collectionRecord.wrappedValue,
                at: effectiveBreakpoint,
                screens: framework.screens
            )
            guard current == original else { return false }
        } else if let current = editor.document.site.pages.flatMap(\.parts).node(withID: part.id),
                  current.propertyValue(definition.key) != original {
            return false
        }
        guard let asset = importMedia(file, .movie) else { return false }
        selectVideo(asset)
        return true
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
            get: {
                let value = displayPart.property(definition.key)
                if part.type == .container && definition.key.rawValue == "width" {
                    return BootstrapLayout.containerClass(value, screens: framework.screens)
                }
                return value
            },
            set: { newValue in
                if backgroundInspectorContext?.localID == "backgroundMode", newValue == "hover" {
                    replaceVideoBackgroundStyleForHover()
                }
                setProperty(kind.value(newValue))
            }
        )
    }

    /// The Background group shares its Normal style property between Static
    /// and Hover modes. Video is valid only in Static mode, so its segment is
    /// removed dynamically when the top-level Type is Hover.
    private func choicesForCurrentContext(
        _ choices: [PartPropertyChoice]
    ) -> [PartPropertyChoice] {
        let custom = BootstrapCustomTokenClasses.choices(existing: choices.map(\.value), framework: framework)
        let choices = choices + custom.enumerated().map { index, value in
            PartPropertyChoice(value: value, label: BootstrapCustomTokenClasses.label(for: value, framework: framework), separatorBefore: index == 0)
        }
        if part.type == .container && definition.key.rawValue == "width" {
            return choices.filter { BootstrapLayout.allowsContainerClass($0.value, screens: framework.screens) }
        }
        guard let context = backgroundInspectorContext else { return choices }
        return context.choices(choices, mode: displayPart.property(context.modeKey))
    }

    private var backgroundInspectorContext: PartBackgroundInspectorContext? {
        guard collectionRecord == nil else { return nil }
        return PartBackgroundInspectorContext(property: part.type.definition.package?.manifest.resolvedProperties.first {
            $0.id == definition.key.rawValue
        })
    }

    private func replaceVideoBackgroundStyleForHover() {
        guard let context = backgroundInspectorContext,
              case .choice(let choices)? = part.type.definition.property(for: context.styleKey)?.control,
              let fallback = context.replacementStyle(newMode: "hover", currentStyle: displayPart.property(context.styleKey), choices: choices) else {
            return
        }
        setProperty(.choice(fallback), key: context.styleKey)
    }

    private func folderPathName(_ folder: PageFolder) -> String {
        var names = [folder.name]
        var current = folder
        var visited: Set<UUID> = [folder.id]
        while let parentID = current.parentID, visited.insert(parentID).inserted,
              let parent = folders.first(where: { $0.id == parentID }) {
            names.insert(parent.name, at: 0)
            current = parent
        }
        return names.joined(separator: " / ")
    }

    private func fontFaceOptions(font: String?, editsWeight: Bool) -> FontFaceOptions {
        let companions = availableDefinitions.filter { property in
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
            framework: framework, assets: assetContents,
            selectedWeight: editsWeight ? nil : companion?.numberValue.map(Int.init),
            selectedStyle: editsWeight ? companion?.stringValue : nil)
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { displayPart.numberProperty(definition.key, framework: framework) },
            set: { setProperty(.number($0)) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: displayPart.colorProperty(definition.key, framework: framework)) ?? .white },
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
        return .init(source: PartFrameworkValueSelection.manualCustom, customColor: "#000000", opacity: 1)
    }

    private var packageColorSourceBinding: Binding<String> {
        Binding(
            get: { packageColorValue.source },
            set: { source in
                var value = packageColorValue
                value.source = source
                if let palette = framework.colourPalettes.resolvedPalette(id: value.paletteID) {
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

    private var packageColorOpacityBinding: Binding<Double> {
        Binding(
            get: { (appearance == .light ? packageColorValue.opacity : packageColorValue.darkOpacity) * 100 },
            set: { percent in
                var value = packageColorValue
                let alpha = min(max(percent / 100, 0), 1)
                if appearance == .light { value.opacity = alpha } else { value.darkOpacity = alpha }
                setProperty(.packageColor(value))
            }
        )
    }

    private var packageCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                Color.stored(
                    hex: appearance == .light ? packageColorValue.customColor : packageColorValue.darkCustomColor,
                    opacity: appearance == .light ? packageColorValue.opacity : packageColorValue.darkOpacity
                )
            },
            set: { color in
                var value = packageColorValue
                // Read the well's colour as it is; only convert for the hex.
                let picked = NSColor(color)
                let alpha = Double(picked.alphaComponent)
                guard let hex = color.hexString else { return }
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

    private var packageShadowLayersBinding: Binding<[FrameworkShadowLayer]> {
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

    private func resetControl() {
        if let collectionRecord {
            if effectiveBreakpoint != .mobile {
                collectionRecord.wrappedValue = PartCollectionValue.removingOverride(
                    fieldID: definition.key.rawValue,
                    from: collectionRecord.wrappedValue,
                    at: effectiveBreakpoint
                )
            } else {
                collectionRecord.wrappedValue = PartCollectionValue.setting(
                    definition.defaultValue,
                    fieldID: definition.key.rawValue,
                    in: collectionRecord.wrappedValue
                )
            }
            return
        }
        if effectiveBreakpoint != .mobile { removeOverride(for: definition.key) }
        else { setProperty(definition.defaultValue) }
    }

    private var canResetControl: Bool {
        if let collectionRecord {
            return effectiveBreakpoint != .mobile
                ? PartCollectionValue.hasOverride(
                    fieldID: definition.key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: effectiveBreakpoint
                )
                : PartCollectionValue.value(
                    fieldID: definition.key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: .mobile,
                    screens: framework.screens
                ) != definition.defaultValue
        }
        return effectiveBreakpoint != .mobile
            ? part.hasResponsiveOverride(definition.key, at: effectiveBreakpoint)
            : part.propertyValue(definition.key) != definition.defaultValue
    }

    private var controlHasChanges: Bool {
        if collectionRecord != nil { return canResetControl }
        let state = PartInspectorControlState(part: part, definition: definition, framework: framework)
        let targets = selectedParts.isEmpty ? [part] : selectedParts
        return targets.contains { target in
            state.hasChanges(
                in: target,
                at: effectiveBreakpoint,
                screens: framework.screens
            )
        }
    }

    private var responsiveIndicator: InspectorRowIndicator {
        if let collectionRecord {
            return InspectorRowIndicator(
                isVisible: breakpoint != .mobile && definition.isResponsive,
                isOverridden: PartCollectionValue.hasOverride(
                    fieldID: definition.key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: breakpoint
                ),
                breakpointName: breakpoint.displayName,
                toggle: toggleResponsiveOverride
            )
        }
        return InspectorRowIndicator(
            isVisible: breakpoint != .mobile && definition.isResponsive,
            isOverridden: part.hasResponsiveOverride(definition.key, at: breakpoint),
            breakpointName: breakpoint.displayName,
            toggle: toggleResponsiveOverride
        )
    }

    private var imageFocalPointResponsiveIndicator: InspectorRowIndicator {
        let focalPointDefinition = availableDefinitions.first { $0.key == imageFocalPointKey }
        if let collectionRecord {
            return InspectorRowIndicator(
                isVisible: breakpoint != .mobile && focalPointDefinition?.isResponsive == true,
                isOverridden: PartCollectionValue.hasOverride(
                    fieldID: imageFocalPointKey.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: breakpoint
                ),
                breakpointName: breakpoint.displayName,
                toggle: { toggleResponsiveOverride(for: imageFocalPointKey) }
            )
        }
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
                    setProperty(.color(displayPart.colorProperty(definition.key, framework: framework)))
                }
            }
        )
    }

    private func setProperty(
        _ value: PartProperty.Value,
        key: PartProperty.Key? = nil
    ) {
        let key = key ?? definition.key
        if let collectionRecord {
            let viewed = effectiveBreakpoint(for: key)
            let target = viewed == .mobile
                ? ResponsiveBreakpoint.mobile
                : PartCollectionValue.governingBreakpoint(
                    fieldID: key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: viewed,
                    screens: framework.screens
                )
            collectionRecord.wrappedValue = PartCollectionValue.setting(
                value,
                fieldID: key.rawValue,
                in: collectionRecord.wrappedValue,
                at: target
            )
            return
        }
        // Overrides are created only by pinning the blue dot; an ordinary edit
        // writes to whichever pin (or the base) governs the viewed breakpoint,
        // so the change flows to every breakpoint inheriting that value.
        if selectedParts.count > 1, effectiveBreakpoint(for: key) != .mobile {
            let groups = Dictionary(grouping: selectedParts) {
                $0.governingBreakpoint(for: key, at: breakpoint, screens: framework.screens)
            }
            for target in ResponsiveBreakpoint.allCases where groups[target] != nil {
                write(value, key: key, at: target, ids: groups[target]!.map(\.id))
            }
            return
        }
        let target = effectiveBreakpoint(for: key) == .mobile
            ? .mobile
            : part.governingBreakpoint(for: key, at: breakpoint, screens: framework.screens)
        write(value, key: key, at: target)
    }

    /// Routes a write to the given breakpoint's store, preserving the existing
    /// multi-selection and shared-definition paths. `.mobile` means the base value.
    private func write(
        _ value: PartProperty.Value,
        key: PartProperty.Key,
        at target: ResponsiveBreakpoint,
        ids: [UUID]? = nil
    ) {
        if let ids = ids ?? (selectedParts.count > 1 ? selectedParts.map(\.id) : nil) {
            if target == .mobile {
                editor.setProperties(ids: ids, key: key, value: value)
            } else {
                editor.setResponsiveProperties(ids: ids, key: key, value: value, breakpoint: target)
            }
            return
        }
        if target == .mobile {
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
                breakpoint: target
            )
        } else {
            editor.setResponsiveProperty(id: part.id, key: key, value: value, breakpoint: target)
        }
    }

    private func removeOverride(for key: PartProperty.Key) {
        if let collectionRecord {
            collectionRecord.wrappedValue = PartCollectionValue.removingOverride(
                fieldID: key.rawValue,
                from: collectionRecord.wrappedValue,
                at: breakpoint
            )
            return
        }
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
        if let collectionRecord {
            if PartCollectionValue.hasOverride(
                fieldID: key.rawValue,
                in: collectionRecord.wrappedValue,
                at: breakpoint
            ) {
                removeOverride(for: key)
            } else {
                let value = PartCollectionValue.value(
                    fieldID: key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: breakpoint,
                    screens: framework.screens
                )
                collectionRecord.wrappedValue = PartCollectionValue.setting(
                    value,
                    fieldID: key.rawValue,
                    in: collectionRecord.wrappedValue,
                    at: breakpoint
                )
            }
            return
        }
        if part.hasResponsiveOverride(key, at: breakpoint) {
            removeOverride(for: key)
        } else {
            // Pinning stores exactly at the viewed breakpoint, capturing the value
            // currently showing there — the one write that may create an override.
            write(part.propertyValue(key, at: breakpoint, screens: framework.screens), key: key, at: breakpoint)
        }
    }

    private var isBootstrapSpacing: Bool {
        part.type.definition.package?.manifest.resolvedProperties.first { $0.id == definition.key.rawValue }?.controlGroupSource?.type == .spacing
    }

    private var colourTokenSections: [String] {
        if isLinkColour { return ["links"] }
        guard let manifest = part.type.definition.package?.manifest,
              let source = manifest.resolvedProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource else { return [] }
        if source.type == .borders { return ["borders", "blackWhite"] }
        return manifest.controlGroups.first(where: { $0.namespace == source.namespace })?.colourSections ?? []
    }

    private var isLinkColour: Bool {
        part.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource?.type == .linkStyling
    }

    private var bootstrapGapPrefix: String? {
        guard let source = part.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource,
              source.type == .gap else { return nil }
        return BootstrapControlGroupClasses.gapPrefix(source.localID)
    }

    private var displayPart: PartNode {
        var resolved = part.resolved(at: breakpoint, screens: framework.screens)
        if part.type.definition.package?.manifest.resolvedProperties.first(where: { $0.id == definition.key.rawValue })?.controlGroupSource?.type.generatesBootstrapClasses == true {
            resolved.setProperty(definition.key, value: part.propertyValue(definition.key, at: breakpoint, screens: framework.screens))
        }
        guard let record = collectionRecord?.wrappedValue else { return resolved }
        for field in collectionDefinitions {
            resolved.setProperty(
                field.key,
                value: PartCollectionValue.value(
                    fieldID: field.key.rawValue,
                    in: record,
                    at: field.isResponsive ? breakpoint : .mobile,
                    screens: framework.screens
                )
            )
        }
        return resolved
    }

    private var effectiveBreakpoint: ResponsiveBreakpoint {
        effectiveBreakpoint(for: definition.key)
    }

    private func effectiveBreakpoint(for key: PartProperty.Key) -> ResponsiveBreakpoint {
        let propertyDefinition = availableDefinitions.first { $0.key == key }
        return propertyDefinition?.isResponsive == true ? breakpoint : .mobile
    }

    private var availableDefinitions: [PartPropertyDefinition] {
        collectionRecord == nil ? part.type.definition.properties : collectionDefinitions
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
        if case .slider(let options) = element {
            sliderGrid(options: withMemberUnit(options))
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

    /// A control array can give each member its own unit.
    private func withMemberUnit(_ options: SliderOptions) -> SliderOptions {
        var options = options
        if !unit.isEmpty { options.unit = unit }
        return options
    }

    private func sliderGrid(options: SliderOptions) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow(alignment: .sliderTrack) {
                InspectorSlider(
                    value: numberBinding,
                    options: options,
                    accessibilityLabel: subtitle ?? "Slider",
                    help: help
                )
                .frame(maxWidth: .infinity)

                if options.editableValue {
                    InspectorNumberField(
                        value: numberBinding,
                        range: options.range,
                        step: options.step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: options.unit)
                } else {
                    InspectorSliderValueLabel(value: numberBinding.wrappedValue, options: options, unit: options.unit)
                }
            }

            if let subtitle, !subtitle.isEmpty {
                GridRow {
                    subtitleText(subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if options.editableValue {
                        Color.clear.frame(width: 64, height: 0)
                        InspectorUnitLabel(unit: "").hidden()
                    } else {
                        Color.clear.frame(width: 0, height: 0)
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
        case .slider(let options):
            HStack(alignment: .sliderTrack, spacing: 8) {
                InspectorSlider(value: numberBinding, options: options, accessibilityLabel: subtitle ?? "Slider", help: help)
                if options.editableValue {
                    InspectorNumberField(
                        value: numberBinding,
                        range: options.range,
                        step: options.step,
                        accessibilityLabel: "\(subtitle ?? "Slider") value",
                        help: help
                    )
                    .frame(width: 64)
                    InspectorUnitLabel(unit: self.unit.isEmpty ? options.unit : self.unit)
                } else {
                    InspectorSliderValueLabel(value: numberBinding.wrappedValue, options: options, unit: self.unit.isEmpty ? options.unit : self.unit)
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

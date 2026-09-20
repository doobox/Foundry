import Foundation

/// One entry of a manifest's `controls` array: either a single Standard/Framework
/// property, or a reference to a prebuilt Grouped control (`background`,
/// `spacing`, `sizing`, `borders`, `effects`, `layoutItem`) that expands into
/// several properties at this exact position.
nonisolated enum PartPackageControlsEntry: Codable, Equatable, Sendable {
    case property(PartPackageProperty)
    case group(PartPackageControlGroup)

    private struct TypeDiscriminator: Decodable {
        let type: String
    }

    init(from decoder: Decoder) throws {
        let discriminator = try TypeDiscriminator(from: decoder)
        if PartPackageControlGroup.Kind(rawValue: discriminator.type) != nil {
            self = .group(try PartPackageControlGroup(from: decoder))
        } else {
            self = .property(try PartPackageProperty(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .property(let property): try property.encode(to: encoder)
        case .group(let group): try group.encode(to: encoder)
        }
    }
}

nonisolated struct PartPackageManifest: Codable, Equatable, Sendable {
    let minimumAPIVersion: Int
    let identifier: String
    let name: String
    let description: String
    let author: String?
    let version: String
    let category: String
    let tags: [String]
    let showsInPartLibrary: Bool
    let allowedParents: [String]
    let controlsEntries: [PartPackageControlsEntry]
    let groups: [PartPackageInspectorGroup]
    let render: PartPackageRender
    let assets: [PartPackageAsset]
    let helpURL: URL?
    let missingPart: PartPackageMissingPart?
    let requiresPHP: Bool
    let libraries: [PartPackageLibraryRequirement]
    let updates: FoundryPackUpdateConfiguration?

    enum CodingKeys: String, CodingKey {
        case minimumAPIVersion
        case identifier = "id"
        case name = "title"
        case description
        case author
        case version
        case category = "group"
        case tags
        case showsInPartLibrary
        case allowedParents
        case controlsEntries = "controls"
        case groups
        case render = "templates"
        case assets
        case helpURL
        case missingPart
        case requiresPHP
        case libraries
        case updates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumAPIVersion = try container.decode(Int.self, forKey: .minimumAPIVersion)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decode(String.self, forKey: .version)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Other"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        showsInPartLibrary = try container.decodeIfPresent(Bool.self, forKey: .showsInPartLibrary) ?? true
        allowedParents = try container.decodeIfPresent([String].self, forKey: .allowedParents) ?? []
        controlsEntries = try container.decodeIfPresent([PartPackageControlsEntry].self, forKey: .controlsEntries) ?? []
        groups = try container.decodeIfPresent([PartPackageInspectorGroup].self, forKey: .groups) ?? []
        render = try container.decode(PartPackageRender.self, forKey: .render)
        assets = try container.decodeIfPresent([PartPackageAsset].self, forKey: .assets) ?? []
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
        missingPart = try container.decodeIfPresent(PartPackageMissingPart.self, forKey: .missingPart)
        requiresPHP = try container.decodeIfPresent(Bool.self, forKey: .requiresPHP) ?? false
        libraries = try container.decodeIfPresent(
            [PartPackageLibraryRequirement].self,
            forKey: .libraries
        ) ?? []
        updates = try container.decodeIfPresent(FoundryPackUpdateConfiguration.self, forKey: .updates)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minimumAPIVersion, forKey: .minimumAPIVersion)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(version, forKey: .version)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(showsInPartLibrary, forKey: .showsInPartLibrary)
        try container.encode(allowedParents, forKey: .allowedParents)
        try container.encode(controlsEntries, forKey: .controlsEntries)
        try container.encode(groups, forKey: .groups)
        try container.encode(render, forKey: .render)
        try container.encode(assets, forKey: .assets)
        try container.encodeIfPresent(helpURL, forKey: .helpURL)
        try container.encodeIfPresent(missingPart, forKey: .missingPart)
        try container.encode(requiresPHP, forKey: .requiresPHP)
        try container.encode(libraries, forKey: .libraries)
        try container.encodeIfPresent(updates, forKey: .updates)
    }
}

nonisolated struct PartPackageAsset: Codable, Equatable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable {
        case page
        case site
    }

    let path: String
    let scope: Scope

    init(path: String, scope: Scope = .page) {
        self.path = path
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            scope: try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .page
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        if scope != .page {
            try container.encode(scope, forKey: .scope)
        }
    }
}

/// Optional metadata for an Inspector section named by controls' `group` values.
/// `systemImage` sets the SF Symbol on the section's disclosure header; groups
/// without one use the generic fallback icon.
nonisolated struct PartPackageInspectorGroup: Codable, Hashable, Sendable {
    let name: String
    let systemImage: String?
}

extension PartPackageManifest {
    /// Standard/Framework properties in the exact order the manifest declared
    /// them, with each Grouped-control reference expanded in place.
    nonisolated var resolvedProperties: [PartPackageProperty] {
        controlsEntries.flatMap { entry in
            switch entry {
            case .property(let property): [property]
            case .group(let group): group.properties
            }
        }
    }

    /// The Grouped controls this manifest references, in declaration order.
    /// Position-preserving order lives in `controlsEntries`/`resolvedProperties`;
    /// this is just the set of groups, for CSS/HTML-contribution/lookup purposes.
    nonisolated var controlGroups: [PartPackageControlGroup] {
        controlsEntries.compactMap {
            if case .group(let group) = $0 { group } else { nil }
        }
    }

    /// Inspector section icons by group name: each declared Grouped control
    /// supplies its section's standard icon, and the manifest's `groups` array
    /// overrides or extends that for the part's own groups. Groups with no
    /// entry here render with the generic fallback icon.
    nonisolated var resolvedGroupIcons: [String: String] {
        var icons: [String: String] = [:]
        for group in controlGroups {
            icons[group.type.groupName] = group.type.groupSystemImage
        }
        for group in groups {
            if let systemImage = group.systemImage {
                icons[group.name] = systemImage
            }
        }
        return icons
    }

    nonisolated var controlGroupCSS: String {
        controlGroups.map(\.css).joined(separator: "\n")
    }

    nonisolated var htmlContributions: [PartPackageHTMLContribution] {
        render.htmlContributions + controlGroups.flatMap(\.htmlContributions)
    }

    nonisolated var slots: [PartPackageSlot] {
        resolvedProperties.compactMap(\.childSlot)
    }

    nonisolated func permits(parent type: PartType) -> Bool {
        allowedParents.isEmpty || allowedParents.contains(type.rawValue)
    }

    nonisolated func assetDeclaration(containing path: String) -> PartPackageAsset? {
        assets.first { asset in
            path == asset.path || path.hasPrefix(asset.path + "/")
        }
    }
}

nonisolated struct PartPackageControlGroup: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case background
        case spacing
        case sizing
        case borders
        case effects
        case layoutItem

        /// The Inspector section this Grouped control's properties live in, and
        /// the icon that section carries — the same metadata a part declares for
        /// its own groups through the manifest's `groups` array.
        var groupName: String {
            switch self {
            case .background: "Background"
            case .spacing: "Spacing"
            case .sizing: "Sizing"
            case .borders: "Borders"
            case .effects: "Effects"
            case .layoutItem: "Layout item"
            }
        }

        var groupSystemImage: String {
            switch self {
            case .background: "paintbrush.fill"
            case .spacing: "arrow.up.and.down.and.arrow.left.and.right"
            case .sizing: "arrow.up.left.and.arrow.down.right"
            case .borders: "square.dashed"
            case .effects: "sparkles"
            case .layoutItem: "square.on.square"
            }
        }
    }

    enum BackgroundStyle: String, Codable, CaseIterable, Hashable, Sendable {
        case colour
        case image
        case gradient
        case video

        var templateValue: String {
            self == .colour ? "color" : rawValue
        }
    }

    enum BackgroundState: String, Codable, CaseIterable, Hashable, Sendable {
        case staticState = "static"
        case hover
    }

    let type: Kind
    let styles: [BackgroundStyle]
    let states: [BackgroundState]
    /// Lets a part adjust a shared group's injected defaults (e.g. a
    /// different starting padding) without hand-declaring the whole group.
    /// Only meaningful for the non-`background` kinds.
    let defaultOverrides: [String: PartPackageValue]

    init(
        type: Kind,
        styles: [BackgroundStyle] = BackgroundStyle.allCases,
        states: [BackgroundState] = BackgroundState.allCases,
        defaultOverrides: [String: PartPackageValue] = [:]
    ) {
        self.type = type
        self.styles = styles
        self.states = states
        self.defaultOverrides = defaultOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case styles
        case states
        case defaultOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        styles = try container.decodeIfPresent([BackgroundStyle].self, forKey: .styles)
            ?? BackgroundStyle.allCases
        states = try container.decodeIfPresent([BackgroundState].self, forKey: .states)
            ?? BackgroundState.allCases
        defaultOverrides = try container.decodeIfPresent([String: PartPackageValue].self, forKey: .defaultOverrides) ?? [:]
    }

    var properties: [PartPackageProperty] {
        let base: [PartPackageProperty] = switch type {
        case .background:
            PartPackageProperty.backgroundControlGroup(
                styles: styles,
                includesHover: states.contains(.hover)
            )
        case .spacing: PartPackageProperty.spacingControlGroup
        case .sizing: PartPackageProperty.sizingControlGroup
        case .borders: PartPackageProperty.bordersControlGroup
        case .effects: PartPackageProperty.effectsControlGroup
        case .layoutItem: PartPackageProperty.layoutItemControlGroup
        }
        guard !defaultOverrides.isEmpty else { return base }
        return base.map { property in
            guard let override = defaultOverrides[property.id] else { return property }
            var property = property
            property.defaultValue = override
            return property
        }
    }

    var css: String {
        switch type {
        case .background:
            backgroundCSS
        case .spacing, .sizing, .borders, .effects, .layoutItem:
            ""
        }
    }

    var htmlContributions: [PartPackageHTMLContribution] {
        switch type {
        case .background:
            guard styles.contains(.video) else { return [] }
            var fragments = [
                #"{{ if control.backgroundMode != "none" }}{{ if control.backgroundStyle == "video" }}{{ if canvas }}{{ if control.backgroundVideo.poster != "" }}<img class="foundry-background-video" src="{{ control.backgroundVideo.poster | escapeHTMLAttribute }}" alt="" aria-hidden="true">{{ endif }}{{ else }}{{ if control.backgroundVideo != "" }}<video class="foundry-background-video" src="{{ control.backgroundVideo.href | escapeHTMLAttribute }}" poster="{{ control.backgroundVideo.poster | escapeHTMLAttribute }}" autoplay muted loop playsinline aria-hidden="true"></video>{{ endif }}{{ endif }}{{ endif }}{{ endif }}"#
            ]
            if states.contains(.hover) {
                fragments.append(
                    #"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "video" }}{{ if canvas }}{{ if control.backgroundHoverVideo.poster != "" }}<img class="foundry-background-video foundry-background-video--hover" src="{{ control.backgroundHoverVideo.poster | escapeHTMLAttribute }}" alt="" aria-hidden="true">{{ endif }}{{ else }}{{ if control.backgroundHoverVideo != "" }}<video class="foundry-background-video foundry-background-video--hover" src="{{ control.backgroundHoverVideo.href | escapeHTMLAttribute }}" poster="{{ control.backgroundHoverVideo.poster | escapeHTMLAttribute }}" autoplay muted loop playsinline aria-hidden="true"></video>{{ endif }}{{ endif }}{{ endif }}{{ endif }}"#
                )
            }
            return [.init(
                placement: .afterOpeningTag,
                template: fragments.joined(separator: "\n"),
                target: .controlGroupBackground
            )]
        case .spacing, .sizing, .borders, .effects, .layoutItem:
            return []
        }
    }

    private var backgroundCSS: String {
        let includesHover = states.contains(.hover)
        var base = ["background-color: transparent;", "background-image: none;"]
        if styles.contains(.colour) {
            base.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundStyle == "color" }}background-color: {{ control.backgroundColor }};{{ endif }}{{ endif }}"#)
        }
        if styles.contains(.image) {
            base.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundStyle == "image" }}background-image: url("{{ control.backgroundImage }}"); background-position: {{ control.backgroundPosition }}; background-size: {{ control.backgroundSize }}; background-repeat: {{ control.backgroundRepeat }};{{ endif }}{{ endif }}"#)
        }
        if styles.contains(.gradient) {
            base.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundStyle == "gradient" }}{{ if control.backgroundGradientType == "linear" }}background-image: linear-gradient({{ control.backgroundGradientDirection }}, {{ control.backgroundGradientFrom }} {{ control.backgroundGradientFromPosition }}%, {{ control.backgroundGradientTo }} {{ control.backgroundGradientToPosition }}%);{{ elseif control.backgroundGradientType == "radial" }}background-image: radial-gradient({{ control.backgroundGradientFrom }} {{ control.backgroundGradientFromPosition }}%, {{ control.backgroundGradientTo }} {{ control.backgroundGradientToPosition }}%);{{ else }}background-image: conic-gradient({{ control.backgroundGradientFrom }} {{ control.backgroundGradientFromPosition }}%, {{ control.backgroundGradientTo }} {{ control.backgroundGradientToPosition }}%);{{ endif }}{{ endif }}{{ endif }}"#)
        }
        if styles.contains(.video) {
            base.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundStyle == "video" }}position: relative; isolation: isolate; overflow: hidden;{{ if control.backgroundVideoAspectRatio }}aspect-ratio: 16 / 9;{{ endif }}{{ endif }}{{ endif }}"#)
            if includesHover {
                base.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "video" }}position: relative; isolation: isolate; overflow: hidden;{{ if control.backgroundHoverVideoAspectRatio }}aspect-ratio: 16 / 9;{{ endif }}{{ endif }}{{ endif }}"#)
            }
        }
        let target = #"[data-foundry-control-group-background="{{ instance.id }}"]"#
        var output = target + " {\n    " + base.joined(separator: "\n    ") + "\n}"
        if includesHover {
            var hover: [String] = []
            if styles.contains(.colour) {
                hover.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "color" }}background-color: {{ control.backgroundHoverColor }}; background-image: none;{{ endif }}{{ endif }}"#)
            }
            if styles.contains(.image) {
                hover.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "image" }}background-color: transparent; background-image: url("{{ control.backgroundHoverImage }}"); background-position: {{ control.backgroundHoverPosition }}; background-size: {{ control.backgroundHoverSize }}; background-repeat: {{ control.backgroundHoverRepeat }};{{ endif }}{{ endif }}"#)
            }
            if styles.contains(.gradient) {
                hover.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "gradient" }}background-color: transparent;{{ if control.backgroundHoverGradientType == "linear" }}background-image: linear-gradient({{ control.backgroundHoverGradientDirection }}, {{ control.backgroundHoverGradientFrom }} {{ control.backgroundHoverGradientFromPosition }}%, {{ control.backgroundHoverGradientTo }} {{ control.backgroundHoverGradientToPosition }}%);{{ elseif control.backgroundHoverGradientType == "radial" }}background-image: radial-gradient({{ control.backgroundHoverGradientFrom }} {{ control.backgroundHoverGradientFromPosition }}%, {{ control.backgroundHoverGradientTo }} {{ control.backgroundHoverGradientToPosition }}%);{{ else }}background-image: conic-gradient({{ control.backgroundHoverGradientFrom }} {{ control.backgroundHoverGradientFromPosition }}%, {{ control.backgroundHoverGradientTo }} {{ control.backgroundHoverGradientToPosition }}%);{{ endif }}{{ endif }}{{ endif }}"#)
            }
            if styles.contains(.video) {
                hover.append(#"{{ if control.backgroundMode != "none" }}{{ if control.backgroundHoverStyle == "video" }}background-color: transparent; background-image: none;{{ endif }}{{ endif }}"#)
            }
            output += "\n" + target + ":hover {\n    " + hover.joined(separator: "\n    ") + "\n}"
        }
        if styles.contains(.video) {
            output += "\n" + target + " > .foundry-background-video { position: absolute; inset: 0; z-index: -1; width: 100%; height: 100%; object-fit: cover; pointer-events: none; }"
            if includesHover {
                output += "\n" + target + " > .foundry-background-video--hover { opacity: 0; }"
                output += "\n" + target + ":hover > .foundry-background-video--hover { opacity: 1; }"
            }
        }
        return output
    }
}

nonisolated enum PartPackageHTMLContributionRenderer {
    static func decorate(
        _ html: String,
        contributions: [PartPackageHTMLContribution],
        context: PartTemplateContext
    ) -> String {
        var output = html
        for contribution in contributions {
            let fragment = PartTemplateRenderer.render(contribution.template, context: context)
            guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            switch contribution.placement {
            case .afterOpeningTag:
                guard let index = openingTagEnd(in: output, target: contribution.target, context: context) else { continue }
                output.insert(contentsOf: fragment, at: output.index(after: index))
            case .beforeClosingTag:
                guard contribution.target == .root else { continue }
                guard let range = output.range(of: "</", options: .backwards) else { continue }
                output.insert(contentsOf: fragment, at: range.lowerBound)
            }
        }
        return output
    }

    private static func openingTagEnd(
        in html: String,
        target: PartPackageHTMLContribution.Target,
        context: PartTemplateContext
    ) -> String.Index? {
        switch target {
        case .root:
            return html.firstIndex(of: ">")
        case .controlGroupBackground:
            let attribute = #"data-foundry-control-group-background="\#(context.instanceID.uuidString)""#
            guard let attributeRange = html.range(of: attribute) else { return nil }
            return html[attributeRange.upperBound...].firstIndex(of: ">")
        }
    }
}

nonisolated struct PartPackageHTMLContribution: Codable, Equatable, Sendable {
    enum Placement: String, Codable, Sendable {
        case afterOpeningTag
        case beforeClosingTag
    }

    enum Target: Equatable, Sendable {
        case root
        case controlGroupBackground
    }

    let placement: Placement
    let template: String
    let target: Target

    init(placement: Placement, template: String, target: Target = .root) {
        self.placement = placement
        self.template = template
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case template
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placement = try container.decode(Placement.self, forKey: .placement)
        template = try container.decode(String.self, forKey: .template)
        target = .root
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(template, forKey: .template)
    }
}

nonisolated struct PartPackageLibraryRequirement: Codable, Equatable, Hashable, Sendable {
    let identifier: String
    let majorVersion: Int

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case majorVersion
    }
}

nonisolated struct PartPackageSlot: Equatable, Identifiable, Sendable {
    enum Containment: String, Codable, Sendable {
        case open
        case locked
    }

    let id: String
    let title: String
    let accepts: [String]
    let pickerItems: [String]
    let initial: [String]
    let minimum: Int
    let maximum: Int?
    let containment: Containment
    let group: String
    let tooltip: String?
    let visibleWhen: PartPackageVisibilityCondition?

    init(
        id: String,
        title: String,
        accepts: [String],
        pickerItems: [String] = [],
        initial: [String] = [],
        minimum: Int,
        maximum: Int? = nil,
        containment: Containment = .open,
        group: String = "Settings",
        tooltip: String? = nil,
        visibleWhen: PartPackageVisibilityCondition? = nil
    ) {
        self.id = id
        self.title = title
        self.accepts = accepts
        self.pickerItems = pickerItems
        self.initial = initial
        self.minimum = minimum
        self.maximum = maximum
        self.containment = containment
        self.group = group
        self.tooltip = tooltip
        self.visibleWhen = visibleWhen
    }
}

nonisolated struct PartPackageImageRendition: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let maximumDimension: Int

    var effectiveMaximumDimension: Int {
        min(maximumDimension, PartImageProcessor.canonicalMaximumDimension)
    }
}

nonisolated struct PartPackageProperty: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let noteTitle: String?
    let noteBody: String
    let noteSystemImage: String?
    let group: String
    let control: PartPackageControl
    var defaultValue: PartPackageValue
    var breakpointDefaults: [String: PartPackageValue] = [:]
    let responsive: Bool
    let subtitles: [String]
    let buttonTexts: [String]
    let buttonIcons: [String]
    let activeButtonTexts: [String]
    let activeButtonIcons: [String]
    let units: [String]
    let tooltip: String?
    let visibleWhen: PartPackageVisibilityCondition?
    let alt: String
    let focalPoint: Bool
    let renditions: [PartPackageImageRendition]
    let accepts: [String]
    let pickerItems: [String]
    let initial: [String]
    let containment: PartPackageSlot.Containment

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case title
        case body
        case systemImage
        case group
        case defaultValue = "defaults"
        case responsive
        case subtitle
        case buttonText
        case buttonIcon
        case activeButtonText
        case activeButtonIcon
        case units
        case tooltip
        case visibleWhen
        case alt
        case focalPoint
        case renditions
        case accepts
        case pickerItems
        case initial
        case containment
    }

    init(
        id: String,
        label: String,
        group: String,
        control: PartPackageControl,
        defaultValue: PartPackageValue,
        responsive: Bool,
        visibleWhen: PartPackageVisibilityCondition? = nil,
        tooltip: String? = nil,
        units: [String] = [""]
    ) {
        self.id = id
        self.label = label
        noteTitle = nil
        noteBody = ""
        noteSystemImage = nil
        self.group = group
        self.control = control
        self.defaultValue = defaultValue
        breakpointDefaults = [:]
        self.responsive = responsive
        subtitles = []
        buttonTexts = []
        buttonIcons = []
        activeButtonTexts = []
        activeButtonIcons = []
        self.units = units
        self.tooltip = tooltip
        self.visibleWhen = visibleWhen
        alt = ""
        focalPoint = false
        renditions = []
        accepts = []
        pickerItems = []
        initial = []
        containment = .open
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "Settings"
        control = try PartPackageControl(from: decoder)
        tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        visibleWhen = try container.decodeIfPresent(PartPackageVisibilityCondition.self, forKey: .visibleWhen)
        alt = try container.decodeIfPresent(String.self, forKey: .alt) ?? ""
        focalPoint = try container.decodeIfPresent(Bool.self, forKey: .focalPoint) ?? false
        renditions = try container.decodeIfPresent([PartPackageImageRendition].self, forKey: .renditions) ?? []
        let declaredAccepts = try container.decodeIfPresent([String].self, forKey: .accepts)
        let declaredPickerItems = try container.decodeIfPresent([String].self, forKey: .pickerItems)
        pickerItems = declaredPickerItems ?? []
        accepts = declaredAccepts ?? pickerItems
        initial = try container.decodeIfPresent([String].self, forKey: .initial) ?? []
        containment = try container.decodeIfPresent(PartPackageSlot.Containment.self, forKey: .containment) ?? .open

        if control.count != nil {
            subtitles = try container.decodeIfPresent([String].self, forKey: .subtitle) ?? []
            buttonTexts = try container.decodeIfPresent([String].self, forKey: .buttonText) ?? []
            buttonIcons = try container.decodeIfPresent([String].self, forKey: .buttonIcon) ?? []
            activeButtonTexts = try container.decodeIfPresent([String].self, forKey: .activeButtonText) ?? []
            activeButtonIcons = try container.decodeIfPresent([String].self, forKey: .activeButtonIcon) ?? []
            units = try container.decodeIfPresent([String].self, forKey: .units) ?? []
        } else {
            subtitles = try container.decodeIfPresent(String.self, forKey: .subtitle).map { [$0] } ?? []
            buttonTexts = try container.decodeIfPresent(String.self, forKey: .buttonText).map { [$0] } ?? []
            buttonIcons = try container.decodeIfPresent(String.self, forKey: .buttonIcon).map { [$0] } ?? []
            activeButtonTexts = try container.decodeIfPresent(String.self, forKey: .activeButtonText).map { [$0] } ?? []
            activeButtonIcons = try container.decodeIfPresent(String.self, forKey: .activeButtonIcon).map { [$0] } ?? []
            if control.type == .edges || control.type == .corners {
                // The unit menu is a list even without count.
                units = try container.decodeIfPresent([String].self, forKey: .units) ?? []
            } else {
                units = [try container.decodeIfPresent(String.self, forKey: .units) ?? ""]
            }
        }
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        noteTitle = control.type == .note
            ? try container.decodeIfPresent(String.self, forKey: .title)
            : nil
        noteBody = control.type == .note
            ? try container.decode(String.self, forKey: .body)
            : ""
        noteSystemImage = control.type == .note
            ? try container.decodeIfPresent(String.self, forKey: .systemImage)
            : nil

        let defaults = try container.decodeIfPresent([String: PartPackageValue].self, forKey: .defaultValue)
        if let defaults {
            guard defaults["base"] != nil else { throw DecodingError.dataCorruptedError(forKey: .defaultValue, in: container, debugDescription: "defaults.base is required") }
            breakpointDefaults = defaults.filter { $0.key != "base" }
        }
        if control.type == .divider || control.type == .note || control.type == .image || control.type == .video || control.type == .math || control.type == .childPicker {
            defaultValue = defaults?["base"] ?? .string("")
            if control.type == .video {
                responsive = false
            } else {
                responsive = control.type == .image && focalPoint
                    ? true
                    : try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
            }
        } else {
            guard let base = defaults?["base"] else { throw DecodingError.keyNotFound(CodingKeys.defaultValue, .init(codingPath: decoder.codingPath, debugDescription: "defaults.base is required")) }
            defaultValue = base
            responsive = try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        }
    }

    func encode(to encoder: Encoder) throws {
        try control.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if control.count != nil || control.type == .edges || control.type == .corners {
            if !units.isEmpty {
                try container.encode(units, forKey: .units)
            }
        } else {
            if let unit = units.first, !unit.isEmpty {
                try container.encode(unit, forKey: .units)
            }
        }
        if control.type != .note, !label.isEmpty {
            try container.encode(label, forKey: .label)
        }
        if control.type == .note {
            try container.encodeIfPresent(noteTitle, forKey: .title)
            try container.encode(noteBody, forKey: .body)
            try container.encodeIfPresent(noteSystemImage, forKey: .systemImage)
        }
        try container.encode(group, forKey: .group)
        if ![.note, .divider, .math, .childPicker].contains(control.type) {
            try container.encode(breakpointDefaults.merging(["base": defaultValue]) { _, base in base }, forKey: .defaultValue)
            if control.type != .video {
                try container.encode(responsive, forKey: .responsive)
            }
        }
        if control.type != .note, control.count != nil, !subtitles.isEmpty {
            try container.encode(subtitles, forKey: .subtitle)
        } else if control.type != .note, let subtitle = subtitles.first, !subtitle.isEmpty {
            try container.encode(subtitle, forKey: .subtitle)
        }
        if control.count != nil, !buttonTexts.isEmpty {
            try container.encode(buttonTexts, forKey: .buttonText)
        } else if let buttonText = buttonTexts.first, !buttonText.isEmpty {
            try container.encode(buttonText, forKey: .buttonText)
        }
        if control.count != nil {
            if !buttonIcons.isEmpty { try container.encode(buttonIcons, forKey: .buttonIcon) }
            if !activeButtonTexts.isEmpty { try container.encode(activeButtonTexts, forKey: .activeButtonText) }
            if !activeButtonIcons.isEmpty { try container.encode(activeButtonIcons, forKey: .activeButtonIcon) }
        } else {
            if let value = buttonIcons.first, !value.isEmpty { try container.encode(value, forKey: .buttonIcon) }
            if let value = activeButtonTexts.first, !value.isEmpty { try container.encode(value, forKey: .activeButtonText) }
            if let value = activeButtonIcons.first, !value.isEmpty { try container.encode(value, forKey: .activeButtonIcon) }
        }
        try container.encodeIfPresent(tooltip, forKey: .tooltip)
        try container.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        if control.type == .image, !alt.isEmpty {
            try container.encode(alt, forKey: .alt)
        }
        if control.type == .image, focalPoint {
            try container.encode(true, forKey: .focalPoint)
        }
        if control.type == .image, !renditions.isEmpty {
            try container.encode(renditions, forKey: .renditions)
        }
        if control.type == .childPicker {
            try container.encode(pickerItems, forKey: .pickerItems)
            if accepts != pickerItems { try container.encode(accepts, forKey: .accepts) }
            if !initial.isEmpty { try container.encode(initial, forKey: .initial) }
            if containment != .open { try container.encode(containment, forKey: .containment) }
        }
    }

    var childSlot: PartPackageSlot? {
        guard control.type == .childPicker else { return nil }
        return .init(
            id: id,
            title: label.isEmpty ? id : label,
            accepts: accepts,
            pickerItems: pickerItems,
            initial: initial,
            minimum: Int(control.minimum ?? 0),
            maximum: control.maximum.map(Int.init),
            containment: containment,
            group: group,
            tooltip: tooltip,
            visibleWhen: visibleWhen
        )
    }
}

nonisolated extension PartPackageProperty {
    private static func backgroundVisibility(
        mode: String,
        style: String? = nil,
        extra: PartPackageVisibilityCondition? = nil
    ) -> PartPackageVisibilityCondition {
        var conditions = [PartPackageVisibilityCondition(id: "backgroundMode", value: .string(mode))]
        if let style {
            let styleKey = mode == "hover" ? "backgroundHoverStyle" : "backgroundStyle"
            conditions.append(.init(id: styleKey, value: .string(style)))
        }
        if let extra { conditions.append(extra) }
        return .init(all: conditions)
    }

    private static func backgroundStyleControl(
        styles: [PartPackageControlGroup.BackgroundStyle] = PartPackageControlGroup.BackgroundStyle.allCases,
        includesNone: Bool = false
    ) -> PartPackageControl {
        var options: [PartPackageOption] = []
        if includesNone { options.append(.init(value: "none", title: "None")) }
        let available: [PartPackageControlGroup.BackgroundStyle: PartPackageOption] = [
            .colour: .init(value: "color", title: "Colour", systemImage: "paintbrush.fill"),
            .image: .init(value: "image", title: "Image", systemImage: "photo"),
            .gradient: .init(value: "gradient", title: "Gradient", systemImage: "circle.lefthalf.filled"),
            .video: .init(value: "video", title: "Video", systemImage: "video.fill")
        ]
        options += styles.compactMap { available[$0] }
        return .init(type: .select, options: options, presentation: .segmented)
    }

    static func backgroundControlGroup(
        styles: [PartPackageControlGroup.BackgroundStyle],
        includesHover: Bool
    ) -> [Self] {
        let defaultStyle = styles.first?.templateValue ?? "color"
        var modeOptions = [("none", "None"), ("static", "Static")]
        if includesHover { modeOptions.append(("hover", "Hover")) }
        let mode = Self(
            id: "backgroundMode",
            label: "Type",
            group: "Background",
            control: .select(modeOptions, presentation: .segmented),
            defaultValue: .string("none"),
            responsive: false
        )
        let style = Self(
            id: "backgroundStyle",
            label: "Style",
            group: "Background",
            control: backgroundStyleControl(styles: styles),
            defaultValue: .string(defaultStyle),
            responsive: false,
            visibleWhen: backgroundVisibility(mode: "static")
        )
        let staticProperties = backgroundStaticControlGroup.dropFirst(2).filter {
            backgroundStyle(for: $0.id).map(styles.contains) ?? true
        }
        guard includesHover else { return [mode, style] + staticProperties }
        let hoverStyle = Self(
            id: "backgroundHoverStyle",
            label: "Style",
            group: "Background",
            control: backgroundStyleControl(styles: styles, includesNone: true),
            defaultValue: .string("none"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "hover")
        )
        let hoverProperties = backgroundHoverControlGroup.dropFirst().filter {
            backgroundStyle(for: $0.id).map(styles.contains) ?? true
        }
        return [mode, style] + staticProperties + [hoverStyle] + hoverProperties
    }

    private static func backgroundStyle(
        for propertyID: String
    ) -> PartPackageControlGroup.BackgroundStyle? {
        if propertyID.contains("Gradient") { return .gradient }
        if propertyID.contains("Video") { return .video }
        if propertyID == "backgroundColor" || propertyID == "backgroundHoverColor" { return .colour }
        if [
            "backgroundImage", "backgroundPosition", "backgroundSize", "backgroundRepeat",
            "backgroundHoverImage", "backgroundHoverPosition", "backgroundHoverSize", "backgroundHoverRepeat"
        ].contains(propertyID) { return .image }
        return nil
    }

    private static let backgroundStaticControlGroup: [Self] = [
        Self(
            id: "backgroundMode",
            label: "Type",
            group: "Background",
            control: .select([
                ("none", "None"),
                ("static", "Static"),
                ("hover", "Hover")
            ], presentation: .segmented),
            defaultValue: .string("none"),
            responsive: false
        ),
        Self(
            id: "backgroundStyle",
            label: "Style",
            group: "Background",
            control: backgroundStyleControl(),
            defaultValue: .string("color"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static")
        ),
        Self(
            id: "backgroundColor",
            label: "Colour",
            group: "Background",
            control: .init(type: .frameworkColor, allowsCustom: true, opacity: true),
            defaultValue: .object(["palette": .string("surface")]),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "color")
        ),
        Self(
            id: "backgroundImage",
            label: "Image",
            group: "Background",
            control: .init(type: .image),
            defaultValue: .string(""),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "image")
        ),
        Self(
            id: "backgroundPosition",
            label: "Position",
            group: "Background",
            control: .select([
                ("center", "Centre"), ("top", "Top"), ("right", "Right"),
                ("bottom", "Bottom"), ("left", "Left"),
                ("left top", "Top left"), ("right top", "Top right"),
                ("left bottom", "Bottom left"), ("right bottom", "Bottom right")
            ]),
            defaultValue: .string("center"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "image")
        ),
        Self(
            id: "backgroundSize",
            label: "Size",
            group: "Background",
            control: .select([("cover", "Cover"), ("contain", "Contain"), ("auto", "Auto")]),
            defaultValue: .string("cover"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "image")
        ),
        Self(
            id: "backgroundRepeat",
            label: "Repeat",
            group: "Background",
            control: .select([
                ("no-repeat", "No repeat"), ("repeat", "Repeat"),
                ("repeat-x", "Repeat horizontally"), ("repeat-y", "Repeat vertically"),
                ("space", "Space"), ("round", "Round")
            ]),
            defaultValue: .string("no-repeat"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "image")
        ),
        Self(
            id: "backgroundGradientType",
            label: "Type",
            group: "Background",
            control: .select([("linear", "Linear"), ("radial", "Radial"), ("conic", "Conic")], presentation: .segmented),
            defaultValue: .string("linear"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient")
        ),
        Self(
            id: "backgroundGradientDirection",
            label: "Direction",
            group: "Background",
            control: .select([
                ("to bottom", "To bottom"), ("to top", "To top"),
                ("to right", "To right"), ("to left", "To left"),
                ("to bottom right", "To bottom right"), ("to bottom left", "To bottom left"),
                ("to top right", "To top right"), ("to top left", "To top left")
            ]),
            defaultValue: .string("to bottom"),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient", extra: .init(id: "backgroundGradientType", value: .string("linear")))
        ),
        Self(
            id: "backgroundGradientFrom",
            label: "From colour",
            group: "Background",
            control: .init(type: .frameworkColor, allowsCustom: true, opacity: true),
            defaultValue: .object(["palette": .string("surface")]),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient")
        ),
        Self(
            id: "backgroundGradientFromPosition",
            label: "From position",
            group: "Background",
            control: .init(type: .slider, minimum: 0, maximum: 100, step: 1, showsValueField: true),
            defaultValue: .number(0),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient")
        ),
        Self(
            id: "backgroundGradientTo",
            label: "To colour",
            group: "Background",
            control: .init(type: .frameworkColor, allowsCustom: true, opacity: true),
            defaultValue: .object(["palette": .string("accent")]),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient")
        ),
        Self(
            id: "backgroundGradientToPosition",
            label: "To position",
            group: "Background",
            control: .init(type: .slider, minimum: 0, maximum: 100, step: 1, showsValueField: true),
            defaultValue: .number(100),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "gradient")
        ),
        Self(
            id: "backgroundVideo",
            label: "Video",
            group: "Background",
            control: .init(type: .video),
            defaultValue: .string(""),
            responsive: false,
            visibleWhen: backgroundVisibility(mode: "static", style: "video"),
            tooltip: "Choose a video from project resources. Background video is muted, loops, and does not capture pointer events."
        ),
        Self(
            id: "backgroundVideoAspectRatio",
            label: "Force 16:9 aspect ratio",
            group: "Background",
            control: .init(type: .toggle),
            defaultValue: .boolean(false),
            responsive: true,
            visibleWhen: backgroundVisibility(mode: "static", style: "video")
        )
    ]

    private static let backgroundHoverControlGroup: [Self] = [
        Self(id: "backgroundHoverStyle", label: "Style", group: "Background", control: backgroundStyleControl(includesNone: true), defaultValue: .string("none"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover")),
        Self(id: "backgroundHoverColor", label: "Colour", group: "Background", control: .init(type: .frameworkColor, allowsCustom: true, opacity: true), defaultValue: .object(["palette": .string("surface")]), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "color")),
        Self(id: "backgroundHoverImage", label: "Image", group: "Background", control: .init(type: .image), defaultValue: .string(""), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "image")),
        Self(id: "backgroundHoverPosition", label: "Position", group: "Background", control: .select([("center", "Centre"), ("top", "Top"), ("right", "Right"), ("bottom", "Bottom"), ("left", "Left"), ("left top", "Top left"), ("right top", "Top right"), ("left bottom", "Bottom left"), ("right bottom", "Bottom right")]), defaultValue: .string("center"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "image")),
        Self(id: "backgroundHoverSize", label: "Size", group: "Background", control: .select([("cover", "Cover"), ("contain", "Contain"), ("auto", "Auto")]), defaultValue: .string("cover"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "image")),
        Self(id: "backgroundHoverRepeat", label: "Repeat", group: "Background", control: .select([("no-repeat", "No repeat"), ("repeat", "Repeat"), ("repeat-x", "Repeat horizontally"), ("repeat-y", "Repeat vertically"), ("space", "Space"), ("round", "Round")]), defaultValue: .string("no-repeat"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "image")),
        Self(id: "backgroundHoverGradientType", label: "Type", group: "Background", control: .select([("linear", "Linear"), ("radial", "Radial"), ("conic", "Conic")], presentation: .segmented), defaultValue: .string("linear"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient")),
        Self(id: "backgroundHoverGradientDirection", label: "Direction", group: "Background", control: .select([("to bottom", "To bottom"), ("to top", "To top"), ("to right", "To right"), ("to left", "To left"), ("to bottom right", "To bottom right"), ("to bottom left", "To bottom left"), ("to top right", "To top right"), ("to top left", "To top left")]), defaultValue: .string("to bottom"), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient", extra: .init(id: "backgroundHoverGradientType", value: .string("linear")))),
        Self(id: "backgroundHoverGradientFrom", label: "From colour", group: "Background", control: .init(type: .frameworkColor, allowsCustom: true, opacity: true), defaultValue: .object(["palette": .string("surface")]), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient")),
        Self(id: "backgroundHoverGradientFromPosition", label: "From position", group: "Background", control: .init(type: .slider, minimum: 0, maximum: 100, step: 1, showsValueField: true), defaultValue: .number(0), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient")),
        Self(id: "backgroundHoverGradientTo", label: "To colour", group: "Background", control: .init(type: .frameworkColor, allowsCustom: true, opacity: true), defaultValue: .object(["palette": .string("accent")]), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient")),
        Self(id: "backgroundHoverGradientToPosition", label: "To position", group: "Background", control: .init(type: .slider, minimum: 0, maximum: 100, step: 1, showsValueField: true), defaultValue: .number(100), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "gradient")),
        Self(id: "backgroundHoverVideo", label: "Video", group: "Background", control: .init(type: .video), defaultValue: .string(""), responsive: false, visibleWhen: backgroundVisibility(mode: "hover", style: "video"), tooltip: "Choose a video from project resources."),
        Self(id: "backgroundHoverVideoAspectRatio", label: "Force 16:9 aspect ratio", group: "Background", control: .init(type: .toggle), defaultValue: .boolean(false), responsive: true, visibleWhen: backgroundVisibility(mode: "hover", style: "video"))
    ]

    private static func visibleWhenEnabled(_ id: String) -> PartPackageVisibilityCondition {
        .init(id: id, value: .boolean(true))
    }

    static let sizingControlGroup: [Self] = [
        Self(id: "widthMode", label: "Width", group: "Sizing", control: .select([("full", "Fill parent"), ("auto", "Fit content"), ("custom", "Custom")]), defaultValue: .string("full"), responsive: true),
        Self(id: "customWidth", label: "Custom width", group: "Sizing", control: .init(type: .number, minimum: 0, maximum: 10_000, step: 1), defaultValue: .number(320), responsive: true, visibleWhen: .init(id: "widthMode", value: .string("custom")), units: ["px"]),
        Self(id: "maxWidth", label: "Maximum width", group: "Sizing", control: .init(type: .number, minimum: 0, maximum: 10_000, step: 1), defaultValue: .number(0), responsive: true, tooltip: "Zero removes the width limit. Never exceeds the available parent width.", units: ["px"]),
        Self(id: "minimumHeight", label: "Minimum height", group: "Sizing", control: .init(type: .number, minimum: 0, maximum: 10_000, step: 1), defaultValue: .number(0), responsive: true, units: ["px"]),
        Self(id: "heightMode", label: "Height", group: "Sizing", control: .select([("auto", "Fit content"), ("viewport", "Fill viewport"), ("custom", "Custom")]), defaultValue: .string("auto"), responsive: true),
        Self(id: "customHeight", label: "Custom height", group: "Sizing", control: .init(type: .number, minimum: 0, maximum: 10_000, step: 1), defaultValue: .number(400), responsive: true, visibleWhen: .init(id: "heightMode", value: .string("custom")), units: ["px"])
    ]

    static let layoutItemControlGroup: [Self] = [
        Self(id: "itemEnabled", label: "Enable", group: "Layout item", control: .init(type: .toggle), defaultValue: .boolean(false), responsive: true),
        Self(id: "flexGrow", label: "Grow", group: "Layout item", control: .init(type: .number, minimum: 0, maximum: 10, step: 1), defaultValue: .number(0), responsive: true, visibleWhen: visibleWhenEnabled("itemEnabled"), tooltip: "Flex parent: share remaining space. Zero keeps the natural size."),
        Self(id: "flexShrink", label: "Shrink", group: "Layout item", control: .init(type: .number, minimum: 0, maximum: 10, step: 1), defaultValue: .number(1), responsive: true, visibleWhen: visibleWhenEnabled("itemEnabled"), tooltip: "Flex parent: allow this item to shrink. Zero prevents shrinking."),
        Self(id: "alignSelf", label: "Alignment", group: "Layout item", control: .select([("auto", "Follow parent"), ("stretch", "Stretch"), ("flex-start", "Start"), ("center", "Centre"), ("flex-end", "End"), ("baseline", "Baseline")]), defaultValue: .string("auto"), responsive: true, visibleWhen: visibleWhenEnabled("itemEnabled")),
        Self(id: "columnSpan", label: "Column span", group: "Layout item", control: .init(type: .number, minimum: 1, maximum: 12, step: 1), defaultValue: .number(1), responsive: true, visibleWhen: visibleWhenEnabled("itemEnabled"), tooltip: "Grid parent only. Keep within the parent's column count at this breakpoint."),
        Self(id: "rowSpan", label: "Row span", group: "Layout item", control: .init(type: .number, minimum: 1, maximum: 12, step: 1), defaultValue: .number(1), responsive: true, visibleWhen: visibleWhenEnabled("itemEnabled"), tooltip: "Grid parent only.")
    ]

    static let spacingControlGroup: [Self] = [
        Self(id: "spacingEnabled", label: "Enable", group: "Spacing", control: .init(type: .toggle), defaultValue: .boolean(true), responsive: true),
        Self(id: "frameworkPadding", label: "Padding", group: "Spacing", control: .init(type: .frameworkPadding), defaultValue: .string("none"), responsive: true, visibleWhen: visibleWhenEnabled("spacingEnabled")),
        Self(id: "frameworkMargin", label: "Margin", group: "Spacing", control: .init(type: .frameworkMargin), defaultValue: .string("none"), responsive: true, visibleWhen: visibleWhenEnabled("spacingEnabled"))
    ]

    static let bordersControlGroup: [Self] = [
        Self(id: "borderEnabled", label: "Enable", group: "Borders", control: .init(type: .toggle), defaultValue: .boolean(false), responsive: true),
        Self(id: "frameworkBorder", label: "Border", group: "Borders", control: .init(type: .frameworkBorder, showsStyle: true), defaultValue: .object(["width": .string("none"), "style": .string("solid")]), responsive: true, visibleWhen: visibleWhenEnabled("borderEnabled")),
        Self(id: "frameworkBorderColour", label: "Colour", group: "Borders", control: .init(type: .frameworkColor, allowsCustom: true, opacity: true), defaultValue: .object(["palette": .string("muted-text")]), responsive: true, visibleWhen: visibleWhenEnabled("borderEnabled")),
        Self(id: "frameworkRadius", label: "Radius", group: "Borders", control: .init(type: .frameworkRadius), defaultValue: .string("none"), responsive: true, visibleWhen: visibleWhenEnabled("borderEnabled"))
    ]

    static let effectsControlGroup: [Self] = [
        Self(id: "effectsEnabled", label: "Enable", group: "Effects", control: .init(type: .toggle), defaultValue: .boolean(false), responsive: true),
        Self(id: "frameworkShadow", label: "Shadow", group: "Effects", control: .init(type: .frameworkShadow), defaultValue: .string("none"), responsive: true, visibleWhen: visibleWhenEnabled("effectsEnabled")),
        Self(id: "opacity", label: "Opacity", group: "Effects", control: .init(type: .slider, minimum: 0, maximum: 100, step: 1, showsValueField: true), defaultValue: .number(100), responsive: true, visibleWhen: visibleWhenEnabled("effectsEnabled"), units: ["%"])
    ]
}

nonisolated struct PartPackageVisibilityCondition: Codable, Equatable, Sendable {
    let id: String?
    let operation: String
    let value: PartPackageValue?
    let all: [Self]?
    let any: [Self]?

    enum CodingKeys: String, CodingKey {
        case id
        case operation
        case value
        case all
        case any
    }

    init(id: String, operation: String = "==", value: PartPackageValue? = nil) {
        self.id = id
        self.operation = operation
        self.value = value
        all = nil
        any = nil
    }

    init(all: [Self]) {
        id = nil
        operation = "=="
        value = nil
        self.all = all
        any = nil
    }

    init(any: [Self]) {
        id = nil
        operation = "=="
        value = nil
        all = nil
        self.any = any
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "=="
        value = try container.decodeIfPresent(PartPackageValue.self, forKey: .value)
        all = try container.decodeIfPresent([Self].self, forKey: .all)
        any = try container.decodeIfPresent([Self].self, forKey: .any)
    }
}

nonisolated struct PartPackageControl: Codable, Equatable, Sendable {
    enum SelectPresentation: String, Codable, Sendable {
        case menu
        case segmented
    }
    enum ButtonSelectionMode: String, Codable, Sendable {
        case multiple
        case single
    }

    enum ColorOutputFormat: String, Codable, CaseIterable, Sendable {
        case hex
        case hexValue
        case rgb
        case rgba
        case rgbValues
        case rgbaValues
        case hsl
        case hsla
        case hslValues
        case hslaValues
    }

    enum Kind: String, Codable, Sendable {
        case text
        case textArea
        case number
        case color
        case frameworkColor
        case frameworkFont
        case frameworkBorder
    case frameworkRadius
    case frameworkMargin
    case frameworkSpacing
    case frameworkPadding
        case edges
        case corners
        case fontWeight
        case fontStyle
        case icon
        case select
        case link
        case toggle
        case textAlignment
        case divider
        case slider
        case date
        case note
        case button
        case image
        case video
        case math
        case frameworkShadow
        case childPicker
    }

    let type: Kind
    let font: String?
    let showsFamily: Bool?
    let showsWeight: Bool?
    let showsStyle: Bool?
    let minimum: Double?
    let maximum: Double?
    let minimumDate: String?
    let maximumDate: String?
    let step: Double?
    let options: [PartPackageOption]?
    let frameworkValues: PartPackageFrameworkValues?
    let allowsCustom: Bool?
    let opacity: Bool?
    let outputFormat: ColorOutputFormat?
    let customColor: String?
    let count: Int?
    let ticks: Int?
    let showsValueField: Bool?
    let trueValue: PartPackageValue?
    let falseValue: PartPackageValue?
    let selectionMode: ButtonSelectionMode?
    let argument1: PartPackageValue?
    let argument2: PartPackageValue?
    let operation: String?
    let round: Bool?
    let absoluteURL: Bool?
    let presentation: SelectPresentation?
    /// Explicit starting link state for edges/corners controls; nil infers it from
    /// whether the declared edge defaults are all equal.
    let linked: Bool?

    enum CodingKeys: String, CodingKey {
        case type, font, minimum, maximum, step, options, frameworkValues, allowsCustom
        case showsFamily, showsWeight, showsStyle
        case opacity, outputFormat, customColor, count, ticks, showsValueField
        case trueValue, falseValue, selectionMode, argument1, argument2, operation, round, absoluteURL, presentation, linked
    }

    init(
        type: Kind,
        minimum: Double? = nil,
        maximum: Double? = nil,
        step: Double? = nil,
        options: [PartPackageOption]? = nil,
        allowsCustom: Bool? = nil,
        opacity: Bool? = nil,
        showsValueField: Bool? = nil,
        absoluteURL: Bool? = nil,
        presentation: SelectPresentation? = nil,
        showsStyle: Bool? = nil
    ) {
        self.type = type
        font = nil
        showsFamily = nil
        showsWeight = nil
        self.showsStyle = showsStyle
        self.minimum = minimum
        self.maximum = maximum
        minimumDate = nil
        maximumDate = nil
        self.step = step
        self.options = options
        frameworkValues = nil
        self.allowsCustom = allowsCustom
        self.opacity = opacity
        outputFormat = nil
        customColor = nil
        count = nil
        ticks = nil
        self.showsValueField = showsValueField
        trueValue = nil
        falseValue = nil
        selectionMode = nil
        argument1 = nil
        argument2 = nil
        operation = nil
        round = nil
        self.absoluteURL = absoluteURL
        self.presentation = presentation
        linked = nil
    }

    static func select(_ options: [(String, String)], presentation: SelectPresentation? = nil) -> Self {
        Self(type: .select, options: options.map { PartPackageOption(value: $0.0, title: $0.1) }, presentation: presentation)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        font = try container.decodeIfPresent(String.self, forKey: .font)
        showsFamily = try container.decodeIfPresent(Bool.self, forKey: .showsFamily)
        showsWeight = try container.decodeIfPresent(Bool.self, forKey: .showsWeight)
        showsStyle = try container.decodeIfPresent(Bool.self, forKey: .showsStyle)
        if type == .date {
            minimum = nil
            maximum = nil
            minimumDate = try container.decodeIfPresent(String.self, forKey: .minimum)
            maximumDate = try container.decodeIfPresent(String.self, forKey: .maximum)
        } else {
            minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
            maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
            minimumDate = nil
            maximumDate = nil
        }
        step = try container.decodeIfPresent(Double.self, forKey: .step)
        options = try container.decodeIfPresent([PartPackageOption].self, forKey: .options)
        frameworkValues = try container.decodeIfPresent(PartPackageFrameworkValues.self, forKey: .frameworkValues)
        allowsCustom = try container.decodeIfPresent(Bool.self, forKey: .allowsCustom)
        opacity = try container.decodeIfPresent(Bool.self, forKey: .opacity)
        outputFormat = try container.decodeIfPresent(ColorOutputFormat.self, forKey: .outputFormat)
        customColor = try container.decodeIfPresent(String.self, forKey: .customColor)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        ticks = try container.decodeIfPresent(Int.self, forKey: .ticks)
        showsValueField = try container.decodeIfPresent(Bool.self, forKey: .showsValueField)
        trueValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .trueValue)
        falseValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .falseValue)
        selectionMode = try container.decodeIfPresent(ButtonSelectionMode.self, forKey: .selectionMode)
        argument1 = try container.decodeIfPresent(PartPackageValue.self, forKey: .argument1)
        argument2 = try container.decodeIfPresent(PartPackageValue.self, forKey: .argument2)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        round = try container.decodeIfPresent(Bool.self, forKey: .round)
        absoluteURL = try container.decodeIfPresent(Bool.self, forKey: .absoluteURL)
        presentation = try container.decodeIfPresent(SelectPresentation.self, forKey: .presentation)
        linked = try container.decodeIfPresent(Bool.self, forKey: .linked)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(font, forKey: .font)
        try container.encodeIfPresent(showsFamily, forKey: .showsFamily)
        try container.encodeIfPresent(showsWeight, forKey: .showsWeight)
        try container.encodeIfPresent(showsStyle, forKey: .showsStyle)
        if type == .date {
            try container.encodeIfPresent(minimumDate, forKey: .minimum)
            try container.encodeIfPresent(maximumDate, forKey: .maximum)
        } else {
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        }
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(frameworkValues, forKey: .frameworkValues)
        try container.encodeIfPresent(allowsCustom, forKey: .allowsCustom)
        try container.encodeIfPresent(opacity, forKey: .opacity)
        try container.encodeIfPresent(outputFormat, forKey: .outputFormat)
        try container.encodeIfPresent(customColor, forKey: .customColor)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(ticks, forKey: .ticks)
        try container.encodeIfPresent(showsValueField, forKey: .showsValueField)
        try container.encodeIfPresent(trueValue, forKey: .trueValue)
        try container.encodeIfPresent(falseValue, forKey: .falseValue)
        try container.encodeIfPresent(selectionMode, forKey: .selectionMode)
        try container.encodeIfPresent(argument1, forKey: .argument1)
        try container.encodeIfPresent(argument2, forKey: .argument2)
        try container.encodeIfPresent(operation, forKey: .operation)
        try container.encodeIfPresent(round, forKey: .round)
        try container.encodeIfPresent(absoluteURL, forKey: .absoluteURL)
        try container.encodeIfPresent(presentation, forKey: .presentation)
        try container.encodeIfPresent(linked, forKey: .linked)
    }
}

nonisolated enum PartPackageFrameworkValueSource: String, Codable, CaseIterable, Sendable {
    case colors
    case fontFamilies
    case fontSizes
    case spacing
    case shadows
}

nonisolated enum PartPackageFrameworkValues: Codable, Equatable, Sendable {
    case source(PartPackageFrameworkValueSource)
    case defaultValue(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = PartPackageFrameworkValueSource(rawValue: value).map(Self.source) ?? .defaultValue(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .source(let source): try container.encode(source)
        case .defaultValue(let value): try container.encode(value)
        }
    }
}

nonisolated extension PartPackageControl {
    var frameworkValueSource: PartPackageFrameworkValueSource? {
        if type == .frameworkShadow { return .shadows }
        if type == .frameworkColor { return .colors }
        return nil
    }

    var frameworkValueDefault: String? {
        guard case .defaultValue(let value) = frameworkValues else { return nil }
        return value
    }
}

nonisolated struct PartPackageOption: Codable, Equatable, Identifiable, Sendable {
    let value: String
    let title: String
    let systemImage: String?

    init(value: String, title: String, systemImage: String? = nil) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
    }

    var id: String { value }
}

nonisolated enum PartPackageValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([PartPackageValue])
    case object([String: PartPackageValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([PartPackageValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PartPackageValue].self) {
            self = .object(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var stringValue: String {
        if case .string(let value) = self { value } else { "" }
    }

    var numberValue: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    func value(at path: ArraySlice<Substring>) -> PartPackageValue? {
        guard let key = path.first else { return self }
        guard case .object(let values) = self, let value = values[String(key)] else { return nil }
        return value.value(at: path.dropFirst())
    }
}

nonisolated struct PartPackageRender: Codable, Equatable, Sendable {
    let html: String
    let editorCSS: String?
    let files: [PartPackageTemplateFile]
    let htmlContributions: [PartPackageHTMLContribution]

    enum CodingKeys: String, CodingKey {
        case html
        case editorCSS
        case files
        case htmlContributions
    }

    init(html: String, editorCSS: String? = nil, files: [PartPackageTemplateFile] = [], htmlContributions: [PartPackageHTMLContribution] = []) {
        self.html = html
        self.editorCSS = editorCSS
        self.files = files
        self.htmlContributions = htmlContributions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        html = try container.decode(String.self, forKey: .html)
        editorCSS = try container.decodeIfPresent(String.self, forKey: .editorCSS)
        files = try container.decodeIfPresent([PartPackageTemplateFile].self, forKey: .files) ?? []
        htmlContributions = try container.decodeIfPresent([PartPackageHTMLContribution].self, forKey: .htmlContributions) ?? []
    }
}

nonisolated struct PartPackageTemplateFile: Codable, Equatable, Sendable {
    enum Scope: String, Codable, Sendable {
        case instance
        case page
        case site
    }

    enum Placement: String, Codable, Hashable, Sendable {
        case headStart
        case headEnd
        case bodyStart
        case bodyEnd
    }

    let path: String
    let scope: Scope
    let placement: Placement?
    let closure: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case scope
        case placement
        case closure
    }

    init(path: String, scope: Scope = .instance, placement: Placement? = nil, closure: Bool = true) {
        self.path = path
        self.scope = scope
        self.placement = placement
        self.closure = closure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .instance
        placement = try container.decodeIfPresent(Placement.self, forKey: .placement)
        closure = try container.decodeIfPresent(Bool.self, forKey: .closure) ?? true
    }
}

nonisolated struct PartPackageMissingPart: Codable, Equatable, Sendable {
    let message: String?
    let preview: String?
}

nonisolated struct PartPackageLock: Codable, Equatable, Hashable, Sendable {
    let identifier: String
}

nonisolated struct MissingPartSnapshot: Codable, Equatable, Sendable {
    let name: String
    let category: String
    let previewHTML: String?
    let helpURL: URL?
}

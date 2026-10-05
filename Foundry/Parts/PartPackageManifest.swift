import Foundation

/// One entry of a manifest's `inspector` array: a single Standard/Framework
/// property, a reference to a prebuilt Grouped control (`background`,
/// `spacing`, `sizing`, `borders`, `effects`, `layout`, `reveal`) that
/// expands into several properties at this exact position, or a named section
/// that carries its own controls. Entries with a `type` are controls; entries
/// without one are sections. Sectioning is entirely the developer's: controls
/// outside any section — grouped ones included — live in `Settings`.
nonisolated enum PartPackageControlsEntry: Codable, Equatable, Sendable {
    case property(PartPackageProperty)
    case group(PartPackageControlGroup)
    case section(PartPackageControlSection)

    private struct TypeDiscriminator: Decodable {
        let type: String?
    }

    init(from decoder: Decoder) throws {
        guard let type = try TypeDiscriminator(from: decoder).type else {
            self = .section(try PartPackageControlSection(from: decoder))
            return
        }
        if PartPackageControlGroup.Kind(rawValue: type) != nil {
            self = .group(try PartPackageControlGroup(from: decoder))
        } else {
            self = .property(try PartPackageProperty(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .property(let property): try property.encode(to: encoder)
        case .group(let group): try group.encode(to: encoder)
        case .section(let section): try section.encode(to: encoder)
        }
    }
}

/// A named Inspector section declared inline in `inspector`: the section name
/// and its optional disclosure-header icon appear once, and every control
/// inside belongs to it — plain controls and Grouped-control references
/// alike. Controls outside any section live in `Settings`.
nonisolated struct PartPackageControlSection: Codable, Equatable, Sendable {
    let name: String
    let systemImage: String?
    /// Property and Grouped-control entries in declaration order; sections
    /// cannot nest.
    let entries: [PartPackageControlsEntry]

    private enum CodingKeys: String, CodingKey {
        case name = "section"
        case systemImage
        case entries = "controls"
    }

    init(name: String, systemImage: String? = nil, entries: [PartPackageControlsEntry] = []) {
        self.name = name
        self.systemImage = systemImage
        self.entries = entries.map { entry in
            guard case .property(var property) = entry else { return entry }
            property.group = name
            return .property(property)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([PartPackageControlsEntry].self, forKey: .entries) ?? []
        if entries.contains(where: { if case .section = $0 { true } else { false } }) {
            throw DecodingError.dataCorruptedError(
                forKey: .entries,
                in: container,
                debugDescription: "Sections cannot nest inside sections."
            )
        }
        self.init(
            name: try container.decode(String.self, forKey: .name),
            systemImage: try container.decodeIfPresent(String.self, forKey: .systemImage),
            entries: entries
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(systemImage, forKey: .systemImage)
        try container.encode(entries, forKey: .entries)
    }

    /// The section's controls with every Grouped-control reference expanded
    /// in place; all of them belong to this section.
    var properties: [PartPackageProperty] {
        entries.flatMap { entry -> [PartPackageProperty] in
            switch entry {
            case .property(let property):
                return [property]
            case .group(let group):
                return group.properties.map { property in
                    var property = property
                    property.group = name
                    return property
                }
            case .section:
                return []
            }
        }
    }

    /// The Grouped controls referenced inside this section.
    var groups: [PartPackageControlGroup] {
        entries.compactMap {
            if case .group(let group) = $0 { group } else { nil }
        }
    }
}

/// A part's library artwork: one square glyph — an SVG or an SF Symbol —
/// plus a system tint. By default the tile fills with the tint behind a
/// white glyph; the structure tree paints the glyph in the tint directly.
nonisolated struct PartPackageIcon: Codable, Equatable, Sendable {
    let file: String?
    let symbol: String?
    /// A system colour name, optionally with a shade: `blue`, `blue.light`.
    let tint: String?
    let rendering: String?

    init(file: String? = nil, symbol: String? = nil, tint: String? = nil, rendering: String? = nil) {
        self.file = file
        self.symbol = symbol
        self.tint = tint
        self.rendering = rendering
    }

    private var tintParts: (colour: Substring, shade: Substring?) {
        let parts = (tint ?? "").split(separator: ".", maxSplits: 1)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : nil)
    }

    /// Unknown colours render as gray rather than failing validation.
    var resolvedTint: PartIconTint {
        PartIconTint(rawValue: String(tintParts.colour)) ?? .gray
    }

    /// Unknown shades use the regular colour.
    var resolvedShade: PartIconShade {
        tintParts.shade.flatMap { PartIconShade(rawValue: String($0)) } ?? .regular
    }

    /// Unknown renderings use the standard white glyph.
    var resolvedRendering: PartIconRendering {
        rendering.flatMap(PartIconRendering.init(rawValue:)) ?? .monochrome
    }
}

/// A lighter or darker version of an icon tint.
nonisolated enum PartIconShade: String, Codable, CaseIterable, Sendable {
    case regular, light, dark
}

/// How an icon's glyph is drawn. Original applies to SVG files, which then
/// draw as authored; everything else draws as a white monochrome glyph.
nonisolated enum PartIconRendering: String, Codable, CaseIterable, Sendable {
    case monochrome, original
}

/// The supported icon tints, mirroring the macOS system colours so both
/// appearances come for free.
nonisolated enum PartIconTint: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
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
    let icon: PartPackageIcon?
    let controlsEntries: [PartPackageControlsEntry]
    let render: PartPackageRender
    let assets: [PartPackageAsset]
    let helpURL: URL?
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
        case icon
        case controlsEntries = "inspector"
        case render = "templates"
        case assets
        case helpURL
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
        icon = try container.decodeIfPresent(PartPackageIcon.self, forKey: .icon)
        controlsEntries = try container.decodeIfPresent([PartPackageControlsEntry].self, forKey: .controlsEntries) ?? []
        render = try container.decode(PartPackageRender.self, forKey: .render)
        assets = try container.decodeIfPresent([PartPackageAsset].self, forKey: .assets) ?? []
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
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
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(controlsEntries, forKey: .controlsEntries)
        try container.encode(render, forKey: .render)
        try container.encode(assets, forKey: .assets)
        try container.encodeIfPresent(helpURL, forKey: .helpURL)
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

extension PartPackageManifest {
    /// Standard/Framework properties in the exact order the manifest declared
    /// them, with each Grouped-control reference and section expanded in place.
    nonisolated var resolvedProperties: [PartPackageProperty] {
        controlsEntries.flatMap { entry in
            switch entry {
            case .property(let property): [property]
            case .group(let group): group.properties
            case .section(let section): section.properties
            }
        }
    }

    /// The named sections this manifest declared, in declaration order.
    nonisolated var controlSections: [PartPackageControlSection] {
        controlsEntries.compactMap {
            if case .section(let section) = $0 { section } else { nil }
        }
    }

    /// The Grouped controls this manifest references — top level and inside
    /// sections — in declaration order. Position-preserving order lives in
    /// `controlsEntries`/`resolvedProperties`; this is just the set of groups,
    /// for CSS/HTML-contribution/lookup purposes.
    nonisolated var controlGroups: [PartPackageControlGroup] {
        controlsEntries.flatMap { entry -> [PartPackageControlGroup] in
            switch entry {
            case .group(let group): [group]
            case .section(let section): section.groups
            case .property: []
            }
        }
    }

    /// Inspector section icons by section name, from each named section's
    /// `systemImage`. Sections with no entry here render with the generic
    /// fallback icon.
    nonisolated var resolvedGroupIcons: [String: String] {
        var icons: [String: String] = [:]
        for section in controlSections {
            if let systemImage = section.systemImage {
                icons[section.name] = systemImage
            }
        }
        return icons
    }

    nonisolated var controlGroupCSS: String {
        controlGroups.map(\.css).joined(separator: "\n")
    }

    nonisolated var controlGroupJavaScript: String {
        controlGroups.map(\.javaScript).joined(separator: "\n")
    }

    nonisolated var htmlContributions: [PartPackageHTMLContribution] {
        let imageAlt = resolvedProperties.first { $0.id == "source" && $0.control.type == .image }
            .map { "control.\($0.id).alt" }
        let lightboxes = controlGroups.filter { $0.type == .lightbox }.compactMap(\.id)
        return render.htmlContributions + controlGroups.flatMap { group in
            group.htmlContributions(imageAlt: imageAlt).map { contribution in
                guard group.type == .linkOverlay, !lightboxes.isEmpty else { return contribution }
                let guards = lightboxes.map { "{{ if !control.\($0).enabled }}" }.joined()
                return PartPackageHTMLContribution(placement: contribution.placement, template: guards + contribution.template + String(repeating: "{{ endif }}", count: lightboxes.count))
            }
        }
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
        case transitions
        case filters
        case transforms
        case flexbox
        case layout
        case reveal
        /// A whole-part destination and its accessible name. Its distinct
        /// name avoids colliding with the primitive `link` control kind.
        case linkOverlay
        case lightbox
        /// The opt-in HTML identity section (ID, classes, custom attributes).
        /// Unlike the other kinds it carries native Inspector fields bound to
        /// the placed part, not property controls, so it has no registry
        /// definition and always renders as Foundry's own Advanced section.
        case advanced
    }

    enum BackgroundStyle: String, Codable, CaseIterable, Hashable, Sendable {
        case colour
        case image
        case gradient
        case video

        /// Video requires authored markup and a positioned host; opt in explicitly.
        static let defaultStyles: [Self] = [.colour, .image, .gradient]

        var templateValue: String {
            self == .colour ? "color" : rawValue
        }
    }

    let type: Kind
    let id: String?
    /// Reveal-only descendant selector. Nil deliberately targets the part root.
    let target: String?
    var namespace: String { id ?? "" }
    let backgroundTypes: [BackgroundStyle]
    let supportsHover: Bool
    /// Lets a part adjust a shared group's injected defaults (e.g. a
    /// different starting padding) without hand-declaring the whole group.
    let defaults: [String: PartPackageValue]
    /// Gates the whole group behind one of the part's own controls, e.g. a
    /// flexbox group shown only while a layout select reads "flex". Folded
    /// into every expanded control's own condition.
    let visibleWhen: PartPackageVisibilityCondition?
    /// Generated controls this part does not want at all — a choice its own
    /// markup could not honour, or a capability it deliberately withholds.
    /// Controls that exist only to configure an omitted one go too.
    let excludeControls: [String]
    /// Narrows a generated select to the listed values, in the listed order.
    /// The first value becomes the control's default unless the original
    /// default survives the narrowing.
    let allowedOptions: [String: [String]]

    init(
        type: Kind,
        id: String?,
        target: String? = nil,
        backgroundTypes: [BackgroundStyle] = BackgroundStyle.defaultStyles,
        supportsHover: Bool = true,
        defaults: [String: PartPackageValue] = [:],
        visibleWhen: PartPackageVisibilityCondition? = nil,
        excludeControls: [String] = [],
        allowedOptions: [String: [String]] = [:]
    ) {
        self.type = type
        self.id = id
        self.target = target
        self.backgroundTypes = backgroundTypes
        self.supportsHover = supportsHover
        self.defaults = defaults
        self.visibleWhen = visibleWhen
        self.excludeControls = excludeControls
        self.allowedOptions = allowedOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case target = "targetSelector"
        case backgroundTypes
        case supportsHover
        case defaults
        case visibleWhen
        case excludeControls
        case allowedOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        id = type == .advanced ? nil : try container.decode(String.self, forKey: .id)
        if let id, id.range(of: #"^[A-Za-z][A-Za-z0-9_-]*$"#, options: .regularExpression) == nil {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Group id must start with a letter and contain only letters, numbers, underscores, or hyphens.")
        }
        target = try container.decodeIfPresent(String.self, forKey: .target)
        backgroundTypes = try container.decodeIfPresent([BackgroundStyle].self, forKey: .backgroundTypes)
            ?? BackgroundStyle.defaultStyles
        supportsHover = try container.decodeIfPresent(Bool.self, forKey: .supportsHover) ?? true
        defaults = try container.decodeIfPresent([String: PartPackageValue].self, forKey: .defaults) ?? [:]
        visibleWhen = try container.decodeIfPresent(PartPackageVisibilityCondition.self, forKey: .visibleWhen)
        excludeControls = try container.decodeIfPresent([String].self, forKey: .excludeControls) ?? []
        allowedOptions = try container.decodeIfPresent([String: [String]].self, forKey: .allowedOptions) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        guard type != .advanced else { return }
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(target, forKey: .target)
        if type == .background {
            try container.encode(backgroundTypes, forKey: .backgroundTypes)
            try container.encode(supportsHover, forKey: .supportsHover)
        }
        if !defaults.isEmpty { try container.encode(defaults, forKey: .defaults) }
        try container.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        if !excludeControls.isEmpty { try container.encode(excludeControls, forKey: .excludeControls) }
        if !allowedOptions.isEmpty { try container.encode(allowedOptions, forKey: .allowedOptions) }
    }

    var properties: [PartPackageProperty] {
        guard type != .advanced, let id else { return [] }
        let definition = BuiltInControlGroupRegistry.definition(for: type)
        let base = type == .background
            ? configuredBackgroundProperties(definition.controls)
            : definition.controls
        return omitting(narrowedOptions(base)).map { property in
            var property = property
            let localID = property.id
            if let override = defaults[property.id] {
                property.defaultValue = override
            }
            property.id = id + "." + localID
            property.visibleWhen = property.visibleWhen?.prefixed(with: id)
            property.controlGroupSource = .init(type: type, namespace: namespace, localID: localID)
            if let visibleWhen {
                property.visibleWhen = property.visibleWhen.map { .init(all: [visibleWhen, $0]) } ?? visibleWhen
            }
            return property
        }
    }

    /// Narrows the named selects to the listed values, in the listed order.
    /// A default the narrowing removed moves to the first listed value, the
    /// way the Background group's `backgroundTypes` sets its initial style.
    private func narrowedOptions(_ properties: [PartPackageProperty]) -> [PartPackageProperty] {
        guard !allowedOptions.isEmpty else { return properties }
        return properties.map { original in
            guard let permitted = allowedOptions[original.id],
                  let options = original.control.options else { return original }
            var property = original
            property.control.options = permitted.compactMap { value in
                options.first { $0.value == value }
            }
            if case .string(let current) = property.defaultValue, !permitted.contains(current) {
                property.defaultValue = .string(permitted.first ?? current)
            }
            return property
        }
    }

    /// Drops the omitted controls, then anything left whose visibility depends
    /// on one of them: a control that configures a capability the part removed
    /// has nothing left to configure.
    private func omitting(_ properties: [PartPackageProperty]) -> [PartPackageProperty] {
        guard !excludeControls.isEmpty else { return properties }
        var remaining = properties.filter { !excludeControls.contains($0.id) }
        var present = Set(remaining.map(\.id))
        var removedDependent = true
        while removedDependent {
            removedDependent = false
            remaining = remaining.filter { property in
                let references = Self.referencedIDs(in: property.visibleWhen)
                guard !references.isSubset(of: present) else { return true }
                removedDependent = true
                return false
            }
            present = Set(remaining.map(\.id))
        }
        return remaining
    }

    /// The sibling control IDs a condition reads, ignoring the group-level
    /// condition's reference to one of the part's own controls — this runs
    /// before that condition is folded in.
    static func referencedIDs(in condition: PartPackageVisibilityCondition?) -> Set<String> {
        guard let condition else { return [] }
        if let all = condition.all {
            return all.reduce(into: Set()) { $0.formUnion(referencedIDs(in: $1)) }
        }
        if let any = condition.any {
            return any.reduce(into: Set()) { $0.formUnion(referencedIDs(in: $1)) }
        }
        // An indexed reference such as `edges[0]` names the control before it.
        guard let id = condition.id else { return [] }
        return [String(id.prefix { $0 != "[" })]
    }

    private func configuredBackgroundProperties(
        _ properties: [PartPackageProperty]
    ) -> [PartPackageProperty] {
        let styleValues = Set(backgroundTypes.map(\.templateValue))
        let hoverStyleValues = styleValues.subtracting(["video"])
        let includesHover = supportsHover && !hoverStyleValues.isEmpty

        return properties.compactMap { original in
            if !includesHover, original.id.hasPrefix("backgroundHover") {
                return nil
            }
            let isOverlay = original.id.hasPrefix("backgroundOverlay")
            if isOverlay {
                let mediaStyles: Set<String> = ["image", "video"]
                if styleValues.isDisjoint(with: mediaStyles) { return nil }
            }
            if let requiredStyle = Self.backgroundStyle(for: original.id),
               !isOverlay, !styleValues.contains(requiredStyle) {
                return nil
            }

            var property = original
            if isOverlay, !includesHover {
                var conditions: [PartPackageVisibilityCondition] = [
                    .init(id: "backgroundMode", value: .string("static")),
                    .init(any: ["image", "video"].map {
                        .init(id: "backgroundStyle", value: .string($0))
                    })
                ]
                if property.id == "backgroundOverlayColor" {
                    conditions.append(.init(id: "backgroundOverlayEnabled", value: .boolean(true)))
                }
                property.visibleWhen = .init(all: conditions)
            }
            switch property.id {
            case "backgroundMode":
                property.control.options = property.control.options?.filter {
                    includesHover || $0.value != "hover"
                }
            case "backgroundStyle":
                property.control.options = property.control.options?.filter {
                    styleValues.contains($0.value)
                }
                property.defaultValue = .string(backgroundTypes.first?.templateValue ?? "color")
            case "backgroundHoverStyle":
                property.control.options = property.control.options?.filter {
                    hoverStyleValues.contains($0.value)
                }
                property.defaultValue = .string(
                    backgroundTypes.map(\.templateValue).first(where: hoverStyleValues.contains) ?? "color"
                )
            default:
                break
            }
            return property
        }
    }

    private static func backgroundStyle(for propertyID: String) -> String? {
        if propertyID.contains("Gradient") { return "gradient" }
        if propertyID.contains("Video") { return "video" }
        if propertyID == "backgroundColor" || propertyID == "backgroundHoverColor" { return "color" }
        if [
            "backgroundImage", "backgroundSize", "backgroundRepeat",
            "backgroundHoverImage", "backgroundHoverSize", "backgroundHoverRepeat"
        ].contains(propertyID) { return "image" }
        return nil
    }

    /// Link supplies its own root decoration; style groups expose CSS values.
    var css: String {
        guard type == .linkOverlay, let id else { return "" }
        return """
        {{ if control.\(id).destination }}
        :where(:instance[data-foundry-link-display="block"]) { display: block; }
        :where(:instance[data-foundry-root-link]) { color: inherit; text-decoration: none; }
        :instance[data-foundry-root-link]:focus-visible {
            outline: 2px solid currentColor;
            outline-offset: -2px;
        }
        {{ endif }}
        """
    }

    var htmlContributions: [PartPackageHTMLContribution] { htmlContributions(imageAlt: nil) }

    func htmlContributions(imageAlt: String?) -> [PartPackageHTMLContribution] {
        if type == .lightbox, let id {
            return [.init(placement: .beforeClosingTag, template: """
            {{ if control.\(id).enabled }}
            <div hidden data-foundry-lightbox-config="\(id)" style="color: {{ control.\(id).backdropColor }}" data-backdrop-color="{{ control.\(id).backdropColor }}" data-backdrop-blur="{{ control.\(id).backdropBlur }}"></div>
            {{ endif }}
            """)]
        }
        guard type == .linkOverlay, let id,
              properties.contains(where: { $0.controlGroupSource?.localID == "destination" }) else { return [] }
        let fallback = imageAlt.map { "{{ if \($0) }}{{ \($0) }}{{ else }}{{ control.\(id).destination }}{{ endif }}" }
            ?? "{{ control.\(id).destination }}"
        let label = properties.contains { $0.controlGroupSource?.localID == "accessibleName" }
            ? "{{ if control.\(id).accessibleName }}{{ control.\(id).accessibleName }}{{ else }}\(fallback){{ endif }}"
            : fallback
        return [.init(placement: .rootLink, template: """
        {{ if control.\(id).destination }}<a data-foundry-root-link="\(id)" href="{{ control.\(id).destination }}" target="{{ control.\(id).destination.target }}" {{ control.\(id).destination.attributes }} aria-label="\(label)"></a>{{ endif }}
        """)]
    }

    var javaScript: String {
        if type == .lightbox, let id {
            return "{{ if !canvas }}{{ if control.\(id).enabled }}" + YouTubePosterPlayback.javaScript + "\n" + CanvasYouTubeThumbnails.javaScript + "\n" + FoundryLightbox.javaScript + """
            \n(() => {
              const root = document.querySelector('[data-foundry-id="{{ instance.id }}"]');
              const config = root && Array.from(root.querySelectorAll('[data-foundry-lightbox-config="\(id)"]')).find(node => node.closest('[data-foundry-id]') === root);
              if (root && config) globalThis.foundryLightbox.connect(root, config);
            })();
            {{ endif }}{{ endif }}
            """
        }
        if type == .background, backgroundTypes.contains(.video) {
            return PartBackgroundVideoPlayback.javaScript
        }
        guard type == .reveal, let id else { return "" }
        let script = #"""
        (() => {
            const root = document.querySelector('[data-foundry-id="{{ instance.id }}"]');
            if (!root || typeof gsap === "undefined" || typeof ScrollTrigger === "undefined") return;
            root._foundryRevealContext?.revert();
            if (!{{ control.revealEnabled }} || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
                return;
            }
            const selector = __FOUNDRY_REVEAL_TARGET__;
            let target = root;
            if (selector !== null) {
                let matches;
                try {
                    matches = Array.from(root.querySelectorAll(selector)).filter(
                        element => element.closest('[data-foundry-id]') === root
                    );
                } catch {
                    console.warn("Foundry Reveal: invalid target selector", selector, root);
                    return;
                }
                if (matches.length !== 1) {
                    console.warn("Foundry Reveal: target must match exactly one element owned by this part", selector, root);
                    return;
                }
                target = matches[0];
            }
            const targets = {{ if control.revealStagger > 0 }}Array.from(target.children){{ else }}[target]{{ endif }};
            gsap.registerPlugin(ScrollTrigger);
            const from = { autoAlpha: 0 };
            const distance = {{ control.revealDistance }};
            switch ("{{ control.revealEffect }}") {
            case "fade-up": from.y = distance; break;
            case "fade-down": from.y = -distance; break;
            case "fade-left": from.x = distance; break;
            case "fade-right": from.x = -distance; break;
            case "scale": from.scale = 0.85; break;
            case "blur": from.filter = "blur(" + distance + "px)"; break;
            }
            root._foundryRevealContext = gsap.context(() => {
                gsap.from(targets, {
                    ...from,
                    duration: {{ control.revealDuration }} / 1000,
                    delay: {{ control.revealDelay }} / 1000,
                    stagger: {{ control.revealStagger }} / 1000,
                    ease: "{{ control.revealEase }}",
                    scrollTrigger: {
                        trigger: target,
                        start: "top {{ control.revealTrigger }}%",
                        once: {{ control.revealOnce }},
                        toggleActions: {{ if control.revealOnce }}"play none none none"{{ else }}"play none none reverse"{{ endif }}
                    }
                });
            }, root);
        })();
        """#
        // JSON quoting prevents selectors becoming executable JavaScript. Escape
        // '<' too because the same source can appear inside an HTML script tag.
        let selector = target.map { value in
            String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
                .replacingOccurrences(of: "<", with: #"\u003c"#)
                .replacingOccurrences(of: "\u{2028}", with: #"\u2028"#)
                .replacingOccurrences(of: "\u{2029}", with: #"\u2029"#)
        } ?? "null"
        return script.replacingOccurrences(of: "control.reveal", with: "control.\(id).reveal")
            .replacingOccurrences(of: "root._foundryRevealContext", with: "root[\"_foundryReveal_\(id)\"]")
            .replacingOccurrences(of: "__FOUNDRY_REVEAL_TARGET__", with: selector)
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
            case .rootLink:
                output = PartRootLinkRenderer.convert(output, anchor: fragment)
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
        }
    }
}

nonisolated struct PartPackageHTMLContribution: Codable, Equatable, Sendable {
    enum Placement: String, Codable, Sendable {
        case afterOpeningTag
        case beforeClosingTag
        case rootLink
    }

    enum Target: Equatable, Sendable {
        case root
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
    let buttonText: String
    let buttonIcon: String
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
        visibleWhen: PartPackageVisibilityCondition? = nil,
        buttonText: String = "Add Child",
        buttonIcon: String = "plus.app"
    ) {
        self.id = id
        self.title = title
        self.buttonText = buttonText
        self.buttonIcon = buttonIcon
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
    struct ControlGroupSource: Equatable, Sendable {
        let type: PartPackageControlGroup.Kind
        let namespace: String
        let localID: String
    }
    // Expansion-only identity, never inferred from IDs or encoded as a custom control key.
    var controlGroupSource: ControlGroupSource? = nil
    var usesAutomaticVideoPoster: Bool {
        control.type == .video && controlGroupSource?.type == .background
    }
    enum ValueAvailability: String, Codable, CaseIterable, Sendable {
        case always
        case whenVisible
    }

    var id: String
    let label: String
    let noteTitle: String?
    let noteBody: String
    let noteSystemImage: String?
    /// The Inspector section this control belongs to — assigned by the
    /// containing section wrapper (or its Grouped-control definition), never
    /// decoded from the control itself. Top-level controls live in Settings.
    var group: String
    var control: PartPackageControl
    var defaultValue: PartPackageValue
    var breakpointDefaults: [String: PartPackageValue] = [:]
    let responsive: Bool
    let subtitles: [String]
    let buttonTexts: [String]
    let buttonIcons: [String]
    let activeButtonTexts: [String]
    let activeButtonIcons: [String]
    let units: [String]
    /// The CSS a framework-spacing control emits for its `none` token. CSS
    /// spells "no constraint" differently per property — `0` for a minimum,
    /// `none` for a maximum — so the control carries its own answer and
    /// templates can interpolate it unconditionally.
    let noneValue: String?
    let tooltip: String?
    /// `var`: a grouped-control reference's own `visibleWhen` folds into each
    /// expanded control during manifest expansion.
    var visibleWhen: PartPackageVisibilityCondition?
    let valueAvailability: ValueAvailability
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
        case defaultValue = "defaults"
        case responsive
        case subtitle
        case buttonText
        case buttonIcon
        case activeButtonText
        case activeButtonIcon
        case units
        case noneValue
        case tooltip
        case visibleWhen
        case valueAvailability
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
        valueAvailability: ValueAvailability = .always,
        tooltip: String? = nil,
        units: [String] = [""],
        noneValue: String? = nil
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
        self.noneValue = noneValue
        self.tooltip = tooltip
        self.visibleWhen = visibleWhen
        self.valueAvailability = valueAvailability
        alt = ""
        focalPoint = false
        renditions = []
        accepts = []
        pickerItems = []
        initial = []
        containment = .open
    }

    /// Developer ids must start with a letter, so this prefix can never
    /// collide with one.
    static let synthesizedIDPrefix = "__"

    /// Whether Foundry, not the developer, named this control.
    var hasSynthesizedID: Bool {
        control.type.permitsOmittedID && id.hasPrefix(Self.synthesizedIDPrefix)
    }

    /// A stable id from the control's place in the manifest. The coding path
    /// is unique per declaration — `inspector[3].controls[1]` becomes
    /// `__divider_3_1` — and the same manifest always yields the same ids.
    private static func synthesizedID(for type: PartPackageControl.Kind, at codingPath: [any CodingKey]) -> String {
        let position = codingPath.compactMap { $0.intValue.map(String.init) }.joined(separator: "_")
        return synthesizedIDPrefix + type.rawValue + (position.isEmpty ? "" : "_" + position)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = "Settings"
        control = try PartPackageControl(from: decoder)
        if let declared = try container.decodeIfPresent(String.self, forKey: .id) {
            id = declared
        } else if control.type.permitsOmittedID {
            id = Self.synthesizedID(for: control.type, at: decoder.codingPath)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        noneValue = try container.decodeIfPresent(String.self, forKey: .noneValue)
        visibleWhen = try container.decodeIfPresent(PartPackageVisibilityCondition.self, forKey: .visibleWhen)
        valueAvailability = try container.decodeIfPresent(ValueAvailability.self, forKey: .valueAvailability) ?? .always
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
        if control.type == .divider || control.type == .spacer || control.type == .note || control.type == .image || control.type == .svg || control.type == .video || control.type == .math || control.type == .childPicker {
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
        if ![.note, .divider, .spacer, .math, .childPicker].contains(control.type) {
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
        try container.encodeIfPresent(noneValue, forKey: .noneValue)
        try container.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        if valueAvailability != .always {
            try container.encode(valueAvailability, forKey: .valueAvailability)
        }
        if (control.type == .image || control.type == .svg), !alt.isEmpty {
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
            visibleWhen: visibleWhen,
            buttonText: buttonTexts.first ?? "Add Child",
            buttonIcon: buttonIcons.first ?? "plus.app"
        )
    }
}


nonisolated struct PartPackageVisibilityCondition: Codable, Equatable, Sendable {
    func removingPrefix(_ prefix: String) -> Self {
        if let all { return .init(all: all.map { $0.removingPrefix(prefix) }) }
        if let any { return .init(any: any.map { $0.removingPrefix(prefix) }) }
        guard let id, id.hasPrefix(prefix) else { return self }
        return .init(id: String(id.dropFirst(prefix.count)), operation: operation, value: value)
    }
    func prefixed(with namespace: String) -> Self {
        if let all { return .init(all: all.map { $0.prefixed(with: namespace) }) }
        if let any { return .init(any: any.map { $0.prefixed(with: namespace) }) }
        guard let id else { return self }
        return .init(id: namespace + "." + id, operation: operation, value: value)
    }
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
    enum ControlPresentation: String, Codable, Sendable {
        case menu
        case segmented
        case checkbox
        case `switch`
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

    enum Kind: String, Codable, CaseIterable, Sendable {
        case text
        case textArea
        case number
        case color
        case frameworkColor
        case frameworkFont
        case frameworkFontSize
        case frameworkStackingOrder
        case pageFolder
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
        case svg
        case video
        case math
        case frameworkShadow
        case childPicker
        case spacer

        /// Controls that hold no value and that nothing can refer to. A
        /// developer may leave their id out; one is synthesised instead.
        var permitsOmittedID: Bool {
            self == .divider || self == .note || self == .spacer
        }
    }

    let type: Kind
    let font: String?
    let showsFamily: Bool?
    let showsWeight: Bool?
    let showsStyle: Bool?
    let showsSize: Bool?
    let minimum: Double?
    let maximum: Double?
    let minimumDate: String?
    let maximumDate: String?
    let step: Double?
    var options: [PartPackageOption]?
    let frameworkValues: PartPackageFrameworkValues?
    let allowsCustom: Bool?
    let opacity: Bool?
    let outputFormat: ColorOutputFormat?
    let customColor: String?
    let count: Int?
    let ticks: Int?
    let editableValue: Bool?
    let trueValue: PartPackageValue?
    let falseValue: PartPackageValue?
    let selectionMode: ButtonSelectionMode?
    let argument1: PartPackageValue?
    let argument2: PartPackageValue?
    let operation: String?
    let round: Bool?
    let absoluteURL: Bool?
    let presentation: ControlPresentation?
    /// Explicit starting link state for edges/corners controls; nil infers it from
    /// whether the declared edge defaults are all equal.
    let linked: Bool?
    /// Spacer-only: the gap in points.
    let height: Double?
    /// Slider-only: labelled tick marks, keyed by the value as a string.
    let tickLabels: [String: String]?
    /// Slider-only: text shown in place of the read-only value at particular values.
    let valueLabels: [String: String]?
    /// Slider-only: what sits at each end of the track.
    let minimumLabel: PartPackageSliderEndLabel?
    let maximumLabel: PartPackageSliderEndLabel?
    /// Slider-only: the value the track fills from, instead of the minimum.
    let neutralValue: Double?

    /// The spacer's gap when `height` is omitted, and the permitted range.
    static let defaultSpacerHeight: Double = 10
    static let spacerHeightRange: ClosedRange<Double> = 1...30

    enum CodingKeys: String, CodingKey {
        case type, font, minimum, maximum, step, options, frameworkValues, allowsCustom
        case showsFamily, showsWeight, showsStyle, showsSize
        case opacity, outputFormat, customColor, count, ticks, editableValue
        case trueValue, falseValue, selectionMode, argument1, argument2, operation, round, absoluteURL, presentation, linked
        case height
        case tickLabels, valueLabels, minimumLabel, maximumLabel, neutralValue
    }

    init(
        type: Kind,
        minimum: Double? = nil,
        maximum: Double? = nil,
        step: Double? = nil,
        options: [PartPackageOption]? = nil,
        allowsCustom: Bool? = nil,
        opacity: Bool? = nil,
        editableValue: Bool? = nil,
        absoluteURL: Bool? = nil,
        presentation: ControlPresentation? = nil,
        showsStyle: Bool? = nil
    ) {
        self.type = type
        font = nil
        showsFamily = nil
        showsWeight = nil
        self.showsStyle = showsStyle
        showsSize = nil
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
        self.editableValue = editableValue
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
        height = nil
        tickLabels = nil
        valueLabels = nil
        minimumLabel = nil
        maximumLabel = nil
        neutralValue = nil
    }

    static func select(_ options: [(String, String)], presentation: ControlPresentation? = nil) -> Self {
        Self(type: .select, options: options.map { PartPackageOption(value: $0.0, title: $0.1) }, presentation: presentation)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        font = try container.decodeIfPresent(String.self, forKey: .font)
        showsFamily = try container.decodeIfPresent(Bool.self, forKey: .showsFamily)
        showsWeight = try container.decodeIfPresent(Bool.self, forKey: .showsWeight)
        showsStyle = try container.decodeIfPresent(Bool.self, forKey: .showsStyle)
        showsSize = try container.decodeIfPresent(Bool.self, forKey: .showsSize)
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
        editableValue = try container.decodeIfPresent(Bool.self, forKey: .editableValue)
        trueValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .trueValue)
        falseValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .falseValue)
        selectionMode = try container.decodeIfPresent(ButtonSelectionMode.self, forKey: .selectionMode)
        argument1 = try container.decodeIfPresent(PartPackageValue.self, forKey: .argument1)
        argument2 = try container.decodeIfPresent(PartPackageValue.self, forKey: .argument2)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        round = try container.decodeIfPresent(Bool.self, forKey: .round)
        absoluteURL = try container.decodeIfPresent(Bool.self, forKey: .absoluteURL)
        presentation = try container.decodeIfPresent(ControlPresentation.self, forKey: .presentation)
        linked = try container.decodeIfPresent(Bool.self, forKey: .linked)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        tickLabels = try container.decodeIfPresent([String: String].self, forKey: .tickLabels)
        valueLabels = try container.decodeIfPresent([String: String].self, forKey: .valueLabels)
        minimumLabel = try container.decodeIfPresent(PartPackageSliderEndLabel.self, forKey: .minimumLabel)
        maximumLabel = try container.decodeIfPresent(PartPackageSliderEndLabel.self, forKey: .maximumLabel)
        neutralValue = try container.decodeIfPresent(Double.self, forKey: .neutralValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(font, forKey: .font)
        try container.encodeIfPresent(showsFamily, forKey: .showsFamily)
        try container.encodeIfPresent(showsWeight, forKey: .showsWeight)
        try container.encodeIfPresent(showsStyle, forKey: .showsStyle)
        try container.encodeIfPresent(showsSize, forKey: .showsSize)
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
        try container.encodeIfPresent(editableValue, forKey: .editableValue)
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
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(tickLabels, forKey: .tickLabels)
        try container.encodeIfPresent(valueLabels, forKey: .valueLabels)
        try container.encodeIfPresent(minimumLabel, forKey: .minimumLabel)
        try container.encodeIfPresent(maximumLabel, forKey: .maximumLabel)
        try container.encodeIfPresent(neutralValue, forKey: .neutralValue)
    }
}

/// A slider's end label: a symbol, text, or a symbol whose title is read by
/// VoiceOver and shown as its tooltip.
nonisolated struct PartPackageSliderEndLabel: Codable, Equatable, Sendable {
    let title: String?
    let systemImage: String?
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

nonisolated struct PartPackageLock: Codable, Equatable, Hashable, Sendable {
    let identifier: String
}

nonisolated struct MissingPartSnapshot: Codable, Equatable, Sendable {
    let name: String
    let category: String
    let helpURL: URL?
}

import Foundation

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
    let properties: [PartPackageProperty]
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
        case properties = "controls"
        case render = "templates"
        case assets
        case helpURL
        case missingPart
        case requiresPHP
        case libraries
        case updates
    }

    init(
        minimumAPIVersion: Int,
        identifier: String,
        name: String,
        description: String = "",
        author: String? = nil,
        version: String,
        category: String = "Other",
        tags: [String] = [],
        showsInPartLibrary: Bool = true,
        allowedParents: [String] = [],
        properties: [PartPackageProperty] = [],
        render: PartPackageRender,
        assets: [PartPackageAsset] = [],
        helpURL: URL? = nil,
        missingPart: PartPackageMissingPart? = nil,
        requiresPHP: Bool = false,
        libraries: [PartPackageLibraryRequirement] = [],
        updates: FoundryPackUpdateConfiguration? = nil
    ) {
        self.minimumAPIVersion = minimumAPIVersion
        self.identifier = identifier
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.category = category
        self.tags = tags
        self.showsInPartLibrary = showsInPartLibrary
        self.allowedParents = allowedParents
        self.properties = properties
        self.render = render
        self.assets = assets
        self.helpURL = helpURL
        self.missingPart = missingPart
        self.requiresPHP = requiresPHP
        self.libraries = libraries
        self.updates = updates
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
        properties = try container.decodeIfPresent([PartPackageProperty].self, forKey: .properties) ?? []
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
    nonisolated var slots: [PartPackageSlot] {
        properties.compactMap(\.childSlot)
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
    let defaultValue: PartPackageValue
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
        case defaultValue = "default"
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
            units = [try container.decodeIfPresent(String.self, forKey: .units) ?? ""]
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

        if control.type == .divider || control.type == .note || control.type == .image || control.type == .math || control.type == .childPicker {
            defaultValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .defaultValue) ?? .string("")
            responsive = control.type == .image && focalPoint
                ? true
                : try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        } else if control.type == .slider {
            let lowerBound = control.minimum ?? 0
            let upperBound = control.maximum ?? 100
            let implicitDefault = min(max(0, lowerBound), upperBound)
            defaultValue = try container.decodeIfPresent(PartPackageValue.self, forKey: .defaultValue)
                ?? .number(implicitDefault)
            responsive = try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        } else {
            defaultValue = try container.decode(PartPackageValue.self, forKey: .defaultValue)
            responsive = try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        }
    }

    func encode(to encoder: Encoder) throws {
        try control.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if control.count != nil {
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
        if control.type != .note {
            try container.encode(defaultValue, forKey: .defaultValue)
            try container.encode(responsive, forKey: .responsive)
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

nonisolated struct PartPackageVisibilityCondition: Codable, Equatable, Sendable {
    let id: String
    let operation: String
    let value: PartPackageValue?

    enum CodingKeys: String, CodingKey {
        case id
        case operation
        case value
    }

    init(id: String, operation: String = "==", value: PartPackageValue? = nil) {
        self.id = id
        self.operation = operation
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "=="
        value = try container.decodeIfPresent(PartPackageValue.self, forKey: .value)
    }
}

nonisolated struct PartPackageControl: Codable, Equatable, Sendable {
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
        case themeColor
        case themeFont
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
        case math
        case shadow
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
    let themeValues: PartPackageThemeValues?
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

    enum CodingKeys: String, CodingKey {
        case type, font, minimum, maximum, step, options, themeValues, allowsCustom
        case showsFamily, showsWeight, showsStyle
        case opacity, outputFormat, customColor, count, ticks, showsValueField
        case trueValue, falseValue, selectionMode, argument1, argument2, operation, round, absoluteURL
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
        themeValues = try container.decodeIfPresent(PartPackageThemeValues.self, forKey: .themeValues)
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
        try container.encodeIfPresent(themeValues, forKey: .themeValues)
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
    }
}

nonisolated enum PartPackageThemeValueSource: String, Codable, CaseIterable, Sendable {
    case colors
    case fontFamilies
    case fontSizes
    case spacing
    case shadows
}

nonisolated enum PartPackageThemeValues: Codable, Equatable, Sendable {
    case source(PartPackageThemeValueSource)
    case defaultValue(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = PartPackageThemeValueSource(rawValue: value).map(Self.source) ?? .defaultValue(value)
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
    var themeValueSource: PartPackageThemeValueSource? {
        if type == .shadow { return .shadows }
        if type == .themeColor { return .colors }
        return nil
    }

    var themeValueDefault: String? {
        guard case .defaultValue(let value) = themeValues else { return nil }
        return value
    }
}

nonisolated struct PartPackageOption: Codable, Equatable, Identifiable, Sendable {
    let value: String
    let title: String

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

    enum CodingKeys: String, CodingKey {
        case html
        case editorCSS
        case files
    }

    init(html: String, editorCSS: String? = nil, files: [PartPackageTemplateFile] = []) {
        self.html = html
        self.editorCSS = editorCSS
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        html = try container.decode(String.self, forKey: .html)
        editorCSS = try container.decodeIfPresent(String.self, forKey: .editorCSS)
        files = try container.decodeIfPresent([PartPackageTemplateFile].self, forKey: .files) ?? []
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

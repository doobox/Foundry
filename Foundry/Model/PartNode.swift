import Foundation

nonisolated enum PartAnchorValidator {
    static func isValid(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              isASCIILetter(first) else { return false }
        return value.unicodeScalars.dropFirst().allSatisfy {
            isASCIILetter($0) || (48...57).contains($0.value) || $0 == "-" || $0 == "_"
        }
    }

    static func validated(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValid(value) else { return nil }
        return value
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}

nonisolated enum PartRootAttributeValidator {
    static func isValidName(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty,
              !["id", "class", "style"].contains(name),
              !name.hasPrefix("data-foundry-"),
              !name.hasPrefix("on") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value > 32 && ![34, 39, 47, 61, 62].contains(scalar.value)
        }
    }

    static func normalizedClasses(_ value: String?) -> String {
        value?.split(whereSeparator: \Character.isWhitespace).joined(separator: " ") ?? ""
    }

    static func validAttributes(_ attributes: [PartHTMLAttribute]) -> [PartHTMLAttribute] {
        var seen = Set<String>()
        return attributes.compactMap { attribute in
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = name.lowercased()
            guard isValidName(name), seen.insert(normalizedName).inserted else { return nil }
            var result = attribute
            result.name = name
            return result
        }
    }
}

nonisolated struct PartNode: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var type: PartType
    var name: String
    var properties: [PartProperty]
    var children: [PartNode]
    var reusableDefinitionID: UUID?
    var overridesGlobalDefinition: Bool?
    var responsiveOverrides: [ResponsivePropertyOverride]?
    // Initial developer values are distinct from user overrides and survive saving.
    var responsiveDefaults: [ResponsivePropertyOverride]?
    var packageLock: PartPackageLock?
    var missingPackageSnapshot: MissingPartSnapshot?
    var slotID: String?
    var anchor: String?
    var customClasses: String?
    var rootAttributes: [PartHTMLAttribute]?

    init(
        id: UUID = UUID(),
        type: PartType,
        name: String? = nil,
        properties: [PartProperty] = [],
        children: [PartNode] = [],
        reusableDefinitionID: UUID? = nil,
        overridesGlobalDefinition: Bool? = nil,
        responsiveOverrides: [ResponsivePropertyOverride]? = nil,
        packageLock: PartPackageLock? = nil,
        missingPackageSnapshot: MissingPartSnapshot? = nil,
        slotID: String? = nil,
        anchor: String? = nil,
        customClasses: String? = nil,
        rootAttributes: [PartHTMLAttribute]? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.displayName
        self.properties = properties
        self.children = children
        self.reusableDefinitionID = reusableDefinitionID
        self.overridesGlobalDefinition = overridesGlobalDefinition
        self.responsiveOverrides = responsiveOverrides
        self.packageLock = packageLock
        self.missingPackageSnapshot = missingPackageSnapshot
        self.slotID = slotID
        self.anchor = anchor
        self.customClasses = customClasses
        self.rootAttributes = rootAttributes
    }

    static func make(_ type: PartType, theme: Theme = .standard) -> PartNode {
        var ancestry: Set<PartType> = []
        var remainingNodeCount = 1_000
        var node = make(type, ancestry: &ancestry, remainingNodeCount: &remainingNodeCount)
        node.selectInitialColourShades(from: theme)
        return node
    }

    mutating func selectInitialColourShades(from theme: Theme) {
        var initialDefaults: [ResponsivePropertyOverride] = []
        for definition in type.definition.properties {
            for (breakpoint, initialValue) in definition.breakpointDefaults {
                var initialValue = initialValue
                if case .packageColor(var colour) = initialValue,
                   let palette = theme.colourPalettes.resolvedPalette(id: colour.paletteID) {
                    let declaration = type.definition.package?.manifest.properties.first { $0.id == definition.key.rawValue }?.breakpointDefaults[breakpoint.rawValue]
                    if case .object(let fields) = declaration {
                        if fields["lightShade"] == nil { colour.shade = palette.lightDefaultShade }
                        if fields["darkShade"] == nil { colour.darkShade = palette.darkDefaultShade }
                    }
                    initialValue = .packageColor(colour)
                }
                initialDefaults.append(.init(breakpoint: breakpoint, key: definition.key, value: initialValue))
            }
        }
        responsiveDefaults = initialDefaults.isEmpty ? nil : initialDefaults
        for index in properties.indices {
            if case .packageColor(var value) = properties[index].value,
               let palette = theme.colourPalettes.resolvedPalette(id: value.paletteID) {
                if let definition = type.definition.properties.first(where: { $0.key == properties[index].key }),
                   case .packageColor(_, _, let initialLightShade, let initialDarkShade) = definition.control {
                    value.shade = initialLightShade ?? palette.lightDefaultShade
                    value.darkShade = initialDarkShade ?? palette.darkDefaultShade
                } else {
                    value.shade = palette.lightDefaultShade
                    value.darkShade = palette.darkDefaultShade
                }
                properties[index].value = .packageColor(value)
            }
        }
        for index in children.indices { children[index].selectInitialColourShades(from: theme) }
    }

    private static func make(
        _ type: PartType,
        ancestry: inout Set<PartType>,
        remainingNodeCount: inout Int
    ) -> PartNode {
        let definition = type.definition
        var node = PartNode(
            type: type,
            properties: definition.properties.map {
                PartProperty(key: $0.key, value: $0.defaultValue)
            },
            packageLock: definition.package?.lock,
            missingPackageSnapshot: definition.package.map {
                MissingPartSnapshot(
                    name: $0.manifest.name,
                    category: $0.manifest.category,
                    previewHTML: $0.manifest.missingPart?.preview,
                    helpURL: $0.manifest.helpURL
                )
            }
        )
        guard remainingNodeCount > 0,
              let package = definition.package,
              ancestry.insert(type).inserted else { return node }
        remainingNodeCount -= 1
        defer { ancestry.remove(type) }

        for slot in package.manifest.slots {
            for identifier in slot.initial where remainingNodeCount > 0 {
                let childType = PartType(rawValue: identifier)
                guard !ancestry.contains(childType),
                      slot.acceptsPart(childType),
                      childType.definition.package?.manifest.permits(parent: type) != false else { continue }
                var child = make(
                    childType,
                    ancestry: &ancestry,
                    remainingNodeCount: &remainingNodeCount
                )
                child.slotID = slot.id
                node.children.append(child)
            }
        }
        return node
    }

    var packageLocks: Set<PartPackageLock> {
        var locks = Set(children.flatMap(\.packageLocks))
        if let packageLock { locks.insert(packageLock) }
        return locks
    }

    func propertyValue(_ key: PartProperty.Key) -> PartProperty.Value {
        if let value = properties.first(where: { $0.key == key })?.value {
            return value
        }
        return type.definition.properties.first(where: { $0.key == key })?.defaultValue ?? .string("")
    }

    func propertyValue(_ key: PartProperty.Key, at breakpoint: ResponsiveBreakpoint, screens: ScreenTokens = .standard) -> PartProperty.Value {
        let definition = type.definition.properties.first { $0.key == key }
        for candidate in breakpoint.inheritedBreakpoints where candidate.minimumWidth(in: screens) != nil {
            if let value = responsiveOverrides?.first(where: {
                $0.breakpoint == candidate && $0.key == key
            })?.value {
                return value
            }
            if let value = responsiveDefaults?.first(where: { $0.breakpoint == candidate && $0.key == key })?.value { return value }
            if let value = definition?.breakpointDefaults[candidate] { return value }
        }
        return propertyValue(key)
    }

    func hasResponsiveOverride(_ key: PartProperty.Key, at breakpoint: ResponsiveBreakpoint) -> Bool {
        responsiveOverrides?.contains(where: { $0.breakpoint == breakpoint && $0.key == key }) == true
    }

    func resolved(at breakpoint: ResponsiveBreakpoint, screens: ScreenTokens = .standard) -> PartNode {
        guard breakpoint != .mobile else { return self }
        var copy = self
        for definition in type.definition.properties {
            copy.setProperty(definition.key, value: propertyValue(definition.key, at: breakpoint, screens: screens))
        }
        return copy
    }

    func property(_ key: PartProperty.Key) -> String {
        propertyValue(key).stringValue
    }

    func numberProperty(_ key: PartProperty.Key) -> Double {
        propertyValue(key).numberValue ?? 0
    }

    func colorProperty(_ key: PartProperty.Key, theme: Theme) -> String {
        let value = propertyValue(key)
        if let token = value.tokenValue, let color = theme.color(for: token) {
            return color
        }
        return value.stringValue
    }

    func numberProperty(_ key: PartProperty.Key, theme: Theme) -> Double {
        let value = propertyValue(key)
        if let token = value.tokenValue, let number = theme.number(for: token) {
            return number
        }
        return value.numberValue ?? 0
    }

    mutating func setProperty(_ key: PartProperty.Key, value: PartProperty.Value) {
        if let index = properties.firstIndex(where: { $0.key == key }) {
            properties[index].value = value
        } else {
            properties.append(.init(key: key, value: value))
        }
    }

    mutating func setResponsiveProperty(
        _ key: PartProperty.Key,
        value: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint
    ) {
        guard breakpoint != .mobile else {
            setProperty(key, value: value)
            return
        }
        var overrides = responsiveOverrides ?? []
        if let index = overrides.firstIndex(where: { $0.breakpoint == breakpoint && $0.key == key }) {
            overrides[index].value = value
        } else {
            overrides.append(.init(breakpoint: breakpoint, key: key, value: value))
        }
        responsiveOverrides = overrides
    }

    mutating func removeResponsiveOverride(_ key: PartProperty.Key, at breakpoint: ResponsiveBreakpoint) {
        responsiveOverrides?.removeAll(where: { $0.breakpoint == breakpoint && $0.key == key })
        if responsiveOverrides?.isEmpty == true { responsiveOverrides = nil }
    }

    mutating func setProperty(_ key: PartProperty.Key, value: String) {
        let propertyValue: PartProperty.Value = key == .destination
            ? .link(.init(destination: value.isEmpty ? .none : .url(value)))
            : .string(value)
        setProperty(key, value: propertyValue)
    }

    mutating func replaceThemeReference(_ reference: String, with replacement: String) {
        for index in properties.indices {
            properties[index].value = properties[index].value.replacingThemeReference(reference, with: replacement)
        }
        if var overrides = responsiveOverrides {
            for index in overrides.indices {
                overrides[index].value = overrides[index].value
                    .replacingThemeReference(reference, with: replacement)
            }
            responsiveOverrides = overrides
        }
        for index in children.indices {
            children[index].replaceThemeReference(reference, with: replacement)
        }
    }
}

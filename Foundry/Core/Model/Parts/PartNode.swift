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
    /// Values pinned at a breakpoint. A new part starts with its developer's
    /// breakpoint defaults pinned here, exactly as if the user had pinned them.
    var responsiveOverrides: [ResponsivePropertyOverride]?
    var packageLock: PartPackageLock?
    var missingPackageSnapshot: MissingPartSnapshot?
    var slotID: String?
    var anchor: String?
    var customClasses: String?
    /// Author CSS scoped to this instance; `:instance` means the part itself.
    var customCSS: String?
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
        customCSS: String? = nil,
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
        self.customCSS = customCSS
        self.rootAttributes = rootAttributes
    }

    static func make(_ type: PartType) -> PartNode {
        var ancestry: Set<PartType> = []
        var remainingNodeCount = 1_000
        var node = make(type, ancestry: &ancestry, remainingNodeCount: &remainingNodeCount)
        node.applyInitialResponsiveDefaults()
        return node
    }

    mutating func applyInitialResponsiveDefaults() {
        responsiveOverrides = type.definition.properties.flatMap { property in
            property.breakpointDefaults.map { breakpoint, value in
                ResponsivePropertyOverride(breakpoint: breakpoint, key: property.key, value: value)
            }
        }
        if responsiveOverrides?.isEmpty == true { responsiveOverrides = nil }
        for index in children.indices { children[index].applyInitialResponsiveDefaults() }
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

    mutating func migrateLegacyLayoutPartIdentity() {
        let legacyName: String?
        let currentName: String
        switch type {
        case .stack:
            legacyName = "Flexbox"
            currentName = "Stack"
        case .stackItem:
            legacyName = "Flex Item"
            currentName = "Stack Item"
        default:
            legacyName = nil
            currentName = name
        }
        if name == legacyName { name = currentName }
        if let snapshot = missingPackageSnapshot, snapshot.name == legacyName {
            missingPackageSnapshot = .init(
                name: currentName,
                category: snapshot.category,
                helpURL: snapshot.helpURL
            )
        }
        for index in children.indices {
            children[index].migrateLegacyLayoutPartIdentity()
        }
    }

    func propertyValue(_ key: PartProperty.Key) -> PartProperty.Value {
        if let value = storedPropertyValue(key) {
            return value
        }
        return type.definition.property(for: key)?.defaultValue ?? .string("")
    }

    /// Reads only the exact declared property key.
    func storedPropertyValue(_ key: PartProperty.Key) -> PartProperty.Value? {
        properties.first(where: { $0.key == key })?.value
    }

    func propertyValue(_ key: PartProperty.Key, at breakpoint: ResponsiveBreakpoint, screens: ScreenTokens = .standard) -> PartProperty.Value {
        for candidate in breakpoint.inheritedBreakpoints where candidate.minimumWidth(in: screens) != nil {
            if let value = responsiveOverrides?.first(where: {
                $0.breakpoint == candidate && $0.key == key
            })?.value {
                return value
            }
        }
        return propertyValue(key)
    }

    func hasResponsiveOverride(_ key: PartProperty.Key, at breakpoint: ResponsiveBreakpoint) -> Bool {
        responsiveOverrides?.contains(where: { $0.breakpoint == breakpoint && $0.key == key }) == true
    }

    /// The breakpoint whose stored value governs `key` when viewed at `breakpoint`,
    /// and therefore the write target for edits: overrides are created only by
    /// pinning, so an ordinary edit fills whichever pin (including a developer
    /// default pinned when the part was created) or the base the viewed
    /// breakpoint currently inherits from — the change shows at every
    /// breakpoint that inherits the same value.
    func governingBreakpoint(
        for key: PartProperty.Key,
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens = .standard
    ) -> ResponsiveBreakpoint {
        for candidate in breakpoint.inheritedBreakpoints where candidate.minimumWidth(in: screens) != nil {
            if responsiveOverrides?.contains(where: { $0.breakpoint == candidate && $0.key == key }) == true {
                return candidate
            }
        }
        return .mobile
    }

    func resolved(at breakpoint: ResponsiveBreakpoint, screens: ScreenTokens = .standard) -> PartNode {
        guard breakpoint != .mobile else { return self }
        // Only keys that carry breakpoint data can differ from the stored
        // base value; every other key would resolve to itself, and writing
        // all of them dominates page-render profiles.
        let definition = type.definition
        var keys: [PartProperty.Key] = []
        var seen: Set<PartProperty.Key> = []
        for override in responsiveOverrides ?? [] where definition.property(for: override.key) != nil {
            if seen.insert(override.key).inserted { keys.append(override.key) }
        }
        guard !keys.isEmpty else { return self }
        var copy = self
        for key in keys {
            // Native Bootstrap utilities retain all breakpoint classes in one
            // markup tree; do not overwrite their base values for canvas size.
            if definition.package?.manifest.resolvedProperties.first(where: { $0.id == key.rawValue })?.controlGroupSource?.type.generatesBootstrapClasses == true { continue }
            copy.setProperty(key, value: propertyValue(key, at: breakpoint, screens: screens))
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
        let propertyValue: PartProperty.Value = key == .destination || key.rawValue == "link.destination"
            ? .link(.init(destination: value.isEmpty ? .none : .url(value)))
            : .string(value)
        setProperty(key, value: propertyValue)
    }

    mutating func replaceThemeReference(_ reference: String, with replacement: String) {
        transformPropertyValues { $0.replacingThemeReference(reference, with: replacement) }
    }

    mutating func replaceSpacingReference(_ reference: String, with replacement: String) {
        transformPropertyValues { $0.replacingSpacingReference(reference, with: replacement) }
    }

    mutating func bakeThemeSpacingReference(_ reference: String, amountRem: Double, fallbackToken: String) {
        transformPropertyValues {
            $0.bakingThemeSpacingReference(reference, amountRem: amountRem, fallbackToken: fallbackToken)
        }
    }

    mutating func bakeThemeDimensionReference(_ reference: String, amountPx: Double, fallbackToken: String, isRadius: Bool) {
        transformPropertyValues {
            $0.bakingThemeDimensionReference(reference, amountPx: amountPx, fallbackToken: fallbackToken, isRadius: isRadius)
        }
    }

    private mutating func transformPropertyValues(_ transform: (PartProperty.Value) -> PartProperty.Value) {
        for index in properties.indices {
            properties[index].value = transform(properties[index].value)
        }
        if var overrides = responsiveOverrides {
            for index in overrides.indices {
                overrides[index].value = transform(overrides[index].value)
            }
            responsiveOverrides = overrides
        }
        for index in children.indices {
            children[index].transformPropertyValues(transform)
        }
    }
}

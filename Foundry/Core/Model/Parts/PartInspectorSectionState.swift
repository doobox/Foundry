import Foundation

/// Includes hidden and auxiliary properties, never children or neighbouring sections.
nonisolated struct PartInspectorSectionState {
    let defaults: [PartProperty]
    let responsiveDefaults: [ResponsivePropertyOverride]
    let includesIdentity: Bool
    let neutralizingProperty: PartProperty?

    init(part: PartNode, section: PartPropertySection, theme: Theme) {
        let definition = part.type.definition
        let members = definition.inspectorRows.flatMap { row -> [PartPropertyDefinition] in
            if case .controls(let group) = row { return group.properties }
            return []
        }.filter {
            guard $0.section == section else { return false }
            switch $0.control {
            case .note, .divider, .spacer: return false
            default: return true
            }
        }
        var baseline = PartNode(type: part.type, properties: members.map { .init(key: $0.key, value: $0.defaultValue) })
        baseline.applyInitialResponsiveDefaults()
        let keys = Set(members.map(\.key))
        defaults = baseline.properties
        responsiveDefaults = (baseline.responsiveOverrides ?? []).filter { keys.contains($0.key) }
        neutralizingProperty = defaults.first { property in
            let id = property.key.rawValue.split(separator: ".").last
            return (id == "effectsEnabled" && property.value == .boolean(false))
                || (id == "filtersMode" && property.value == .choice("none"))
        }
        includesIdentity = section.rawValue == "Advanced"
            && definition.package?.manifest.controlGroups.contains { $0.type == .advanced } == true
    }

    func hasChanges(in part: PartNode) -> Bool {
        if isNeutral(in: part) { return false }
        return hasStoredChanges(in: part)
    }

    private func hasStoredChanges(in part: PartNode) -> Bool {
        if defaults.contains(where: { part.propertyValue($0.key) != $0.value }) { return true }
        for property in defaults {
            for breakpoint in ResponsiveBreakpoint.allCases {
                func value(in overrides: [ResponsivePropertyOverride], base: PartProperty.Value) -> PartProperty.Value {
                    for inherited in breakpoint.inheritedBreakpoints {
                        if let stored = overrides.first(where: { $0.key == property.key && $0.breakpoint == inherited }) { return stored.value }
                    }
                    return base
                }
                if value(in: part.responsiveOverrides ?? [], base: part.propertyValue(property.key))
                    != value(in: responsiveDefaults, base: property.value) { return true }
            }
        }
        return includesIdentity && (!(part.anchor ?? "").isEmpty || !(part.customClasses ?? "").isEmpty
            || !(part.customCSS ?? "").isEmpty || !(part.rootAttributes ?? []).isEmpty)
    }

    func canReset(_ part: PartNode) -> Bool {
        if hasStoredChanges(in: part) { return true }
        let keys = Set(defaults.map(\.key))
        let actual = (part.responsiveOverrides ?? []).filter { keys.contains($0.key) }
        return actual.count != responsiveDefaults.count || actual.contains { !responsiveDefaults.contains($0) }
    }

    private func isNeutral(in part: PartNode) -> Bool {
        guard let neutralizingProperty else { return false }
        return ResponsiveBreakpoint.allCases.allSatisfy { breakpoint in
            value(
                for: neutralizingProperty.key,
                in: part.responsiveOverrides ?? [],
                base: part.propertyValue(neutralizingProperty.key),
                at: breakpoint
            ) == neutralizingProperty.value
        }
    }

    private func value(
        for key: PartProperty.Key,
        in overrides: [ResponsivePropertyOverride],
        base: PartProperty.Value,
        at breakpoint: ResponsiveBreakpoint
    ) -> PartProperty.Value {
        for inherited in breakpoint.inheritedBreakpoints {
            if let stored = overrides.first(where: { $0.key == key && $0.breakpoint == inherited }) {
                return stored.value
            }
        }
        return base
    }

    func reset(_ part: inout PartNode) {
        let keys = Set(defaults.map(\.key))
        for property in defaults { part.setProperty(property.key, value: property.value) }
        let remaining = (part.responsiveOverrides ?? []).filter { !keys.contains($0.key) } + responsiveDefaults
        part.responsiveOverrides = remaining.isEmpty ? nil : remaining
        if includesIdentity {
            part.anchor = nil
            part.customClasses = nil
            part.customCSS = nil
            part.rootAttributes = nil
        }
    }
}

nonisolated struct PartInspectorControlState {
    private let key: PartProperty.Key
    private let defaultPart: PartNode

    init(part: PartNode, definition: PartPropertyDefinition, theme: Theme) {
        key = definition.key
        var baseline = PartNode(
            type: part.type,
            properties: [.init(key: definition.key, value: definition.defaultValue)]
        )
        baseline.applyInitialResponsiveDefaults()
        defaultPart = baseline
    }

    func hasChanges(
        in part: PartNode,
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens
    ) -> Bool {
        part.propertyValue(key, at: breakpoint, screens: screens)
            != defaultPart.propertyValue(key, at: breakpoint, screens: screens)
    }
}

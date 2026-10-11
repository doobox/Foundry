import Foundation

/// Reusable spacing groups emit Bootstrap utilities, never instance CSS.
nonisolated enum BootstrapSpacingClasses {

    static func resolve(node: PartNode, key: PartProperty.Key, screens: ScreenTokens, spacing: SpacingTokens = .standard) -> String? {
        guard let source = node.definition.package?.manifest.resolvedProperties.first(where: { $0.id == key.rawValue })?.controlGroupSource,
              source.type == .spacing else { return nil }
        var classes = utilities(node.propertyValue(key), spacing: spacing)
        for (index, id) in BootstrapLayout.ids.enumerated() where screens.screen(id).isEnabled {
            guard let override = node.responsiveOverrides?.first(where: { $0.key == key && $0.breakpoint.screenID == id }) else { continue }
            let breakpoint = BootstrapLayout.classes[index].split(separator: ":")[0]
            classes += utilities(override.value, spacing: spacing).map { "\(breakpoint):\($0)" }
        }
        return classes.joined(separator: " ")
    }

    static func utilities(_ value: PartProperty.Value, spacing: SpacingTokens = .standard) -> [String] {
        switch value {
        case .themePadding(let edges): edgeClasses(edges, prefix: "p", spacing: spacing)
        case .themeMargin(let edges): edgeClasses(edges, prefix: "m", spacing: spacing)
        default: []
        }
    }

    private static func edgeClasses<P: ThemeSpacingPolicy>(_ value: ThemeSpacingValue<P>, prefix: String, spacing: SpacingTokens) -> [String] {
        func token(_ edge: ThemeSpacingValue<P>.Edge) -> String? {
            let selected = value.value(for: edge)
            guard !selected.isCustom,
                  spacing.choices.contains(where: { $0.id == selected.token }) || (prefix == "m" && selected.token == "auto") else { return nil }
            return selected.token
        }
        let top = token(.top), bottom = token(.bottom)
        let start = token(.left), end = token(.right)
        if let top, top == bottom, top == start, top == end {
            return ["\(prefix)-\(top)"]
        }
        var classes: [String] = []
        if let top, top == bottom {
            classes.append("\(prefix)y-\(top)")
        } else {
            if let top { classes.append("\(prefix)t-\(top)") }
            if let bottom { classes.append("\(prefix)b-\(bottom)") }
        }
        if let start, start == end {
            classes.append("\(prefix)x-\(start)")
        } else {
            if let start { classes.append("\(prefix)s-\(start)") }
            if let end { classes.append("\(prefix)e-\(end)") }
        }
        return classes
    }

    /// Inspector edge labels; matching edges may use shorthand in generated output.
    static func edgePrefix<P: ThemeSpacingPolicy>(_ edge: ThemeSpacingValue<P>.Edge, property: String) -> String {
        let suffix = switch edge {
        case .top: "t"
        case .bottom: "b"
        case .left: "s"
        case .right: "e"
        }
        return property + suffix
    }
}

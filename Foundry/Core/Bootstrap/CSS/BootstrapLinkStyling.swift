import Foundation

/// Parts choose a centrally defined link pair; only decoration is local.
nonisolated enum BootstrapLinkStyling {
    static func className(node: PartNode, group: PartPackageControlGroup) -> String {
        "fd-links-" + node.id.uuidString.lowercased() + "-" + group.namespace
    }

    static func css(node: PartNode, group: PartPackageControlGroup, theme: Theme) -> String {
        let properties = node.definition.package?.manifest.resolvedProperties.filter { $0.controlGroupSource?.namespace == group.namespace } ?? []
        func selected(_ id: String) -> String? {
            guard let property = properties.first(where: { $0.controlGroupSource?.localID == id }) else { return nil }
            let value = node.propertyValue(.init(rawValue: property.id)).stringValue
            guard value != "none", value != "inherit",
                  property.control.type == .themeColors || property.control.options?.contains(where: { $0.value == value }) == true else { return nil }
            return value
        }
        var base: [String] = [], hover: [String] = []
        if let value = selected("colour") {
            let tokens: [String]
            if value == "token:link-color" { tokens = ["link-color", "link-hover-color"] }
            else if let palette = theme.colourPalettes.first(where: {
                $0.origin == .custom && $0.colourKind == .link && value == "token:" + $0.colourTokens[0]
            }) { tokens = palette.colourTokens }
            else { tokens = [] }
            if tokens.count == 2 {
                if tokens[0] == "link-color" {
                    for token in BootstrapEditorSection.linkColours.tokens {
                        base.append("--bs-\(token.id):\(theme.bootstrapTokens.value(token))")
                    }
                } else {
                    base.append("--bs-link-color:var(--bs-\(tokens[0]))")
                    base.append("--bs-link-hover-color:var(--bs-\(tokens[1]))")
                }
                base.append("color:var(--bs-link-color)")
                hover.append("color:var(--bs-link-hover-color)")
            }
        }
        switch selected("decoration") {
        case "underline": base.append("text-decoration-line:underline"); hover.append("text-decoration-line:underline")
        case "hover": base.append("text-decoration-line:none"); hover.append("text-decoration-line:underline")
        case "off": base.append("text-decoration-line:none"); hover.append("text-decoration-line:none")
        default: break
        }
        guard !base.isEmpty || !hover.isEmpty else { return "" }
        let root = "." + className(node: node, group: group)
        let selector: String
        if let target = group.target {
            guard BootstrapEditorToken.safeValue(target) else { return "" }
            selector = ":where(:scope :is(\(target)):not(.btn))"
        } else { selector = ":where(:scope)" }
        var css = base.isEmpty ? "" : "\(selector){\(base.joined(separator: ";"))}"
        if !hover.isEmpty { css += "@media(hover:hover){\(selector):hover{\(hover.joined(separator: ";"))}}" }
        // Native scope proximity makes the nearest explicit choice win, even
        // when export deduplicates and sorts independently generated styles.
        return "@layer utilities{@scope (\(root)){\(css)}}"
    }
}

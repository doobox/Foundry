import Foundation

/// The property a colour picker paints, independent of its selected colour family.
nonisolated enum PartColourPurpose: String, Sendable {
    case background, foreground, border, link

    var defaultSections: [String] {
        switch self {
        case .background: ["surfaces", "themes"]
        case .foreground: ["foregrounds", "themes", "blackWhite"]
        case .border: ["borders", "themes"]
        case .link: ["links", "themes"]
        }
    }

    var prefix: String {
        switch self {
        case .background: "bg"
        case .foreground: "fg"
        case .border: "border"
        case .link: "link"
        }
    }

    var themeRole: String {
        switch self {
        case .background: "bg"
        case .foreground, .link: "fg"
        case .border: "border"
        }
    }

    /// Generic theme selectors inside reusable colour groups still preview the
    /// paint role that the group applies, rather than the theme's background.
    static func previewRole(purpose: Self?, group: PartPackageControlGroup.Kind?, variant: String? = nil) -> String {
        if let purpose {
            switch (purpose, variant) {
            case (.foreground, "emphasis"): return "fg-emphasis"
            case (.foreground, "contrast"): return "contrast"
            case (.background, "subtle"): return "bg-subtle"
            case (.background, "muted"): return "bg-muted"
            default: return purpose.themeRole
            }
        }
        switch group {
        case .foreground:
            switch variant {
            case "emphasis": return "fg-emphasis"
            case "contrast": return "contrast"
            default: return "fg"
            }
        case .linkStyling: return "fg"
        case .borders: return "border"
        default: return "bg"
        }
    }

    /// Native utilities where available; explicit generated utilities otherwise.
    func resolve(_ selection: String, theme: Theme, variant: String = "normal", opacity: Double = 100) -> (className: String, color: String, css: String) {
        guard !selection.isEmpty, selection != "inherit" else { return ("", "", "") }
        let token: String
        let candidate: String
        let hover: String
        let variant = PartColourToken.parse(selection) == nil ? variant : "normal"
        let variantPrefix: String
        let variantRole: String
        switch (self, variant) {
        case (.foreground, "emphasis"): (variantPrefix, variantRole) = ("fg-emphasis", "fg-emphasis")
        case (.foreground, "contrast"): (variantPrefix, variantRole) = ("fg-contrast", "contrast")
        case (.background, "subtle"): (variantPrefix, variantRole) = ("bg-subtle", "bg-subtle")
        case (.background, "muted"): (variantPrefix, variantRole) = ("bg-muted", "bg-muted")
        case (.border, "subtle"): (variantPrefix, variantRole) = ("border-subtle", "border")
        default: (variantPrefix, variantRole) = (prefix, themeRole)
        }
        if let paint = PartColourToken.parse(selection) {
            token = paint.id
            candidate = token.hasPrefix(prefix + "-") ? token : prefix + "-" + token
            hover = token.hasSuffix("link-color")
                ? String(token.dropLast("link-color".count)) + "link-hover-color" : token
        } else {
            guard let palette = BootstrapPaletteTheme.effectivePalette(selection, in: theme),
                  let role = BootstrapPaletteTheme.nativeRole(palette) else { return ("", "", "") }
            token = role + "-" + variantRole
            candidate = variantPrefix + "-" + role
            hover = role + "-fg-emphasis"
        }
        let amount = Int(min(100, max(0, opacity)).rounded())
        let baseColor = "var(--bs-\(token))"
        let color = amount == 100 ? baseColor : "color-mix(in oklch, \(baseColor) \(amount)%, transparent)"
        func withOpacity(_ className: String, _ css: String, forceCSS: Bool = false) -> (className: String, color: String, css: String) {
            guard amount < 100 else { return (className, color, css) }
            if self == .link {
                let opacityClass = className + "--o\(amount)"
                let rule = ".\(opacityClass){color:\(color)}.\(opacityClass):is(:hover,:focus-visible){color:color-mix(in oklch,var(--bs-\(hover)) \(amount)%,transparent)}"
                return (opacityClass, color, "@layer utilities{\(rule)}")
            }
            let opacityClass = prefix + (amount > 0 && amount % 10 == 0 ? "-\(amount)" : "-opacity--\(amount)")
            let extra = amount > 0 && amount % 10 == 0 && css.isEmpty && !forceCSS ? "" : ".\(opacityClass).\(opacityClass){\(self == .background ? "background-color:color-mix(in oklch,var(--bs-bg) \(amount)%,transparent)" : self == .border ? "border-color:color-mix(in oklch,var(--bs-bc) \(amount)%,transparent)" : "color:color-mix(in oklch,var(--bs-fg) \(amount)%,transparent)")}"
            return (className + " " + opacityClass, color, css + (extra.isEmpty ? "" : "@layer utilities{\(extra)}"))
        }
        if let palette = theme.colourPalettes.first(where: {
            $0.origin == .custom && $0.colourTokens.contains(token)
        }), let source = palette.colourKind.sourceTokens.first(where: { palette.colourToken($0) == token }),
           let name = palette.publicUtilityClass(for: source),
           name.hasPrefix(prefix + "-") {
            return withOpacity(name, "", forceCSS: true)
        }
        if self != .link, BootstrapPaletteTheme.hasBundledClass(candidate) {
            return withOpacity(candidate, "")
        }
        // Project semantic colours already have utilities emitted by the theme.
        if self != .link, PartColourToken.parse(selection) == nil {
            return withOpacity(candidate, "")
        }
        let name = "fd-\(prefix)--\(token)"
        let css: String
        switch self {
        case .background:
            css = ".\(name){--bs-bg:\(baseColor);background-color:var(--bs-bg)}"
        case .foreground:
            css = ".\(name){--bs-fg:\(baseColor);color:var(--bs-fg)}"
        case .border:
            css = ".\(name){--bs-bc:\(baseColor);border-color:var(--bs-bc)}"
        case .link:
            css = ".\(name){color:\(baseColor)}.\(name):is(:hover,:focus-visible){color:var(--bs-\(hover))}"
        }
        return withOpacity(name, "@layer utilities{\(css)}")
    }

    static func pickerSettings(node: PartNode, property: PartPackageProperty) -> (variant: String, opacity: Double) {
        guard property.controlGroupSource?.type == .colourControls else { return ("normal", 100) }
        let prefix = property.id + "_"
        return (
            node.propertyValue(.init(rawValue: prefix + "variant")).stringValue,
            node.propertyValue(.init(rawValue: prefix + "opacity")).numberValue ?? 100
        )
    }

    static func insert(node: PartNode, theme: Theme, into values: inout [String: PartPackageValue]) {
        for property in node.definition.package?.manifest.resolvedProperties ?? [] {
            if property.control.type == .themeColors,
               property.controlGroupSource == nil || property.controlGroupSource?.type == .colourControls {
                let selection = node.property(.init(rawValue: property.id))
                values[property.id] = .string(PartColourToken.parse(selection) == nil
                    ? BootstrapPaletteTheme.resolve(selection, theme: theme) : "theme-reset")
            }
            guard let purpose = property.control.type.colourPurpose else { continue }
            let settings = pickerSettings(node: node, property: property)
            let output = purpose.resolve(node.property(.init(rawValue: property.id)), theme: theme,
                variant: settings.variant, opacity: settings.opacity)
            values[property.id] = .string(output.className)
            values[property.id + ".color"] = .string(output.color)
        }
    }
}

extension PartPackageControl.Kind {
    nonisolated var colourPurpose: PartColourPurpose? {
        switch self {
        case .backgroundColor: .background
        case .foregroundColor: .foreground
        case .borderColor: .border
        case .linkColor: .link
        default: nil
        }
    }

    nonisolated var isColourPicker: Bool { self == .themeColors || colourPurpose != nil }
}

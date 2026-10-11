import Foundation

/// The property a colour picker paints, independent of its selected colour family.
nonisolated enum PartColourPurpose: String, Sendable {
    case background, foreground, border, link

    var defaultSections: [String] {
        switch self {
        case .background: ["surfaces", "themes"]
        case .foreground: ["foregrounds", "themes"]
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

    /// Native utilities where available; explicit generated utilities otherwise.
    func resolve(_ selection: String, theme: Theme) -> (className: String, color: String, css: String) {
        guard !selection.isEmpty, selection != "inherit" else { return ("", "", "") }
        let token: String
        let candidate: String
        let hover: String
        if let paint = PartColourToken.parse(selection) {
            token = paint.id
            candidate = token.hasPrefix(prefix + "-") ? token : prefix + "-" + token
            hover = token.hasSuffix("link-color")
                ? String(token.dropLast("link-color".count)) + "link-hover-color" : token
        } else {
            guard let palette = BootstrapPaletteTheme.effectivePalette(selection, in: theme),
                  let role = BootstrapPaletteTheme.nativeRole(palette) else { return ("", "", "") }
            token = role + "-" + themeRole
            candidate = prefix + "-" + role
            hover = role + "-fg-emphasis"
        }
        let color = "var(--bs-\(token))"
        if self != .link, BootstrapPaletteTheme.hasBundledClass(candidate) {
            return (candidate, color, "")
        }
        // Project semantic colours already have utilities emitted by the theme.
        if self != .link, PartColourToken.parse(selection) == nil {
            return (candidate, color, "")
        }
        let name = "fd-\(prefix)--\(token)"
        let css: String
        switch self {
        case .background:
            css = ".\(name){--bs-bg:\(color);background-color:var(--bs-bg)}"
        case .foreground:
            css = ".\(name){--bs-fg:\(color);color:var(--bs-fg)}"
        case .border:
            css = ".\(name){--bs-bc:\(color);border-color:var(--bs-bc)}"
        case .link:
            css = ".\(name){color:\(color)}.\(name):is(:hover,:focus-visible){color:var(--bs-\(hover))}"
        }
        return (name, color, "@layer utilities{\(css)}")
    }

    static func insert(node: PartNode, theme: Theme, into values: inout [String: PartPackageValue]) {
        for property in node.definition.package?.manifest.resolvedProperties ?? [] {
            if property.control.type == .themeColors, property.controlGroupSource == nil {
                let selection = node.property(.init(rawValue: property.id))
                values[property.id] = .string(PartColourToken.parse(selection) == nil
                    ? BootstrapPaletteTheme.resolve(selection, theme: theme) : "theme-reset")
            }
            guard let purpose = property.control.type.colourPurpose else { continue }
            let output = purpose.resolve(node.property(.init(rawValue: property.id)), theme: theme)
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

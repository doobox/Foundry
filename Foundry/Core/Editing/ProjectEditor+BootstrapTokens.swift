import Foundation

extension ProjectEditor {
    func setBootstrapColourScale(_ hue: String, scale: BootstrapColourScale) {
        guard BootstrapColourCatalogue.hues.contains(hue) else { return }
        mutate(actionName: "Customise \(hue.capitalized) Scale", impact: .theme) { site in
            for shade in ColourShade.allCases {
                let token = BootstrapEditorToken("\(hue)-\(shade.bootstrapLabel)")
                let value = scale.expression(at: shade)
                site.theme.bootstrapTokens.values[token.id] = value == token.defaultValue ? nil : value
            }
        }
    }

    func setBootstrapColourGroup(_ section: BootstrapEditorSection, base: String) {
        guard section == .linkColours || section == .shadowColours,
              BootstrapEditorToken.safeValue(base), let token = section.tokens.first else { return }
        mutate(actionName: "Customise \(section.title)", impact: .theme) { site in
            site.theme.bootstrapTokens.values[token.id] = base == token.defaultValue ? nil : base
            // Bootstrap's native hover expression derives from the link colour.
            if section == .linkColours { site.theme.bootstrapTokens.values["link-hover-color"] = nil }
        }
    }

    func setBootstrapToken(_ token: BootstrapEditorToken, value: String) {
        // Bootstrap's utility scales ship fixed; only component tokens and project additions change.
        guard document.site.theme.bootstrapTokens.isEditable(token) else { return }
        guard BootstrapEditorToken.safeValue(value) else { return }
        guard document.site.theme.bootstrapTokens.value(token) != value else { return }
        mutate(actionName: "Edit Bootstrap \(token.label)", impact: .theme) {
            $0.theme.bootstrapTokens.values[token.id] = value == token.defaultValue ? nil : value
        }
    }

    func resetBootstrapTokens(_ section: BootstrapEditorSection) {
        guard document.site.theme.bootstrapTokens.isChanged(section) else { return }
        mutate(actionName: "Reset Bootstrap \(section.title)", impact: .theme) { site in
            for token in section.tokens { site.theme.bootstrapTokens.values[token.id] = nil }
        }
    }

    func canAddBootstrapToken(_ name: String, section: BootstrapEditorSection) -> Bool {
        guard section.allowsCustom,
              name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              !["none", "auto", "inherit", "initial", "unset", "pill", "circle", "size", "top", "bottom", "start", "end", "current", "black", "white", "opacity", "keyline", "inset"].contains(name),
              !BootstrapColourCatalogue.themeRoles.contains(name) else { return false }
        if section == .fontSize && (BootstrapEditorSection.sizes + ["wrap", "nowrap", "balance", "pretty", "truncate", "center", "break", "lowercase", "uppercase", "capitalize"]).contains(name) { return false }
        let tokens = document.site.theme.bootstrapTokens.tokens(in: section)
        return section.customTokens(named: name).allSatisfy { custom in !tokens.contains { $0.id == custom.id } }
    }

    func addBootstrapToken(_ name: String, section: BootstrapEditorSection) {
        guard canAddBootstrapToken(name, section: section) else { return }
        mutate(actionName: "Add Bootstrap \(section.title)", impact: .theme) {
            $0.theme.bootstrapTokens.custom[section.rawValue, default: []].append(name)
        }
    }

    func removeBootstrapToken(_ name: String, section: BootstrapEditorSection) {
        guard document.site.theme.bootstrapTokens.custom[section.rawValue]?.contains(name) == true else { return }
        mutate(actionName: "Delete Custom \(section.title)", impact: .theme) { site in
            let mappings: [(String, String)] = switch section {
            case .fontSize: [("fs-", "fs-md"), ("text-", "text-md")]
            case .borderWidth: [("border-", "border-1")]
            case .borderRadius: ["rounded", "rounded-size", "rounded-top", "rounded-end", "rounded-bottom", "rounded-start"].map { ($0 + "-", $0 + "-5") }
            case .shadows: [("shadow-", "shadow")]
            case .zIndex: [("z-", "z-0")]
            default: []
            }
            for (prefix, replacement) in mappings { site.replacePartThemeReference(prefix + name, with: replacement) }
            site.theme.bootstrapTokens.custom[section.rawValue]?.removeAll { $0 == name }
            for token in section.customTokens(named: name) { site.theme.bootstrapTokens.values[token.id] = nil }
            if section == .fontSize { site.theme.bootstrapTokens.values["line-height-" + name] = nil }
        }
    }

    func resetBootstrapFonts() {
        mutate(actionName: "Reset Bootstrap Fonts", impact: .theme) {
            let defaults = Theme.standard.typography
            $0.theme.typography.bodyFont = defaults.bodyFont
            $0.theme.typography.headingFont = defaults.headingFont
            $0.theme.typography.monospacedFont = defaults.monospacedFont
        }
    }
}

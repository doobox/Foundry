import Foundation

extension ProjectEditor {
    func setBootstrapToken(_ token: BootstrapEditorToken, value: String) {
        guard BootstrapEditorToken.safeValue(value) else { return }
        guard document.site.framework.bootstrapTokens.value(token) != value else { return }
        mutate(actionName: "Edit Bootstrap \(token.label)", impact: .framework) {
            $0.framework.bootstrapTokens.values[token.id] = value == token.defaultValue ? nil : value
        }
    }

    func resetBootstrapTokens(_ section: BootstrapEditorSection) {
        guard document.site.framework.bootstrapTokens.isChanged(section) else { return }
        mutate(actionName: "Reset Bootstrap \(section.title)", impact: .framework) { site in
            for token in section.tokens { site.framework.bootstrapTokens.values[token.id] = nil }
        }
    }

    func canAddBootstrapToken(_ name: String, section: BootstrapEditorSection) -> Bool {
        guard section.allowsCustom,
              name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              !["none", "auto", "inherit", "initial", "unset", "pill", "circle", "size", "top", "bottom", "start", "end", "current", "black", "white", "opacity", "keyline", "inset"].contains(name),
              !BootstrapColourCatalogue.themeRoles.contains(name) else { return false }
        let tokens = document.site.framework.bootstrapTokens.tokens(in: section)
        return section.customTokens(named: name).allSatisfy { custom in !tokens.contains { $0.id == custom.id } }
    }

    func addBootstrapToken(_ name: String, section: BootstrapEditorSection) {
        guard canAddBootstrapToken(name, section: section) else { return }
        mutate(actionName: "Add Bootstrap \(section.title)", impact: .framework) {
            $0.framework.bootstrapTokens.custom[section.rawValue, default: []].append(name)
        }
    }

    func removeBootstrapToken(_ name: String, section: BootstrapEditorSection) {
        guard document.site.framework.bootstrapTokens.custom[section.rawValue]?.contains(name) == true else { return }
        mutate(actionName: "Delete Custom \(section.title)", impact: .framework) { site in
            let mappings: [(String, String)] = switch section {
            case .fontSize: [("fs-", "fs-md"), ("text-", "text-md")]
            case .borderWidth: [("border-", "border-1")]
            case .borderRadius: ["rounded", "rounded-size", "rounded-top", "rounded-end", "rounded-bottom", "rounded-start"].map { ($0 + "-", $0 + "-5") }
            case .shadows: [("shadow-", "shadow")]
            case .zIndex: [("z-", "z-0")]
            default: []
            }
            for (prefix, replacement) in mappings { site.replacePartFrameworkReference(prefix + name, with: replacement) }
            site.framework.bootstrapTokens.custom[section.rawValue]?.removeAll { $0 == name }
            for token in section.customTokens(named: name) { site.framework.bootstrapTokens.values[token.id] = nil }
        }
    }

    func resetBootstrapFonts() {
        mutate(actionName: "Reset Bootstrap Fonts", impact: .framework) {
            let defaults = Framework.standard.typography
            $0.framework.typography.bodyFont = defaults.bodyFont
            $0.framework.typography.headingFont = defaults.headingFont
            $0.framework.typography.monospacedFont = defaults.monospacedFont
        }
    }
}

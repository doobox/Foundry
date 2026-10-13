import Foundation

nonisolated extension Site {
    /// Retain only extended steps actually selected in older spacing/gap controls.
    /// New projects keep the untouched Bootstrap scale and emit no extra CSS.
    mutating func preserveLegacySpacingSelections() {
        var tokens = Set<String>()
        func collect(_ value: PartProperty.Value) {
            switch value {
            case .themePadding(let value):
                for edge in value.values where !edge.isCustom { tokens.insert(edge.token) }
            case .themeMargin(let value):
                for edge in value.values where !edge.isCustom { tokens.insert(edge.token) }
            case .themeSpacing(let value):
                if !value.selection.isCustom { tokens.insert(value.selection.token) }
            case .array(let values): values.forEach(collect)
            case .object(let values): values.values.forEach(collect)
            default: break
            }
        }
        func visit(_ node: PartNode) {
            node.properties.forEach { collect($0.value) }
            node.responsiveOverrides?.forEach { collect($0.value) }
            node.children.forEach(visit)
        }
        pages.flatMap(\.parts).forEach(visit)
        globalPartLibrary.allDefinitions.forEach { visit($0.root) }
        projectTemplateLibrary.allDefinitions.forEach { visit($0.root) }
        for token in tokens.sorted() {
            guard let amount = SpacingTokens.legacyAmount(token),
                  !theme.spacing.custom.contains(where: { $0.name == token }) else { continue }
            let custom = CustomSpacingToken(name: token, value: amount)
            theme.spacing.custom.append(custom)
            projectThemeValues.spacing.append(custom)
            for index in themeStates.indices where !themeStates[index].theme.spacing.custom.contains(where: { $0.name == token }) {
                themeStates[index].theme.spacing.custom.append(custom)
            }
        }
    }
}

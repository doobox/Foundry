import Foundation

/// Resolves one collection record with the same theme-aware semantics as
/// ordinary part properties. Renderer-specific URL and colour work is supplied
/// by closures so canvas and export keep their existing behaviour.
nonisolated enum PartCollectionRenderResolver {
    static func resolve(
        _ record: PartProperty.Value,
        fields: [PartPropertyDefinition],
        breakpoint: ResponsiveBreakpoint,
        theme: Theme,
        source: (String, PartPropertyControl) -> String,
        link: (PartLink, Bool) -> PartLinkResolver.Result?
    ) -> PartPackageValue {
        let resolvedRecord = PartCollectionValue.resolved(
            record,
            fields: fields,
            at: breakpoint,
            screens: theme.screens
        )
        let raw = resolvedRecord.objectValue ?? [:]
        var values = raw.mapValues(packageValue)

        for definition in fields {
            let id = definition.key.rawValue
            guard let value = raw[id] else { continue }
            if let purpose = definition.colourPurpose {
                let output = purpose.resolve(value.stringValue, theme: theme,
                    variant: raw[id + "_variant"]?.stringValue ?? "normal",
                    opacity: raw[id + "_opacity"]?.numberValue ?? 100)
                values[id] = .string(output.className)
                values[id + ".color"] = .string(output.color)
                continue
            }

            switch (definition.control, value) {
            case (.themeColors, _):
                values[id] = .string(BootstrapPaletteTheme.resolve(value.stringValue, theme: theme))
            case (_, .themeBorderWidth(let width)):
                values[id] = PartPackageThemeBorderWidthControl.resolved(width, theme: theme)
            case (_, .themeRadius(let radius)):
                values[id] = PartPackageThemeRadiusControl.resolved(radius, theme: theme)
            case (_, .themeMargin(let margin)):
                values[id] = PartPackageThemeMarginControl.resolved(margin, theme: theme)
            case (_, .themeSpacing(let spacing)):
                values[id] = PartPackageSingleSpacingControl.resolved(spacing, theme: theme, noneValue: nil)
            case (_, .themePadding(let padding)):
                values[id] = PartPackageThemePaddingControl.resolved(padding, theme: theme)
            case (.themeFont, _):
                var font: [String: PartPackageValue] = [
                    "family": .string(PartPackageThemeValueResolver.resolve(
                        value.stringValue,
                        from: .fontFamilies,
                        theme: theme
                    ) ?? "inherit")
                ]
                if let weight = raw[id + ".weight"]?.numberValue { font["weight"] = .number(weight) }
                if let style = raw[id + ".style"] { font["style"] = packageValue(style) }
                if let size = raw[id + ".size"]?.stringValue.nilIfEmpty {
                    font["size"] = .string(PartPackageThemeValueResolver.resolve(
                        size,
                        from: .fontSizes,
                        theme: theme
                    ) ?? "inherit")
                }
                values[id] = .object(font)
                for (field, fieldValue) in font { values[id + "." + field] = fieldValue }
            case (.themeFontSize, _):
                values[id] = .string(theme.fontSizeCSSVariable(for: value.stringValue))
                values[id + ".lineHeight"] = .string(theme.lineHeightCSSVariable(for: value.stringValue))
            case (.themeStackingOrder, .packageStackingOrder(let selected)):
                values[id] = .string(selected.isCustom
                    ? String(Int(selected.customValue))
                    : theme.zIndexCSSVariable(for: selected.source))
            case (.packageShadow, .packageShadow(let shadow)):
                values[id] = .string(PartPackageShadowResolver.resolve(shadow, theme: theme))
            case (.color, .token(let token)):
                values[id] = .string(theme.color(for: token) ?? token.rawValue)
            case (.number, .token(let token)), (.slider, .token(let token)):
                values[id] = .number(theme.number(for: token) ?? 0)
            case (.image, .url(let path)), (.svg, .url(let path)), (.video, .url(let path)):
                values[id] = .string(source(path, definition.control))
            case (.link(let absoluteURL), .link(let destination)):
                if let resolved = link(destination, absoluteURL) {
                    values[id] = .string(resolved.href)
                    values[id + ".target"] = .string(resolved.target)
                    values[id + ".attributes"] = .string(resolved.attributes)
                }
            default:
                break
            }

            if definition.control.isThemeSpacing,
               case .object(let resolved) = values[id] {
                for (field, fieldValue) in resolved {
                    values[id + "." + field] = fieldValue
                    if case .object(let edges) = fieldValue {
                        for (edge, edgeValue) in edges {
                            values[id + "." + field + "." + edge] = edgeValue
                        }
                    }
                }
                values[id] = resolved["css"]
            }
        }

        return .object(values)
    }

    private static func packageValue(_ value: PartProperty.Value) -> PartPackageValue {
        switch value {
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.map(packageValue))
        case .object(let values): .object(values.mapValues(packageValue))
        case .link: .string("")
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .packageStackingOrder(let value): .string(value.source)
        case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius: .string("")
        }
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

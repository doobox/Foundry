import Foundation

/// Resolves one collection record with the same framework-aware semantics as
/// ordinary part properties. Renderer-specific URL and colour work is supplied
/// by closures so canvas and export keep their existing behaviour.
nonisolated enum PartCollectionRenderResolver {
    static func resolve(
        _ record: PartProperty.Value,
        fields: [PartPropertyDefinition],
        breakpoint: ResponsiveBreakpoint,
        framework: Framework,
        source: (String, PartPropertyControl) -> String,
        link: (PartLink, Bool) -> PartLinkResolver.Result?,
        packageColor: (PartPackageColorValue, Bool) -> String
    ) -> PartPackageValue {
        let resolvedRecord = PartCollectionValue.resolved(
            record,
            fields: fields,
            at: breakpoint,
            screens: framework.screens
        )
        let raw = resolvedRecord.objectValue ?? [:]
        var values = raw.mapValues(packageValue)

        for definition in fields {
            let id = definition.key.rawValue
            guard let value = raw[id] else { continue }

            switch (definition.control, value) {
            case (_, .frameworkBorderWidth(let width)):
                values[id] = PartPackageFrameworkBorderWidthControl.resolved(width, framework: framework)
            case (_, .frameworkRadius(let radius)):
                values[id] = PartPackageFrameworkRadiusControl.resolved(radius, framework: framework)
            case (_, .frameworkMargin(let margin)):
                values[id] = PartPackageFrameworkMarginControl.resolved(margin, framework: framework)
            case (_, .frameworkSpacing(let spacing)):
                values[id] = PartPackageSingleSpacingControl.resolved(spacing, framework: framework, noneValue: nil)
            case (_, .frameworkPadding(let padding)):
                values[id] = PartPackageFrameworkPaddingControl.resolved(padding, framework: framework)
            case (.frameworkFont, _):
                var font: [String: PartPackageValue] = [
                    "family": .string(PartPackageFrameworkValueResolver.resolve(
                        value.stringValue,
                        from: .fontFamilies,
                        framework: framework
                    ) ?? "inherit")
                ]
                if let weight = raw[id + ".weight"]?.numberValue { font["weight"] = .number(weight) }
                if let style = raw[id + ".style"] { font["style"] = packageValue(style) }
                if let size = raw[id + ".size"]?.stringValue.nilIfEmpty {
                    font["size"] = .string(PartPackageFrameworkValueResolver.resolve(
                        size,
                        from: .fontSizes,
                        framework: framework
                    ) ?? "inherit")
                }
                values[id] = .object(font)
                for (field, fieldValue) in font { values[id + "." + field] = fieldValue }
            case (.frameworkFontSize, _):
                values[id] = .string(framework.fontSizeCSSVariable(for: value.stringValue))
                values[id + ".lineHeight"] = .string(framework.lineHeightCSSVariable(for: value.stringValue))
            case (.frameworkStackingOrder, .packageStackingOrder(let selected)):
                values[id] = .string(selected.isCustom
                    ? String(Int(selected.customValue))
                    : framework.zIndexCSSVariable(for: selected.source))
            case (.packageShadow, .packageShadow(let shadow)):
                values[id] = .string(PartPackageShadowResolver.resolve(shadow, framework: framework))
            case (.packageColor(_, let opacity, _, _), .packageColor(let color)):
                values[id] = .string(packageColor(color, opacity))
            case (.color, .token(let token)):
                values[id] = .string(framework.color(for: token) ?? token.rawValue)
            case (.number, .token(let token)), (.slider, .token(let token)):
                values[id] = .number(framework.number(for: token) ?? 0)
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

            if definition.control.isFrameworkSpacing,
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
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .packageStackingOrder(let value): .string(value.source)
        case .frameworkSpacing, .frameworkPadding, .frameworkMargin, .frameworkBorderWidth, .frameworkRadius: .string("")
        }
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import Foundation

/// Composes each control group's selections into the finished block of
/// declarations a part would otherwise hand-write, published as
/// `control.<group>.css`. The individual values stay available for parts that
/// want to place them differently; this is the one-interpolation shortcut for
/// the ordinary case, and it carries the details that are easy to get wrong:
/// the `enabled` toggles' explicit resets, opacity's conversion out of
/// percent, and the Layout group's "emit nothing" sentinels.
///
/// Composition follows explicit identity retained during group expansion.
/// Hand-declared controls never implicitly acquire group behaviour.
nonisolated enum PartPackageControlGroupCSSResolver {
    /// Renderers and validation share the set of groups with composed output.
    private struct Composer {
        let name: String
        let declarations: ([String: PartPackageValue], Set<String>) -> [String]
    }

    private static let composers: [Composer] = [
        .init(name: "effects", declarations: effects),
        .init(name: "transitions", declarations: transitions),
        .init(name: "filters", declarations: { values, declared in
            PartPackageFiltersResolver.declarations(values: values, declared: declared, hovered: false)
        }),
        .init(name: "transforms", declarations: { values, declared in
            PartPackageTransformsResolver.declarations(values: values, declared: declared, hovered: false)
        }),
        .init(name: "layout", declarations: layout)
    ]

    static func resolve(
        _ values: inout [String: PartPackageValue],
        properties: [PartPackageProperty]
    ) {
        for members in groups(in: properties).values {
            guard let source = members.first?.controlGroupSource else { continue }
            let declared = Set(members.compactMap { $0.controlGroupSource?.localID })
            var local = localValues(values, members: members)
            if source.type.generatesBootstrapClasses {
                let classes = members.compactMap { string(values[$0.id]) }.filter { !$0.isEmpty }.joined(separator: " ")
                insertRaw(classes, at: source.namespace + ".classes", into: &values)
                continue
            }
            if supportsHoverTrigger(source.type) {
                insertRaw(
                    hoverSelector(values: local),
                    at: source.namespace + ".hover.selector",
                    into: &values
                )
            }
            guard let composer = composers.first(where: { $0.name == source.type.rawValue }) else { continue }
            // Old documents can contain positions removed by allowedOptions.
            // Use the declared default rather than render a forbidden position.
            if source.type == .layout,
               let position = members.first(where: { $0.controlGroupSource?.localID == "position" }),
               let options = position.control.options,
               !options.contains(where: { $0.value == string(local["position"]) }) {
                local["position"] = position.defaultValue
            }
            let declarations = composer.declarations(local, declared)
            let css = declarations.joined(separator: " ")
            insertRaw(css, at: source.namespace + ".css", into: &values)
            if source.type == .filters {
                let hover = PartPackageFiltersResolver.declarations(values: local, declared: declared, hovered: true)
                insertRaw(hover.joined(separator: " "), at: source.namespace + ".hover.css", into: &values)
            }
            if source.type == .transforms {
                let hover = PartPackageTransformsResolver.declarations(values: local, declared: declared, hovered: true)
                insertRaw(hover.joined(separator: " "), at: source.namespace + ".hover.css", into: &values)
            }
        }
    }

    /// The `control.<name>` namespaces these properties will compose, for
    /// template validation to accept alongside the part's own control IDs.
    static func composedNamespaces(for properties: [PartPackageProperty]) -> Set<String> {
        Set(properties.compactMap { property in
            guard let source = property.controlGroupSource,
                  composers.contains(where: { $0.name == source.type.rawValue }) else { return nil }
            return source.namespace
        })
    }

    private static func supportsHoverTrigger(_ type: PartPackageControlGroup.Kind) -> Bool {
        type == .background || type == .filters || type == .transforms
    }

    private static func hoverSelector(values: [String: PartPackageValue]) -> String {
        switch string(values["hoverTrigger"]) ?? "self" {
        case "parent":
            return ":parent:hover :instance"
        case "custom":
            guard let id = PartAnchorValidator.validated(string(values["hoverTriggerID"])) else {
                return ":instance:hover"
            }
            return "body:has(#\(id):hover) :instance"
        default:
            return ":instance:hover"
        }
    }

    static func groups(in properties: [PartPackageProperty]) -> [String: [PartPackageProperty]] {
        var result: [String: [PartPackageProperty]] = [:]
        for property in properties {
            guard let source = property.controlGroupSource else { continue }
            result[source.namespace, default: []].append(property)
        }
        return result
    }

    static func localValues(_ values: [String: PartPackageValue], members: [PartPackageProperty]) -> [String: PartPackageValue] {
        var local: [String: PartPackageValue] = [:]
        for member in members {
            guard let source = member.controlGroupSource else { continue }
            // Keep the large manifest property out of the inner scan, and
            // prepare its string prefixes once rather than per candidate.
            let memberID = member.id
            let localID = source.localID
            let dottedPrefix = memberID + "."
            let indexedPrefix = memberID + "["
            let prefixLength = memberID.count
            for (key, value) in values {
                guard key == memberID || key.hasPrefix(dottedPrefix) || key.hasPrefix(indexedPrefix) else { continue }
                local[localID + key.dropFirst(prefixLength)] = value
            }
        }
        return local
    }

    static func insertRaw(_ value: String, at reference: String, into values: inout [String: PartPackageValue]) {
        values[reference] = .string(value)
        values["__foundry_raw." + reference] = .boolean(true)
    }

    private static func transitions(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        guard boolean(values["transitionsEnabled"]) == true else {
            return ["transition: none;"]
        }
        let scopes = [
            "all": "all",
            "colors": "color, background-color, border-color, text-decoration-color, fill, stroke",
            "opacity": "opacity",
            "transform": "transform, translate, rotate, scale",
            "shadow": "box-shadow, text-shadow",
            "filters": "filter, backdrop-filter, -webkit-backdrop-filter",
            "border": "border-color, border-width, border-radius",
            "size": "width, height, min-width, max-width, min-height, max-height"
        ]
        let scope = scopes[string(values["transitionProperty"]) ?? "all"] ?? "all"
        let functions = ["ease", "linear", "ease-in", "ease-out", "ease-in-out"]
        let requested = string(values["transitionFunction"]) ?? "ease-in-out"
        let function = functions.contains(requested) ? requested : "ease-in-out"
        func milliseconds(_ key: String, fallback: Double) -> String {
            let raw = number(values[key]) ?? fallback
            let safe = raw.isFinite ? min(max(raw, 0), 10000) : fallback
            return safe.formatted(
                .number.locale(Locale(identifier: "en_US_POSIX"))
                    .grouping(.never).precision(.fractionLength(0...4))
            ) + "ms"
        }
        return [
            "transition-property: \(scope);",
            "transition-duration: calc(\(milliseconds("transitionDuration", fallback: 300)) * var(--foundry-transition-motion, 1));",
            "transition-timing-function: \(function);",
            "transition-delay: calc(\(milliseconds("transitionDelay", fallback: 0)) * var(--foundry-transition-motion, 1));"
        ]
    }

    // MARK: Borders

    // MARK: Shadow

    private static func effects(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let enabled = boolean(values["effectsEnabled"]) ?? false
        var declarations: [String] = []
        if declared.contains("frameworkShadow") {
            declarations.append("box-shadow: \(enabled ? string(values["frameworkShadow"]) ?? "none" : "none");")
        }
        return declarations
    }

    // MARK: Layout

    /// Layout's controls each carry an explicit "emit nothing" choice, so an
    /// untouched group composes an empty block and contributes no CSS at all.
    private static func layout(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        var declarations: [String] = []
        if let position = string(values["position"]), position != "none" {
            declarations.append("position: \(position);")
        }
        switch string(values["zIndexMode"]) {
        case "auto": declarations.append("z-index: auto;")
        case "custom":
            let index = number(values["zIndex"]) ?? 0
            declarations.append("z-index: \(Int(index));")
        default: break
        }
        // Exactly one offset value exists at a time — the other is withheld by
        // its `whenVisible` availability — so whichever is present is the one
        // the author chose.
        if let offsets = string(values["offsets"]), offsets != "none",
           let inset = string(values["offset"]) ?? string(values["offsetEdges"]) {
            declarations.append("inset: \(inset);")
        }
        if let overflow = string(values["overflow"]), overflow != "none" {
            declarations.append("overflow: \(overflow);")
        }
        return declarations
    }

    // MARK: Values

    /// A pixel amount without a trailing `.0`, so `400` composes as `400px`.
    private static func length(_ value: PartPackageValue?) -> String {
        (number(value) ?? 0).formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))
        )
    }

    private static func fraction(_ value: Double) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...4))
        )
    }

    private static func string(_ value: PartPackageValue?) -> String? {
        guard case .string(let value)? = value, !value.isEmpty else { return nil }
        return value
    }

    private static func number(_ value: PartPackageValue?) -> Double? {
        switch value {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    private static func boolean(_ value: PartPackageValue?) -> Bool? {
        guard case .boolean(let value)? = value else { return nil }
        return value
    }
}

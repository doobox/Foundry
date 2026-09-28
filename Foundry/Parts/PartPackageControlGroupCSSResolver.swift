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
        .init(name: "flexbox", declarations: flexbox),
        .init(name: "sizing", declarations: sizing),
        .init(name: "spacing", declarations: spacing),
        .init(name: "borders", declarations: borders),
        .init(name: "effects", declarations: effects),
        .init(name: "layout", declarations: layout)
    ]

    static func resolve(
        _ values: inout [String: PartPackageValue],
        properties: [PartPackageProperty]
    ) {
        for members in groups(in: properties).values {
            guard let source = members.first?.controlGroupSource,
                  let composer = composers.first(where: { $0.name == source.type.rawValue }) else { continue }
            let declared = Set(members.compactMap { $0.controlGroupSource?.localID })
            let local = localValues(values, members: members)
            let declarations = composer.declarations(local, declared)
            let css = declarations.joined(separator: " ")
            insertRaw(css, at: source.namespace + ".css", into: &values)
            if source.type == .flexbox {
                // Structural child sizing is explicitly placed by the part;
                // it does not inject a rule onto the part root.
                insertRaw("min-width: 0;", at: source.namespace + ".childCSS", into: &values)
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

    // MARK: Flexbox

    private static func flexbox(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let fields = [("direction", "flex-direction", "column"), ("wrap", "flex-wrap", "nowrap"),
                      ("columnGap", "column-gap", "0"), ("rowGap", "row-gap", "0"),
                      ("alignItems", "align-items", "flex-start"), ("alignContent", "align-content", "flex-start"),
                      ("justifyContent", "justify-content", "flex-start")]
        return ["display: flex;"] + fields.filter { declared.contains($0.0) }.map {
            "\($0.1): \(string(values[$0.0]) ?? $0.2);"
        }
    }

    // MARK: Sizing

    /// The mode choices are semantic, so this is where they become CSS.
    ///
    /// Every filling mode uses the `stretch` family rather than `width: 100%`:
    /// a percentage resolves against the containing block and then has the
    /// element's own margins added on top, so a part with horizontal margins
    /// overflows its parent. `stretch` fills what is left *after* margins.
    /// The three declarations are one value each engine understands, oldest
    /// first, so the last one a browser recognises wins.
    ///
    /// `max-width: 100%` leads as a rail every later cap overrides in turn:
    /// the mode's own cap, then the author's Max width. Without it an end user
    /// can give a page horizontal scroll with no way to see why.
    private static func sizing(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let fills = ["width: -webkit-fill-available;", "width: -moz-available;", "width: stretch;"]
        var declarations: [String] = []
        let heightMode = declared.contains("heightMode") ? string(values["heightMode"]) ?? "auto" : nil
        var widthCap: String?

        if declared.contains("widthMode") {
            declarations.append("max-width: 100%;")
            switch string(values["widthMode"]) ?? "auto" {
            case "full":
                declarations += fills
            case "fit":
                // fit-content already clamps itself to the available space.
                declarations.append("width: fit-content;")
            case "screen":
                // Deliberately ignores the parent, so it escapes the rail.
                declarations.append("width: 100svw;")
                declarations.append("max-width: none;")
            case "breakpoint":
                declarations += fills
                widthCap = "var(--foundry-container-width)"
                declarations.append("max-width: min(100%, var(--foundry-container-width));")
            case "custom":
                declarations += fills
                let customWidth = "\(length(values["customWidth"]))px"
                widthCap = customWidth
                declarations.append("max-width: min(100%, \(customWidth));")
            default:
                declarations.append("width: auto;")
            }
        }

        if let heightMode {
            // Every responsive mode owns its growth state. Only change growth,
            // leaving a part's shrink factor and basis available to its layout.
            declarations.append("flex-grow: \(heightMode == "fill" ? "1" : "0");")
            if heightMode != "viewport", !declared.contains("minHeight") {
                // Height mode itself can set a minimum even if its separate
                // control is omitted, so leaving viewport must still reset it.
                declarations.append("min-height: 0;")
            }
            switch heightMode {
            case "custom":
                declarations.append("height: \(length(values["customHeight"]))px;")
            case "viewport":
                // A minimum rather than a height, so content taller than the
                // viewport still shows instead of overflowing.
                declarations.append("height: auto;")
                let minimum = declared.contains("minHeight") ? string(values["minHeight"]) ?? "0" : "0"
                // Math functions require compatible types; bare 0 is a number,
                // whereas the framework's None must be a length here.
                declarations.append("min-height: max(100svh, \(minimum == "0" ? "0px" : minimum));")
            case "fill":
                // The page body is a minimum-height flex column, so growing
                // into the space siblings leave free needs no height.
                declarations.append("height: auto;")
            default:
                declarations.append("height: auto;")
            }
        }

        // A ratio only shapes a part whose height follows its width. Any
        // other height mode, or None, writes `auto` so a wider breakpoint's
        // ratio does not leak into this one.
        if declared.contains("aspectRatio") {
            let ratio = string(values["aspectRatio"]) ?? "none"
            if (heightMode ?? "auto") != "auto" || ratio == "none" {
                declarations.append("aspect-ratio: auto;")
            } else if ratio == "custom" {
                declarations.append("aspect-ratio: \(length(values["aspectRatioWidth"])) / \(length(values["aspectRatioHeight"]));")
            } else {
                declarations.append("aspect-ratio: \(ratio);")
            }
        }

        if declared.contains("minWidth") {
            declarations.append("min-width: \(string(values["minWidth"]) ?? "0");")
        }
        // A maximum can tighten a requested width, never enlarge it. With no
        // width mode, None must explicitly clear an earlier breakpoint's cap.
        if declared.contains("maxWidth") {
            let maximum = string(values["maxWidth"]) ?? "none"
            if maximum != "none" {
                let limits = ["100%", widthCap, maximum].compactMap { $0 }.joined(separator: ", ")
                declarations.append("max-width: min(\(limits));")
            } else if !declared.contains("widthMode") {
                declarations.append("max-width: none;")
            }
        }
        if declared.contains("minHeight"), heightMode != "viewport" {
            declarations.append("min-height: \(string(values["minHeight"]) ?? "0");")
        }
        if declared.contains("maxHeight") {
            declarations.append("max-height: \(string(values["maxHeight"]) ?? "none");")
        }
        return declarations
    }

    // MARK: Spacing

    /// Disabled spacing writes explicit zeros rather than nothing, so turning
    /// it off at one breakpoint resets the value a narrower one set.
    private static func spacing(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let enabled = boolean(values["spacingEnabled"]) ?? false
        var declarations: [String] = []
        if declared.contains("frameworkPadding") {
            declarations.append("padding: \(enabled ? string(values["frameworkPadding"]) ?? "0" : "0");")
        }
        if declared.contains("frameworkMargin") {
            declarations.append("margin: \(enabled ? string(values["frameworkMargin"]) ?? "0" : "0");")
        }
        return declarations
    }

    // MARK: Borders

    /// Style and colour stay declared while borders are off: a zero width
    /// keeps them from drawing, and dropping them would fight a wider
    /// breakpoint that has borders on.
    private static func borders(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let enabled = boolean(values["borderEnabled"]) ?? false
        var declarations: [String] = []
        if declared.contains("frameworkBorder") {
            declarations.append("border-width: \(enabled ? string(values["frameworkBorder.width"]) ?? "0" : "0");")
            declarations.append("border-style: \(string(values["frameworkBorder.style"]) ?? "solid");")
        }
        if declared.contains("frameworkBorderColour") {
            declarations.append("border-color: \(string(values["frameworkBorderColour"]) ?? "currentColor");")
        }
        if declared.contains("frameworkRadius") {
            declarations.append("border-radius: \(enabled ? string(values["frameworkRadius"]) ?? "0" : "0");")
        }
        return declarations
    }

    // MARK: Effects

    private static func effects(
        _ values: [String: PartPackageValue],
        declared: Set<String>
    ) -> [String] {
        let enabled = boolean(values["effectsEnabled"]) ?? false
        var declarations: [String] = []
        if declared.contains("frameworkShadow") {
            declarations.append("box-shadow: \(enabled ? string(values["frameworkShadow"]) ?? "none" : "none");")
        }
        if declared.contains("opacity") {
            // The control is a percentage; CSS opacity is a fraction. Doing
            // the division here spares every part a calc().
            let percent = enabled ? number(values["opacity"]) ?? 100 : 100
            declarations.append("opacity: \(fraction(percent / 100));")
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
        if boolean(values["hidden"]) == true {
            // Written after any display the part or another group set.
            declarations.append("display: none;")
        }
        if let visibility = string(values["visibility"]), visibility != "default" {
            declarations.append("visibility: \(visibility);")
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

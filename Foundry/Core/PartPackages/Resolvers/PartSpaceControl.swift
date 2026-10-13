import Foundation
import CryptoKit

nonisolated enum PartSpaceControl {
    static func validDefault(_ value: PartPackageValue) -> Bool {
        if case .string(let token) = value { return PartSpaceValue.preset(token) != nil }
        guard case .object(let fields) = value, Set(fields.keys) == ["value", "unit"],
              case .number(let amount) = fields["value"], amount.isFinite, amount >= 0,
              case .string(let unit) = fields["unit"] else { return false }
        return PartSpaceValue.units.contains(unit)
    }

    private static func overrides(node: PartNode, key: PartProperty.Key, screens: ScreenTokens) -> [ResponsivePropertyOverride] {
        guard node.definition.property(for: key)?.isResponsive == true else { return [] }
        return (node.responsiveOverrides ?? []).filter {
            $0.key == key && $0.breakpoint != .mobile && $0.breakpoint.minimumWidth(in: screens) != nil
        }.sorted { ($0.breakpoint.minimumWidth(in: screens) ?? 0) < ($1.breakpoint.minimumWidth(in: screens) ?? 0) }
    }

    static func className(node: PartNode, key: PartProperty.Key, axis: String, screens: ScreenTokens = .standard) -> String {
        let value = PartSpaceValue(node.propertyValue(key))
        guard value.isCustom || !overrides(node: node, key: key, screens: screens).isEmpty else { return value.preset == "inherit" ? "" : "space-\(axis)-\(value.preset)" }
        // One stable, instance-and-control-specific identifier keeps multiple
        // Space controls on the same part from sharing a CSS rule.
        let identity = node.id.uuidString.lowercased() + ":" + key.rawValue
        let identifier = SHA256.hash(data: Data(identity.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }.joined()
        return "space-\(axis)-\(identifier)"
    }

    static func css(node: PartNode, key: PartProperty.Key, axis: String, screens: ScreenTokens = .standard) -> String {
        let statements = rules(node: node, key: key, axis: axis, screens: screens).map { item in
            item.condition.isEmpty ? item.body : "@media \(item.condition){\(item.body)}"
        }.joined()
        return statements.isEmpty ? "" : "@layer utilities{\(statements)}"
    }

    /// Published and preview pages share each media wrapper across Space
    /// controls. Canvas updates still render one stylesheet per part instance.
    static func pageCSS(nodes: [PartNode], theme: Theme) -> String {
        var conditions: [String] = []
        var bodies: [String: [String]] = [:]
        for node in nodes {
            for definition in node.definition.properties {
                guard case .space(let axis) = definition.control else { continue }
                for item in rules(node: node, key: definition.key, axis: axis, screens: theme.screens) {
                    if bodies[item.condition] == nil { conditions.append(item.condition) }
                    bodies[item.condition, default: []].append(item.body)
                }
            }
        }
        guard !conditions.isEmpty else { return "" }
        let base = bodies[""]?.joined() ?? ""
        let responsive = conditions.filter { !$0.isEmpty }.map { condition in
            "@media \(condition){\(bodies[condition, default: []].joined())}"
        }.joined()
        return "@layer utilities{\(base)\(responsive)}"
    }

    private static func rules(node: PartNode, key: PartProperty.Key, axis: String, screens: ScreenTokens) -> [(condition: String, body: String)] {
        let value = PartSpaceValue(node.propertyValue(key))
        let changes = overrides(node: node, key: key, screens: screens)
        guard value.isCustom || !changes.isEmpty else { return [] }
        let property = axis == "x" ? "margin-inline-end" : "margin-block-end"
        let selections = [value] + changes.map { PartSpaceValue($0.value) }
        let widths = [0] + changes.map { $0.breakpoint.minimumWidth(in: screens)! }
        let selector = className(node: node, key: key, axis: axis, screens: screens)
        // Disjoint intervals let Inherit restore the child's existing margin,
        // without an earlier custom value defeating a later preset or reset.
        return selections.enumerated().compactMap { index, selection -> (condition: String, body: String)? in
            guard selection.isCustom || selection.preset != "inherit" else { return nil }
            let length = selection.isCustom ? selection.cssLength : String(format: "%grem", locale: Locale(identifier: "en_US_POSIX"), SpacingTokens.multipliers[Int(selection.preset)!])
            let rule = ":where(.\(selector) > :not(:last-child)){\(property):\(length)}"
            var conditions: [String] = []
            if widths[index] > 0 { conditions.append("(width >= \(widths[index])px)") }
            if index + 1 < widths.count { conditions.append("(width < \(widths[index + 1])px)") }
            return (conditions.joined(separator: " and "), rule)
        }
    }
}

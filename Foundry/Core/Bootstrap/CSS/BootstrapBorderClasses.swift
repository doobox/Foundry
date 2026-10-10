import Foundation

nonisolated enum BootstrapBorderClasses {
    static func defaultValue(_ raw: PartPackageValue) -> ThemeBorderWidthValue? {
        var result = ThemeBorderWidthValue()
        func edge(_ raw: PartPackageValue) -> ThemeBorderWidthValue.EdgeValue? {
            guard case .string(let token) = raw, ["none", "0", "1"].contains(token) else { return nil }
            return .init(token: token)
        }
        if let shared = edge(raw) {
            result.setAll(shared)
            return result
        }
        guard case .object(let fields) = raw, Set(fields.keys) == ["top", "bottom", "left", "right"] else { return nil }
        result.unlinkAll()
        for side in ThemeBorderWidthValue.Edge.allCases {
            guard let rawValue = fields[side.key], let value = edge(rawValue) else { return nil }
            result.set(value, for: side)
        }
        return result
    }

    static func sides(_ value: ThemeBorderWidthValue) -> String {
        func token(_ edge: ThemeBorderWidthValue.Edge) -> String? {
            let item = value.value(for: edge)
            return !item.isCustom && ["0", "1"].contains(item.token) ? item.token : nil
        }
        func utility(_ suffix: String, _ value: String) -> String {
            "border" + suffix + (value == "0" ? "-0" : "")
        }
        let top = token(.top), bottom = token(.bottom), start = token(.left), end = token(.right)
        if let top, top == bottom, top == start, top == end { return utility("", top) }
        var classes: [String] = []
        if let top, top == bottom { classes.append(utility("-y", top)) }
        else {
            if let top { classes.append(utility("-top", top)) }
            if let bottom { classes.append(utility("-bottom", bottom)) }
        }
        if let start, start == end { classes.append(utility("-x", start)) }
        else {
            if let start { classes.append(utility("-start", start)) }
            if let end { classes.append(utility("-end", end)) }
        }
        return classes.joined(separator: " ")
    }
}

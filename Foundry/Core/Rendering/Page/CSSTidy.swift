import Foundation

/// Tidies generated stylesheet text without changing what it computes.
/// Template conditionals that render nothing leave blank lines behind, and
/// always-emitted scaffolding can produce rules whose bodies emptied out —
/// this pass removes both, and collapses repeated shorthand tuples
/// (`margin: 0 0 0 0` → `margin: 0`) so exports read like hand-written CSS.
nonisolated enum CSSTidy {
    static func tidy(_ css: String) -> String {
        let output = css
            .components(separatedBy: "\n")
            .map(trimmingTrailingWhitespace)
            .filter { !$0.isEmpty }
            .map(collapsingShorthandTuples)
            .joined(separator: "\n")
        return removingEmptyRules(from: output)
    }

    private static func trimmingTrailingWhitespace(_ line: String) -> String {
        var line = Substring(line)
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return String(line)
    }

    /// Removes rules whose bodies contain nothing but whitespace, e.g.
    /// `sel:hover {\n}` — including @media blocks left holding only empty
    /// rules, since children collapse before their parents close. A single
    /// linear pass over a block stack: this runs on every page's whole
    /// stylesheet, where the previous regex fixpoint dominated render time.
    private static func removingEmptyRules(from css: String) -> String {
        struct Frame {
            var selector: String
            var kept = ""
            var pending = ""
        }
        var root = Frame(selector: "")
        var stack: [Frame] = []
        for character in css {
            switch character {
            case "{":
                var parent = stack.last ?? root
                stack.append(Frame(selector: parent.pending))
                parent.pending = ""
                if stack.count > 1 { stack[stack.count - 2] = parent } else { root = parent }
            case "}" where !stack.isEmpty:
                let block = stack.removeLast()
                let body = block.kept + block.pending
                var parent = stack.last ?? root
                if body.allSatisfy(\.isWhitespace), block.selector.contains(where: { !$0.isNewline }) {
                    // Drop the rule with its selector, mirroring the old
                    // pattern's single optional preceding newline.
                    let newlines = block.selector.prefix { $0.isNewline }.count
                    parent.kept += String(repeating: "\n", count: max(0, newlines - 1))
                } else {
                    parent.kept += block.selector + "{" + body + "}"
                }
                if stack.isEmpty { root = parent } else { stack[stack.count - 1] = parent }
            default:
                if stack.isEmpty {
                    root.pending.append(character)
                } else {
                    stack[stack.count - 1].pending.append(character)
                }
            }
        }
        // Unbalanced opening braces (never produced by our renderers) fall
        // back to emitting the text unmodified from that point.
        var output = root.kept + root.pending
        for frame in stack { output += frame.selector + "{" + frame.kept + frame.pending }
        return output
    }

    private static let declaration = try! NSRegularExpression(pattern: #"^(\s*[-A-Za-z]+\s*:\s*)([^;{}]+);$"#)
    /// Values safe to compare as tuple members: keywords, lengths, colours and
    /// custom-property references. Anything else (calc, url, strings) opts the
    /// declaration out of collapsing.
    private static let safeToken = try! NSRegularExpression(pattern: #"^(?:-?[\w.%#]+|var\(--[\w-]+\))$"#)

    private static func collapsingShorthandTuples(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = declaration.firstMatch(in: line, range: range),
              match.range == range,
              let head = Range(match.range(at: 1), in: line),
              let value = Range(match.range(at: 2), in: line) else { return line }
        let tokens = line[value].split(separator: " ").map(String.init)
        guard tokens.count > 1, tokens.allSatisfy({ token in
            safeToken.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil
        }) else {
            return line
        }
        let collapsed: [String]
        switch (tokens.count, tokens) {
        case (2, let t) where t[0] == t[1]:
            collapsed = [t[0]]
        case (3, let t) where t[0] == t[2]:
            collapsed = t[0] == t[1] ? [t[0]] : [t[0], t[1]]
        case (4, let t) where t[0] == t[2] && t[1] == t[3]:
            collapsed = t[0] == t[1] ? [t[0]] : [t[0], t[1]]
        default:
            return line
        }
        return line[head] + collapsed.joined(separator: " ") + ";"
    }
}

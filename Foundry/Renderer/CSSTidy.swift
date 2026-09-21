import Foundation

/// Tidies generated stylesheet text without changing what it computes.
/// Template conditionals that render nothing leave blank lines behind, and
/// always-emitted scaffolding can produce rules whose bodies emptied out —
/// this pass removes both, and collapses repeated shorthand tuples
/// (`margin: 0 0 0 0` → `margin: 0`) so exports read like hand-written CSS.
nonisolated enum CSSTidy {
    static func tidy(_ css: String) -> String {
        var output = css
            .components(separatedBy: "\n")
            .map(trimmingTrailingWhitespace)
            .filter { !$0.isEmpty }
            .map(collapsingShorthandTuples)
            .joined(separator: "\n")
        // Innermost-first so an @media block left holding only empty rules
        // collapses away on a later pass.
        while true {
            let cleaned = removingEmptyRules(from: output)
            if cleaned == output { break }
            output = cleaned
        }
        return output
    }

    private static func trimmingTrailingWhitespace(_ line: String) -> String {
        var line = Substring(line)
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return String(line)
    }

    /// A rule whose body contains nothing but whitespace, e.g. `sel:hover {\n}`.
    private static let emptyRule = /\n?[^{}\n][^{}]*\{\s*\}/

    private static func removingEmptyRules(from css: String) -> String {
        css.replacing(emptyRule, with: "")
    }

    private static let declaration = /^(\s*[-A-Za-z]+\s*:\s*)([^;{}]+)(;)$/
    /// Values safe to compare as tuple members: keywords, lengths, colours and
    /// custom-property references. Anything else (calc, url, strings) opts the
    /// declaration out of collapsing.
    private static let safeToken = /^(?:-?[\w.%#]+|var\(--[\w-]+\))$/

    private static func collapsingShorthandTuples(_ line: String) -> String {
        guard let match = line.wholeMatch(of: declaration) else { return line }
        let tokens = match.2.split(separator: " ").map(String.init)
        guard tokens.count > 1, tokens.allSatisfy({ $0.wholeMatch(of: safeToken) != nil }) else {
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
        return match.1 + collapsed.joined(separator: " ") + match.3
    }
}

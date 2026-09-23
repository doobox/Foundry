import CryptoKit
import Foundation

/// Applies optional publish-only transformations. Every transformation is
/// conservative: when safety cannot be established, the original bytes win.
nonisolated enum PublishedOutputProcessor {
    static func process(_ files: [SiteExportFile], for site: Site) -> [SiteExportFile] {
        var output = files.map { file in
            guard site.minifiesGeneratedOutput,
                  let source = String(data: file.data, encoding: .utf8) else { return file }
            let path = file.path.lowercased()
            let transformed = path.hasSuffix(".css")
                ? conservativeCSS(source)
                : path.hasSuffix(".js") ? conservativeJavaScript(source) : nil
            guard let minified = transformed,
                  minified.utf8.count < source.utf8.count else { return file }
            return SiteExportFile(path: file.path, contents: minified)
        }
        guard site.generatesCacheBustingLinks else { return output }

        let versions = Dictionary(uniqueKeysWithValues: output.compactMap { file -> (String, String)? in
            let path = file.path.lowercased()
            guard path.hasSuffix(".css") || path.hasSuffix(".js") else { return nil }
            let fingerprint = file.contentFingerprint ?? digest(file.data)
            return (file.path, String(fingerprint.prefix(12)))
        })
        output = output.map { file in
            let lowercasedPath = file.path.lowercased()
            guard lowercasedPath.hasSuffix(".html") || lowercasedPath.hasSuffix(".php"),
                  var html = String(data: file.data, encoding: .utf8) else { return file }
            for (resourcePath, version) in versions {
                let reference = relativePath(to: resourcePath, from: file.path)
                html = html.replacingOccurrences(of: "\"\(reference)\"", with: "\"\(reference)?v=\(version)\"")
                html = html.replacingOccurrences(of: "'\(reference)'", with: "'\(reference)?v=\(version)'")
            }
            return SiteExportFile(path: file.path, contents: html)
        }
        return output
    }

    private static func relativePath(to resourcePath: String, from documentPath: String) -> String {
        var documentDirectory = Array(documentPath.split(separator: "/").dropLast())
        var resourceComponents = Array(resourcePath.split(separator: "/"))
        while documentDirectory.first == resourceComponents.first,
              !documentDirectory.isEmpty, !resourceComponents.isEmpty {
            documentDirectory.removeFirst()
            resourceComponents.removeFirst()
        }
        return String(repeating: "../", count: documentDirectory.count)
            + resourceComponents.joined(separator: "/")
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// CSS treats runs of whitespace outside strings and comments as a token
    /// separator. We retain one separator instead of deleting it, preserve all
    /// comments, and reject malformed strings/comments or unbalanced groups.
    private static func conservativeCSS(_ source: String) -> String? {
        var result = ""
        var index = source.startIndex
        var quote: Character?
        var escaped = false
        var inComment = false
        var pendingWhitespace = false
        var stack: [Character] = []

        func matchingOpen(for close: Character) -> Character? {
            switch close {
            case "}": "{"
            case ")": "("
            case "]": "["
            default: nil
            }
        }

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : nil

            if inComment {
                result.append(character)
                if character == "*", next == "/" {
                    result.append("/")
                    index = source.index(after: nextIndex)
                    inComment = false
                } else {
                    index = nextIndex
                }
                continue
            }
            if let activeQuote = quote {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                index = nextIndex
                continue
            }
            if character == "/", next == "*" {
                if pendingWhitespace, !result.isEmpty { result.append(" ") }
                pendingWhitespace = false
                result.append("/*")
                index = source.index(after: nextIndex)
                inComment = true
                continue
            }
            if character == "\"" || character == "'" {
                if pendingWhitespace, !result.isEmpty { result.append(" ") }
                pendingWhitespace = false
                quote = character
                result.append(character)
                index = nextIndex
                continue
            }
            if character.isWhitespace {
                pendingWhitespace = true
                index = nextIndex
                continue
            }
            if let expected = matchingOpen(for: character) {
                guard stack.popLast() == expected else { return nil }
            } else if character == "{" || character == "(" || character == "[" {
                stack.append(character)
            }
            if pendingWhitespace, !result.isEmpty { result.append(" ") }
            pendingWhitespace = false
            result.append(character)
            index = nextIndex
        }
        guard quote == nil, !inComment, stack.isEmpty else { return nil }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only horizontal whitespace is reduced, and line breaks are retained so
    /// JavaScript automatic semicolon insertion cannot change. Slash-based
    /// constructs and template literals are deliberately left untouched; a
    /// full lexer is required to distinguish their meanings with certainty.
    private static func conservativeJavaScript(_ source: String) -> String? {
        guard !source.contains("/"), !source.contains("`") else { return nil }
        var result = ""
        var quote: Character?
        var escaped = false
        var pendingHorizontalWhitespace = false

        for character in source {
            if let activeQuote = quote {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                if pendingHorizontalWhitespace, !result.isEmpty, result.last != "\n", result.last != "\r" {
                    result.append(" ")
                }
                pendingHorizontalWhitespace = false
                quote = character
                result.append(character)
            } else if character == " " || character == "\t" {
                pendingHorizontalWhitespace = true
            } else {
                if pendingHorizontalWhitespace, !result.isEmpty,
                   result.last != "\n", result.last != "\r",
                   character != "\n", character != "\r" {
                    result.append(" ")
                }
                pendingHorizontalWhitespace = false
                result.append(character)
            }
        }
        guard quote == nil else { return nil }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

/// Tidies opening tags only; never minifies text or embedded source code.
nonisolated enum HTMLTagWhitespaceCleanup {
    static func clean(_ html: String) -> String {
        // Server-side code may generate partial tags. Leave those documents intact.
        guard !html.contains("<?"), !html.contains("<%") else { return html }
        let bytes = Array(html.utf8)
        var output = [UInt8]()
        output.reserveCapacity(bytes.count)
        var index = 0
        var rawElement: String?
        let rawElements: Set<String> = ["script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "noscript"]
        while index < bytes.count {
            guard bytes[index] == 60 else {
                output.append(bytes[index]); index += 1; continue
            }
            if let raw = rawElement {
                let prefix = Array(("</" + raw).utf8)
                let end = index + prefix.count
                guard end < bytes.count,
                      zip(bytes[index..<end], prefix).allSatisfy({ lower($0.0) == $0.1 }),
                      space(bytes[end]) || bytes[end] == 62 || bytes[end] == 47 else {
                    output.append(bytes[index]); index += 1; continue
                }
                rawElement = nil
            }
            if bytes[index...].starts(with: Array("<!--".utf8)) {
                var end = index + 4
                while end + 2 < bytes.count && !(bytes[end] == 45 && bytes[end + 1] == 45 && bytes[end + 2] == 62) { end += 1 }
                end = min(end + 3, bytes.count)
                output.append(contentsOf: bytes[index..<end]); index = end; continue
            }
            if bytes[index...].starts(with: Array("<![CDATA[".utf8)) {
                var end = index + 9
                while end + 2 < bytes.count && !(bytes[end] == 93 && bytes[end + 1] == 93 && bytes[end + 2] == 62) { end += 1 }
                end = min(end + 3, bytes.count)
                output.append(contentsOf: bytes[index..<end]); index = end; continue
            }
            guard index + 1 < bytes.count,
                  letter(bytes[index + 1]) || [33, 47].contains(bytes[index + 1]) else {
                output.append(bytes[index]); index += 1; continue
            }
            var end = index + 1
            var quote: UInt8?
            while end < bytes.count {
                let byte = bytes[end]
                if let current = quote {
                    if byte == current { quote = nil }
                } else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { break }
                end += 1
            }
            guard end < bytes.count else {
                output.append(contentsOf: bytes[index...]); break
            }
            if letter(bytes[index + 1]) {
                let tag = Array(bytes[index...end])
                var nameEnd = 1
                while nameEnd < tag.count && !space(tag[nameEnd]) && tag[nameEnd] != 47 && tag[nameEnd] != 62 { nameEnd += 1 }
                let name = String(decoding: tag[1..<nameEnd].map(lower), as: UTF8.self)
                output.append(contentsOf: cleanTag(tag, nameEnd: nameEnd))
                if name == "plaintext" {
                    output.append(contentsOf: bytes[(end + 1)...]); break
                }
                if rawElements.contains(name) { rawElement = name }
            } else {
                output.append(contentsOf: bytes[index...end])
            }
            index = end + 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func cleanTag(_ tag: [UInt8], nameEnd: Int) -> [UInt8] {
        var output = Array(tag[..<nameEnd])
        var index = nameEnd
        var lastValueWasUnquoted = false
        while index < tag.count {
            let separator = index
            while index < tag.count && space(tag[index]) { index += 1 }
            guard index < tag.count else { return tag }
            if tag[index] == 62 {
                output.append(62); return output
            }
            if tag[index] == 47 && index + 1 == tag.count - 1 {
                // Without this separator, '/' becomes part of an unquoted value.
                if lastValueWasUnquoted { output.append(32) }
                output.append(contentsOf: [47, 62]); return output
            }
            guard index > separator else { return tag }
            let nameStart = index
            while index < tag.count && !space(tag[index]) && ![61, 47, 62].contains(tag[index]) {
                guard ![34, 39, 60, 96].contains(tag[index]) else { return tag }
                index += 1
            }
            guard index > nameStart else { return tag }
            let nameEnd = index
            var equal = index
            while equal < tag.count && space(tag[equal]) { equal += 1 }
            guard equal < tag.count else { return tag }
            if tag[equal] != 61 {
                output.append(contentsOf: tag[separator..<index])
                lastValueWasUnquoted = false
                continue
            }
            index = equal + 1
            while index < tag.count && space(tag[index]) { index += 1 }
            guard index < tag.count else { return tag }
            let quoted = tag[index] == 34 || tag[index] == 39
            let quote = tag[index]
            if quoted { index += 1 }
            let valueStart = index
            while index < tag.count && (quoted ? tag[index] != quote : !space(tag[index]) && tag[index] != 62) { index += 1 }
            guard index < tag.count, quoted || index > valueStart else { return tag }
            let valueEnd = index
            if quoted { index += 1 }
            let isClass = tag[nameStart..<nameEnd].map(lower) == Array("class".utf8)
            if isClass && quoted {
                let tokens = tag[valueStart..<valueEnd].split(whereSeparator: space)
                if tokens.isEmpty { continue }
                output.append(contentsOf: tag[separator..<valueStart])
                for (offset, token) in tokens.enumerated() {
                    if offset > 0 { output.append(32) }
                    output.append(contentsOf: token)
                }
                output.append(quote)
            } else {
                output.append(contentsOf: tag[separator..<index])
            }
            lastValueWasUnquoted = !quoted
        }
        return tag
    }

    private static func space(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }
    private static func lower(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
    private static func letter(_ byte: UInt8) -> Bool { (97...122).contains(lower(byte)) }
}

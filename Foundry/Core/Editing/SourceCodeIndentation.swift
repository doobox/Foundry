import Foundation

nonisolated enum SourceCodeIndentation {
    struct Edit {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    static func edit(_ text: String, selection: NSRange, unindent: Bool) -> Edit? {
        let source = text as NSString
        guard selection.location != NSNotFound, selection.location <= source.length,
              selection.length <= source.length - selection.location else { return nil }
        if selection.length == 0, !unindent {
            return Edit(range: selection, replacement: "  ", selection: NSRange(location: selection.location + 2, length: 0))
        }
        let start = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        // Ending at the start of a line must not indent that next line too.
        let last = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        let end = NSMaxRange(source.lineRange(for: NSRange(location: last, length: 0)))
        let range = NSRange(location: start, length: end - start)
        var replacement = ""
        var cursor = start
        var firstRemoved = 0
        repeat {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            let line = source.substring(with: lineRange)
            if unindent {
                let removed = line.hasPrefix("\t") ? 1 : line.prefix(2).prefix(while: { $0 == " " }).count
                replacement += String(line.dropFirst(removed))
                if cursor == start { firstRemoved = removed }
            } else {
                replacement += "  " + line
            }
            cursor = NSMaxRange(lineRange)
        } while cursor < end
        guard replacement != source.substring(with: range) else { return nil }
        let updatedSelection = selection.length == 0
            ? NSRange(location: max(start, selection.location - firstRemoved), length: 0)
            : NSRange(location: start, length: (replacement as NSString).length)
        return Edit(range: range, replacement: replacement, selection: updatedSelection)
    }
}

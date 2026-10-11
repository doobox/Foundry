import Foundation
import Testing
@testable import Foundry

struct SourceCodeIndentationTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func selectedLinesRoundTrip(newline: String) throws {
        let source = "<div>" + newline + "  🐈 café" + newline + "</div>"
        let range = NSRange(location: 0, length: (source as NSString).length)
        let indent = try #require(SourceCodeIndentation.edit(source, selection: range, unindent: false))
        #expect(indent.replacement == "  <div>" + newline + "    🐈 café" + newline + "  </div>")
        let unindent = try #require(SourceCodeIndentation.edit(indent.replacement, selection: indent.selection, unindent: true))
        #expect(unindent.replacement == source)
        #expect(unindent.selection == range)
    }

    @Test func selectionEndingAtNextLineStartExcludesThatLine() throws {
        let edit = try #require(SourceCodeIndentation.edit("one\ntwo\nthree", selection: NSRange(location: 1, length: 3), unindent: false))
        #expect(edit.range == NSRange(location: 0, length: 4))
        #expect(edit.replacement == "  one\n")
        #expect(edit.selection == NSRange(location: 0, length: 6))
    }

    @Test func caretInsertsSpacesWithoutReplacingText() throws {
        let edit = try #require(SourceCodeIndentation.edit("abc", selection: NSRange(location: 1, length: 0), unindent: false))
        #expect(edit.range == NSRange(location: 1, length: 0))
        #expect(edit.replacement == "  ")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test func unindentRemovesTabsAndPartialSpaceIndents() throws {
        let source = "\tone\n two\n    three\nfour"
        let edit = try #require(SourceCodeIndentation.edit(source, selection: NSRange(location: 0, length: (source as NSString).length), unindent: true))
        #expect(edit.replacement == "one\ntwo\n  three\nfour")
    }

    @Test func unindentCaretStaysOnCurrentLine() throws {
        let edit = try #require(SourceCodeIndentation.edit("one\n  two", selection: NSRange(location: 5, length: 0), unindent: true))
        #expect(edit.range == NSRange(location: 4, length: 5))
        #expect(edit.replacement == "two")
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }

    @Test func emptyEditorAndAlreadyUnindentedText() throws {
        let edit = try #require(SourceCodeIndentation.edit("", selection: NSRange(location: 0, length: 0), unindent: false))
        #expect(edit.replacement == "  ")
        #expect(SourceCodeIndentation.edit("", selection: NSRange(location: 0, length: 0), unindent: true) == nil)
        #expect(SourceCodeIndentation.edit("abc", selection: NSRange(location: 0, length: 3), unindent: true) == nil)
    }

    @Test func invalidSelectionIsIgnored() {
        #expect(SourceCodeIndentation.edit("abc", selection: NSRange(location: NSNotFound, length: 0), unindent: false) == nil)
        #expect(SourceCodeIndentation.edit("abc", selection: NSRange(location: 2, length: 5), unindent: false) == nil)
    }
}

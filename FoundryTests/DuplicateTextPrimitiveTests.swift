import Foundation
import Testing
@testable import Foundry

/// A Build 11 report: two `text("item")` macros crashed Foundry before the
/// validator could report them. Duplicate names must never crash; the part is
/// rejected at load with a diagnostic the developer can read.
struct DuplicateTextPrimitiveTests {
    private func makePackage(controls: String = "", template: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "DuplicateNames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Resources"), withIntermediateDirectories: true)
        let manifest = """
        {"minimumAPIVersion":1,"id":"uk.co.example.duplicate","title":"Duplicate","version":"1.0.0",
         "description":"Test","group":"Content","inspector":[\(controls)],"templates":{"html":"part.html"}}
        """
        try manifest.write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        try template.write(to: root.appending(path: "Resources/part.html"), atomically: true, encoding: .utf8)
        return root
    }

    private func rejectionMessages(for url: URL) -> [String] {
        do {
            _ = try PartPackageLoader.loadWithDiagnostics(from: url)
            return []
        } catch PartPackageLoadingError.invalid(let diagnostics) {
            return diagnostics.filter { $0.severity == .error }.map(\.message)
        } catch {
            return ["\(error)"]
        }
    }

    @Test(arguments: [
        // The reported case: two editable macros with the same name.
        ("", #"<ul class="{{ part.class }}" {{ part.attributes }}><li>{{ text("item", default: "Item Name") }}</li><li>{{ text("item", default: "Item Name") }}</li></ul>"#,
         "'item' is used more than once"),
        // Two controls sharing an id; this used to crash the validator itself.
        (#"{"type":"text","id":"title","defaults":{"xs":"A"}},{"type":"text","id":"title","defaults":{"xs":"B"}}"#,
         #"<p class="{{ part.class }}" {{ part.attributes }}>{{ control.title }}</p>"#,
         "Duplicate control identifier 'title'"),
        // Two number controls sharing an id; this used to crash while loading.
        (#"{"type":"number","id":"count","maximum":5,"defaults":{"xs":1}},{"type":"number","id":"count","maximum":9,"defaults":{"xs":2}}"#,
         #"<p class="{{ part.class }}" {{ part.attributes }}>{{ control.count }}</p>"#,
         "Duplicate control identifier 'count'"),
        // An editable macro named like a control.
        (#"{"type":"text","id":"title","defaults":{"xs":"A"}}"#,
         #"<p class="{{ part.class }}" {{ part.attributes }}>{{ text("title", default: "B") }}</p>"#,
         "conflicts with a custom control id")
    ])
    func duplicateNamesAreRejectedWithADiagnostic(_ controls: String, _ template: String, _ expected: String) throws {
        let url = try makePackage(controls: controls, template: template)
        defer { try? FileManager.default.removeItem(at: url) }
        let messages = rejectionMessages(for: url)
        #expect(messages.contains { $0.contains(expected) }, "\(messages)")
    }
}

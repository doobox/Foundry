import Foundation

/// The Controls sheet edits the entries of the manifest's inspector array.
/// The brackets stay in the stored source, so the package compiler always sees JSON.
enum HTMLPartControlsEditorText {
    static func body(from storedArray: String) -> String {
        let trimmed = storedArray.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[", trimmed.last == "]" else { return storedArray }
        return String(trimmed.dropFirst().dropLast())
    }

    static func storedArray(from body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "[]" : "[\(body)]"
    }
}

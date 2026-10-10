import Foundation

/// Only explicitly edited modes are stored. Untouched modes retain Bootstrap's
/// original expression, including live references to other theme tokens.
nonisolated struct BootstrapTokenColour: Codable, Equatable, Sendable {
    var light: BootstrapColourScale?
    var dark: BootstrapColourScale?

    func expression(default original: String) -> String {
        "light-dark(\(light?.base ?? original),\(dark?.base ?? original))"
    }
}

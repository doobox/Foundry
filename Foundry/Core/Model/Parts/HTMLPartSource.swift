import Foundation

nonisolated struct HTMLPartSource: Equatable, Hashable, Sendable {
    var html: String
    var css: String
    var javaScript: String
    var controls: String? = nil
}

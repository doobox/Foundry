import Foundation

nonisolated extension Double {
    var bootstrapCSSNumber: String {
        guard isFinite else { return "0" }
        return String(format: "%.8g", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

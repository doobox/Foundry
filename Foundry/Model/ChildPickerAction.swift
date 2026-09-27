import Foundation

nonisolated enum ChildPickerAction: Equatable {
    case unavailable
    case limitReached
    case add(PartType)
    case choose

    static func resolve(options: [PartType], childCount: Int, maximum: Int?) -> Self {
        guard !options.isEmpty else { return .unavailable }
        guard maximum.map({ childCount < $0 }) ?? true else { return .limitReached }
        if options.count == 1, let type = options.first { return .add(type) }
        return .choose
    }

    var isEnabled: Bool {
        switch self {
        case .add, .choose: true
        case .unavailable, .limitReached: false
        }
    }
}

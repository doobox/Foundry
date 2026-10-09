enum FrameworkDimensionScaleKind {
    case borderWidth
    case borderRadius
    case zIndex

    var isRadius: Bool { self == .borderRadius }

    var title: String {
        switch self {
        case .borderWidth: "Framework Border Widths"
        case .borderRadius: "Framework Corner Radii"
        case .zIndex: "Framework Stacking Order"
        }
    }

    var sectionTitle: String {
        switch self {
        case .borderWidth: "Border Width"
        case .borderRadius: "Border Radius"
        case .zIndex: "Stacking Order"
        }
    }

    var customTitle: String {
        switch self {
        case .borderWidth: "Custom Border Widths"
        case .borderRadius: "Custom Corner Radii"
        case .zIndex: "Custom Stacking Order"
        }
    }

    var unit: String {
        switch self {
        case .borderWidth, .borderRadius: "px"
        case .zIndex: ""
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .borderWidth: 0...20
        case .borderRadius: 0...100
        case .zIndex: 0...2_000
        }
    }

    var step: Double {
        switch self {
        case .borderWidth, .borderRadius: 0.5
        case .zIndex: 10
        }
    }

    func tokens(in framework: Framework) -> FrameworkDimensionTokens {
        switch self {
        case .borderWidth: framework.borderWidths
        case .borderRadius: framework.borderRadii
        case .zIndex: framework.zIndexes
        }
    }
}

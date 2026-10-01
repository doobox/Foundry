import SwiftUI

struct InspectorControlReset {
    let isEnabled: Bool
    let action: () -> Void
}

extension EnvironmentValues {
    @Entry var inspectorControlReset: InspectorControlReset? = nil
}

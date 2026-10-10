import SwiftUI

struct BootstrapTokenRow: View {
    let token: BootstrapEditorToken
    let value: String
    let editor: ProjectEditor

    var body: some View {
        if token.id.hasPrefix("box-shadow") {
            BootstrapShadowTokenRow(token: token, value: value, editor: editor)
        } else if value.hasPrefix("clamp(") {
            BootstrapFluidSizeRow(token: token, value: value, editor: editor)
        } else {
            BootstrapTokenValueRow(token: token, value: value, editor: editor)
        }
    }
}

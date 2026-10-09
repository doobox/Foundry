import SwiftUI

struct BootstrapShadowTokenRow: View {
    let token: BootstrapEditorToken
    let value: String
    let editor: ProjectEditor
    @State private var layers: [BootstrapShadowGeometry] = []

    var body: some View {
        DisclosureGroup(token.label) {
            VStack(spacing: 12) {
                ForEach(layers.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("Layer \(index + 1)").frame(width: 90, alignment: .leading)
                        VStack {
                            Text("X").font(.caption).foregroundStyle(.secondary)
                            FrameworkNumberField(title: "X", value: $layers[index].x, unit: layers[index].unit, step: 0.025, precision: 3)
                        }
                        VStack {
                            Text("Y").font(.caption).foregroundStyle(.secondary)
                            FrameworkNumberField(title: "Y", value: $layers[index].y, unit: layers[index].unit, step: 0.025, precision: 3)
                        }
                        VStack {
                            Text("Blur").font(.caption).foregroundStyle(.secondary)
                            FrameworkNumberField(title: "Blur", value: $layers[index].blur, unit: layers[index].unit, step: 0.025, precision: 3)
                        }
                        VStack {
                            Text("Spread").font(.caption).foregroundStyle(.secondary)
                            FrameworkNumberField(title: "Spread", value: $layers[index].spread, unit: layers[index].unit, step: 0.025, precision: 3)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }.padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .onAppear { layers = BootstrapShadowGeometry.parse(value) }
        .onChange(of: value) { _, updated in layers = BootstrapShadowGeometry.parse(updated) }
        .onChange(of: layers) { _, updated in
            guard updated != BootstrapShadowGeometry.parse(value), !updated.isEmpty,
                  updated.allSatisfy({ [$0.x, $0.y, $0.blur, $0.spread].allSatisfy(\.isFinite) && $0.blur >= 0 }) else { return }
            editor.setBootstrapToken(token, value: updated.map(\.css).joined(separator: ", "))
        }
    }
}

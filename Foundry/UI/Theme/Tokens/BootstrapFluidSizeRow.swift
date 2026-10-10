import SwiftUI

struct BootstrapFluidSizeRow: View {
    let token: BootstrapEditorToken
    let value: String
    let editor: ProjectEditor
    @State private var components: [Double] = []

    private static func parse(_ value: String) -> [Double] {
        let regex = try! NSRegularExpression(pattern: #"-?(?:\d+(?:\.\d+)?|\.\d+)(?=rem|vw)"#)
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            Range($0.range, in: value).flatMap { Double(value[$0]) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(token.label).fontWeight(.medium)
            if components.count == 4 {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 14) {
                        let label = ["Minimum", "Base", "Viewport", "Maximum"][index]
                        Text(label).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        ThemeSlider(value: $components[index], range: 0...max(10, components[index]), step: 0.025)
                            .accessibilityLabel("\(token.label) \(label)")
                        ThemeNumberField(title: label, value: $components[index], unit: index == 2 ? "vw" : "rem", step: 0.025, precision: 3)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear { components = Self.parse(value) }
        .onChange(of: value) { _, updated in components = Self.parse(updated) }
        .onChange(of: components) { _, updated in
            guard updated.count == 4, updated.allSatisfy({ $0.isFinite && $0 >= 0 }), updated != Self.parse(value), updated[0] <= updated[3] else { return }
            editor.setBootstrapToken(token, value: "clamp(\(updated[0].bootstrapCSSNumber)rem, \(updated[1].bootstrapCSSNumber)rem + \(updated[2].bootstrapCSSNumber)vw, \(updated[3].bootstrapCSSNumber)rem)")
        }
    }
}

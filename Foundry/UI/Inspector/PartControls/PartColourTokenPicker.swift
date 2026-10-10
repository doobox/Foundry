import SwiftUI

struct PartColourTokenPicker: View {
    let previews: [String: String]
    let sections: [String]
    let selectedID: String
    var palettes: [ColourPalette] = []
    var linksOnly = false
    var search = ""
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PartColourToken.groups(for: sections, palettes: palettes, linksOnly: linksOnly), id: \.0) { title, tokens in
                let matches = tokens.filter { search.isEmpty || PartColourToken.label($0, palettes: palettes, linksOnly: linksOnly).localizedCaseInsensitiveContains(search) || title.localizedCaseInsensitiveContains(search) }
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                        ForEach(matches, id: \.self) { token in
                            Button { select("token:" + token) } label: {
                                HStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: previews[token] ?? "#808080") ?? .gray)
                                        .frame(width: 24, height: 20)
                                    Text(PartColourToken.label(token, palettes: palettes, linksOnly: linksOnly))
                                    Spacer()
                                    if selectedID == "token:" + token {
                                        Image(systemName: "checkmark")
                                    }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(4)
    }
}

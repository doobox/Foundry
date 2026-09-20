import AppKit
import Observation
import SwiftUI

/// Palette editing state. The project view supplies document persistence through onChange;
/// previews and tests can still use this independently.
@Observable
final class FrameworkColourPreviewModel {
    private(set) var storedPalettes: [ColourPalette] {
        didSet {
            if !synchronizing, oldValue != storedPalettes { onChange?(storedPalettes, pendingSession) }
        }
    }
    @ObservationIgnored var onChange: (([ColourPalette], UUID?) -> Void)?
    private var synchronizing = false
    private var pendingSession: UUID?

    func synchronize(_ values: [ColourPalette]) {
        guard values != storedPalettes else { return }
        synchronizing = true
        storedPalettes = values
        lastEditSession = nil
        synchronizing = false
    }
    var palettes: [PreviewColourPalette] {
        get { storedPalettes.map { PreviewColourPalette(stored: $0) } }
        set { storedPalettes = newValue.map { $0.storedValue } }
    }
    private var lastEditSession: UUID?

    init(storedPalettes: [ColourPalette]? = nil) {
        self.storedPalettes = storedPalettes ?? PreviewColourPalette.samples.map { $0.storedValue }
    }

    func binding(for snapshot: PreviewColourPalette) -> Binding<PreviewColourPalette> {
        let id = snapshot.id
        return Binding(
            get: { self.storedPalettes.first(where: { $0.id == id }).map { PreviewColourPalette(stored: $0) } ?? snapshot },
            set: { value in
                guard let index = self.storedPalettes.firstIndex(where: { $0.id == id }) else { return }
                self.storedPalettes[index] = value.storedValue
            })
    }

    func delete(id: String) {
        storedPalettes.removeAll { $0.id == id && $0.origin == .custom }
    }

    func update(_ palette: PreviewColourPalette, session: UUID, undoManager: UndoManager?) {
        guard let index = storedPalettes.firstIndex(where: { $0.id == palette.id }) else { return }
        let stored = palette.storedValue
        guard storedPalettes[index] != stored else { return }
        if onChange == nil && lastEditSession != session {
            registerRestore(storedPalettes[index], undoManager: undoManager)
            lastEditSession = session
        }
        pendingSession = session
        storedPalettes[index] = stored
        pendingSession = nil
    }

    private func registerRestore(_ value: ColourPalette, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            guard let index = model.storedPalettes.firstIndex(where: { $0.id == value.id }) else { return }
            model.registerRestore(model.storedPalettes[index], undoManager: undoManager)
            model.storedPalettes[index] = value
            model.lastEditSession = nil
        }
        undoManager?.setActionName("Edit Colour")
    }

    func add() {
        let names = Set(storedPalettes.map(\.name))
        var number = 1
        while names.contains("New Colour \(number)") { number += 1 }
        storedPalettes.insert(PreviewColourPalette(name: "New Colour \(number)", hex: "#F97316", group: .custom).storedValue, at: 0)
    }

    func duplicate(_ palette: PreviewColourPalette) {
        var copy = palette
        if palette.group == .standard && !palette.single {
            copy.overrides = Dictionary(uniqueKeysWithValues: (0..<11).map {
                ($0, palette.colour(at: $0).hexString ?? "#000000")
            })
            copy.generated = false
        }
        copy.id = "custom.\(UUID().uuidString.lowercased())"
        let names = Set(storedPalettes.map(\.name))
        let base = palette.name + " Copy"
        copy.name = base
        var number = 2
        while names.contains(copy.name) {
            copy.name = "\(base) \(number)"
            number += 1
        }
        copy.group = .custom
        storedPalettes.insert(copy.storedValue, at: 0)
    }
}

struct PreviewColourPalette: Identifiable, Equatable {
    enum Group: String, CaseIterable {
        case custom = "Custom Colours", framework = "Framework Colours", standard = "Standard Colours"
    }
    static let steps = Array(1...11)
    var id = "custom.\(UUID().uuidString.lowercased())"
    var name: String
    var hex: String
    var group: Group
    var anchor = 5
    var lightDefaultShade = 5
    var darkDefaultShade = 5
    var generated = true
    var overrides: [Int: String] = [:]
    var single = false
    var softening = 0.0
    var reversed = false
    private var snapshot: ColourPalette?

    init(id: String = "custom.\(UUID().uuidString.lowercased())", name: String, hex: String,
         group: Group, anchor: Int = 5, lightDefaultShade: Int = 5, darkDefaultShade: Int? = nil, generated: Bool = true,
         overrides: [Int: String] = [:], single: Bool = false, softening: Double = 0,
         reversed: Bool = false) {
        self.id = id; self.name = name; self.hex = hex; self.group = group
        self.anchor = anchor; self.lightDefaultShade = lightDefaultShade; self.generated = generated
        self.darkDefaultShade = darkDefaultShade ?? 10 - lightDefaultShade
        self.overrides = overrides; self.single = single; self.softening = softening
        self.reversed = reversed
    }

    init(stored: ColourPalette) {
        id = stored.id; name = stored.name
        switch stored.origin {
        case .custom: group = .custom
        case .framework: group = .framework
        case .standard: group = .standard
        }
        lightDefaultShade = stored.lightDefaultShade.rawValue - 1
        darkDefaultShade = stored.darkDefaultShade.rawValue - 1
        single = stored.single
        hex = stored.generation?.anchorHex ?? stored.colour(at: .default)
        anchor = (stored.generation?.anchor.rawValue ?? stored.lightDefaultShade.rawValue) - 1
        generated = stored.generation?.enabled ?? false
        softening = stored.generation?.softening ?? 0
        reversed = stored.generation?.reversed ?? false
        overrides = stored.generation?.overrides ?? Dictionary(uniqueKeysWithValues: stored.shades.enumerated().map { ($0.offset, $0.element) })
        snapshot = stored
    }

    private var generationSettings: ColourPalette.Generation {
        .init(algorithm: snapshot?.generation?.algorithm ?? "foundry.rgb-soften.v1",
              anchor: ColourShade(rawValue: anchor + 1)!, anchorHex: hex,
              softening: softening, reversed: reversed, enabled: generated, overrides: overrides)
    }

    var storedValue: ColourPalette {
        let origin: ColourPalette.Origin = group == .custom ? .custom : (group == .framework ? .framework : .standard)
        // Eleven values are always produced, and shade indices are editor-controlled.
        var value = try! ColourPalette(id: id, name: name, origin: origin,
            shades: (0..<11).map { colour(at: $0).hexString ?? "#000000" },
            lightDefaultShade: ColourShade(rawValue: lightDefaultShade + 1)!,
            darkDefaultShade: ColourShade(rawValue: darkDefaultShade + 1)!, generation: generationSettings)
        value.single = single
        return value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.hex == rhs.hex && lhs.group == rhs.group
        && lhs.anchor == rhs.anchor && lhs.lightDefaultShade == rhs.lightDefaultShade
        && lhs.darkDefaultShade == rhs.darkDefaultShade
        && lhs.generated == rhs.generated && lhs.overrides == rhs.overrides
        && lhs.single == rhs.single && lhs.softening == rhs.softening && lhs.reversed == rhs.reversed
    }

    func colour(at index: Int) -> Color {
        if let snapshot, snapshot.generation == generationSettings, snapshot.single == single {
            return Color(hex: snapshot.shades[index]) ?? .gray
        }
        if let value = overrides[index], !generated { return Color(hex: value) ?? .gray }
        guard let base = Color(hex: hex), let rgb = NSColor(base).usingColorSpace(.sRGB) else { return .gray }
        if single || index == anchor { return base }
        let position = reversed ? 10 - index : index
        let origin = reversed ? 10 - anchor : anchor
        // Keep the existing read-only sample palettes stable during generator experiments.
        let lighter = position < origin
        let fraction = lighter
            ? Double(origin - position) / Double(max(origin, 1)) * 0.94
            : Double(position - origin) / Double(max(10 - origin, 1)) * 0.85
        let target = lighter ? 1.0 : 0.0
        let fullRange = Color(.sRGB,
                     red: rgb.redComponent + (target - rgb.redComponent) * fraction,
                     green: rgb.greenComponent + (target - rgb.greenComponent) * fraction,
                     blue: rgb.blueComponent + (target - rgb.blueComponent) * fraction)
        guard group != .standard && softening > 0 else { return fullRange }
        let adaptive = PreviewPerceptualRamp.colour(base: rgb, offset: origin - position)
        return PreviewPerceptualRamp.blend(fullRange, adaptive, amount: softening)
    }

    mutating func reverseShades() {
        guard !single else { return }
        reversed.toggle()
        anchor = 10 - anchor
        lightDefaultShade = 10 - lightDefaultShade
        darkDefaultShade = 10 - darkDefaultShade
        overrides = Dictionary(uniqueKeysWithValues: overrides.map { (10 - $0.key, $0.value) })
    }

    mutating func setColour(_ colour: Color, at index: Int) {
        guard let value = colour.hexString else { return }
        if generated { hex = value; anchor = index }
        else { overrides[index] = value }
    }

    static var samples: [Self] {
        [Self(name: "Page", hex: "#F8FAFC", group: .framework, anchor: 0, lightDefaultShade: 0),
         Self(name: "Background", hex: "#F8FAFC", group: .framework, anchor: 0, lightDefaultShade: 0),
         Self(name: "Surface", hex: "#FFFFFF", group: .framework, anchor: 0, lightDefaultShade: 0),
         Self(name: "Text", hex: "#1E293B", group: .framework, anchor: 9, lightDefaultShade: 9),
         Self(name: "Muted Text", hex: "#64748B", group: .framework),
         Self(name: "Accent", hex: "#6366F1", group: .framework),
         Self(name: "Links", hex: "#2563EB", group: .framework, anchor: 6, lightDefaultShade: 6),
         Self(name: "Brand", hex: "#F97316", group: .custom),
         Self(name: "Black", hex: "#000000", group: .standard, single: true),
         Self(name: "White", hex: "#FFFFFF", group: .standard, single: true),
         // Familiar colour families, with shades generated by Foundry rather
         // than importing a framework's individually specified shade values.
         Self(name: "Red", hex: "#EF4444", group: .standard),
         Self(name: "Orange", hex: "#F97316", group: .standard),
         Self(name: "Amber", hex: "#F59E0B", group: .standard),
         Self(name: "Yellow", hex: "#EAB308", group: .standard),
         Self(name: "Lime", hex: "#84CC16", group: .standard),
         Self(name: "Green", hex: "#22C55E", group: .standard),
         Self(name: "Emerald", hex: "#10B981", group: .standard),
         Self(name: "Teal", hex: "#14B8A6", group: .standard),
         Self(name: "Cyan", hex: "#06B6D4", group: .standard),
         Self(name: "Sky", hex: "#0EA5E9", group: .standard),
         Self(name: "Blue", hex: "#3B82F6", group: .standard),
         Self(name: "Indigo", hex: "#6366F1", group: .standard),
         Self(name: "Violet", hex: "#8B5CF6", group: .standard),
         Self(name: "Purple", hex: "#A855F7", group: .standard),
         Self(name: "Fuchsia", hex: "#D946EF", group: .standard),
         Self(name: "Pink", hex: "#EC4899", group: .standard),
         Self(name: "Rose", hex: "#F43F5E", group: .standard),
         Self(name: "Slate", hex: "#64748B", group: .standard),
         Self(name: "Grey", hex: "#6B7280", group: .standard),
         Self(name: "Zinc", hex: "#71717A", group: .standard),
         Self(name: "Neutral", hex: "#737373", group: .standard),
         Self(name: "Stone", hex: "#78716C", group: .standard)].map { palette in
             var palette = palette
             if palette.group != .custom {
                 let prefix = palette.group == .framework ? "framework" : "standard"
                 palette.id = prefix + "." + palette.name.lowercased().replacingOccurrences(of: " ", with: "-")
             }
             return palette
         }
    }
}

struct FrameworkColoursPreview: View {
    @Bindable var model: FrameworkColourPreviewModel
    var canEditFramework = false
    var requestDelete: ((PreviewColourPalette) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(PreviewColourPalette.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(model.palettes.filter { $0.group == group }) { palette in
                                PreviewColourRibbon(palette: model.binding(for: palette),
                                    canEditFramework: canEditFramework,
                                    update: { value, session in model.update(value, session: session, undoManager: undoManager) },
                                    duplicate: {
                                        model.duplicate(palette)
                                        withAnimation { scrollPosition.scrollTo(edge: .top) }
                                    },
                                    delete: {
                                        if let requestDelete { requestDelete(palette) }
                                        else { model.delete(id: palette.id) }
                                    })
                        }
                        if group == .custom && !model.palettes.contains(where: { $0.group == .custom }) {
                            Text("Add a named colour to try your own palette.").foregroundStyle(.secondary)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(group.rawValue).font(.headline).accessibilityAddTraits(.isHeader)
                                Spacer()
                                if group == .custom {
                                    Button("Add Colour", systemImage: "plus", action: model.add)
                                }
                            }
                        }
                        .padding(.top, group == .custom ? 0 : 18)
                    }
                }
            }
            .padding(28)
        }
        .controlSize(.small)
        .scrollPosition($scrollPosition)
    }
}

/// Colour samples must stay accurate while pressed, not dim like ordinary buttons.
private struct PreviewSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct PreviewColourRibbon: View {
    @Binding var palette: PreviewColourPalette
    let canEditFramework: Bool
    let update: (PreviewColourPalette, UUID) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var editingShade: Int?
    @State private var editSession = UUID()
    @State private var confirmGenerated = false

    private var isEditable: Bool {
        palette.group == .custom || (palette.group == .framework && canEditFramework)
    }

    var body: some View {
        HStack(spacing: 12) {
                identity.frame(width: 150, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
                ribbon.frame(minWidth: 440)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Regenerate this palette?", isPresented: $confirmGenerated) {
            Button("Regenerate Shades", role: .destructive) {
                guard isEditable else { return }
                palette.overrides = [:]
                palette.generated = true
            }
        } message: { Text("Individual shade edits will be discarded.") }
        .onChange(of: canEditFramework) {
            if !isEditable {
                closeEditor()
                confirmGenerated = false
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if palette.group == .custom {
                    TextField("Colour name", text: $palette.name).textFieldStyle(.roundedBorder)
                } else { Text(palette.name).fontWeight(.medium) }
            }
            HStack(spacing: 6) {
                Button(action: duplicate) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate to Custom Colours")
                .accessibilityLabel("Duplicate \(palette.name) to Custom Colours")
                if palette.group == .custom {
                    Button(action: delete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Colour")
                    .accessibilityLabel("Delete \(palette.name)")
                }
                if isEditable {
                Picker("Palette mode", selection: Binding(
                    get: { palette.generated },
                    set: { generated in
                        if generated { confirmGenerated = true }
                        else { palette.generated = false }
                    })) {
                    Text("Generated").tag(true)
                    Text("Custom").tag(false)
                }.labelsHidden()
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var ribbon: some View {
        HStack(spacing: 0) {
            ForEach(palette.single ? [5] : Array(0..<11), id: \.self) { index in
                swatch(index)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func swatch(_ index: Int) -> some View {
        let displayed = palette
        let colour = displayed.colour(at: index)
        let rgb = NSColor(colour).usingColorSpace(.sRGB)
        let light = (rgb.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent } ?? 0) > 0.57
        let content = VStack(spacing: 4) {
            HStack(spacing: 3) {
                if !palette.single && palette.group != .standard {
                    if index == displayed.lightDefaultShade {
                        Image(systemName: "sun.max.fill")
                            .accessibilityHidden(true)
                    }
                    if index == displayed.darkDefaultShade {
                        Image(systemName: "moon.fill").accessibilityHidden(true)
                    }
                }
            }.font(.system(size: 9, weight: .medium)).frame(height: 12)
            Text(palette.single ? palette.name : String(PreviewColourPalette.steps[index]))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(light ? Color.black : Color.white)
        .frame(maxWidth: .infinity).frame(height: 62)
        .background { Rectangle().fill(colour) }
        .contentShape(Rectangle())
        return Group {
            if isEditable {
                Button { editSession = UUID(); editingShade = index } label: { content }
                    .buttonStyle(PreviewSwatchButtonStyle())
                    .popover(isPresented: Binding(get: { editingShade == index }, set: { if !$0 { closeEditor() } })) {
                        PreviewShadeEditor(
                            original: palette,
                            index: index,
                            change: {
                                guard editingShade == index, isEditable else { return }
                                update($0, editSession)
                            }
                        )
                        .onDisappear {
                            guard editingShade == index else { return }
                            closeEditor()
                        }
                    }
            } else {
                content
            }
        }
        .help("\(palette.name) · \(colour.hexString ?? "")\(index == displayed.lightDefaultShade ? " · Light default" : "")\(index == displayed.darkDefaultShade ? " · Dark default" : "")")
        .accessibilityLabel("\(palette.name), shade \(PreviewColourPalette.steps[index])\(index == displayed.lightDefaultShade ? ", light default" : "")\(index == displayed.darkDefaultShade ? ", dark default" : "")")
    }

    private func closeEditor() {
        editingShade = nil
    }
}

/// Validates transient text input before publishing live palette changes.
struct PreviewShadeEdit {
    var palette: PreviewColourPalette
    var index: Int
    var hex: String

    init(palette: PreviewColourPalette, index: Int) {
        self.palette = palette
        self.index = index
        hex = palette.colour(at: index).hexString ?? "#000000"
    }

    static func normalizedHex(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard [3, 6].contains(value.count), value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        return "#" + value.uppercased()
    }

    mutating func setHex(_ input: String) {
        hex = input
        guard let normalized = Self.normalizedHex(input), let colour = Color(hex: normalized) else { return }
        // Merely entering the existing value must not move the base shade.
        guard normalized != palette.colour(at: index).hexString?.uppercased() else { return }
        palette.setColour(colour, at: index)
    }

    mutating func setDefault(for appearance: SiteAppearance) {
        if appearance == .light { palette.lightDefaultShade = index }
        else { palette.darkDefaultShade = index }
    }

    mutating func setColour(_ colour: Color) {
        guard let value = colour.hexString else { return }
        setHex(value)
    }

    mutating func setSoftening(_ amount: Double) {
        let amount = min(1, max(0, amount))
        guard amount != palette.softening else { return }
        // Preserve the selected swatch when Soften is the first edit,
        // without moving the default or changing anything on opening.
        if palette.generated && palette.anchor != index {
            palette.setColour(palette.colour(at: index), at: index)
        }
        palette.softening = amount
        hex = palette.colour(at: index).hexString ?? hex
    }

    mutating func setReversed(_ value: Bool) {
        guard value != palette.reversed && !palette.single else { return }
        palette.reverseShades()
        index = 10 - index
        hex = palette.colour(at: index).hexString ?? hex
    }
}

struct PreviewShadeEditor: View {
    private enum FocusTarget: Hashable { case hex }
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: FocusTarget?
    @State private var hexFrame = CGRect.zero
    let original: PreviewColourPalette
    let index: Int
    let change: (PreviewColourPalette) -> Void
    @State private var edit: PreviewShadeEdit

    init(original: PreviewColourPalette, index: Int,
         change: @escaping (PreviewColourPalette) -> Void) {
        self.original = original
        self.index = index
        self.change = change
        _edit = State(initialValue: PreviewShadeEdit(palette: original, index: index))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(original.name) · \(PreviewColourPalette.steps[edit.index])").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close the popover. Live changes are kept.")
            }
            HStack(spacing: 10) {
                ColorPicker("Colour", selection: Binding(
                    get: { edit.palette.colour(at: edit.index) },
                    set: { focus = nil; edit.setColour($0); change(edit.palette) }), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Colour")
                    .fixedSize()
                TextField("#RRGGBB", text: Binding(
                    get: { edit.hex },
                    set: { edit.setHex($0); change(edit.palette) }))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Hex colour")
                    .focused($focus, equals: .hex)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("shadeEditor"))
                    } action: { hexFrame = $0 }
            }
            if PreviewShadeEdit.normalizedHex(edit.hex) == nil {
                Text("Enter 3 or 6 hexadecimal digits.").font(.caption).foregroundStyle(.red)
            }
            if !original.single {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Soften")
                        Spacer()
                        Text(edit.palette.softening, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { edit.palette.softening }, set: {
                        focus = nil; edit.setSoftening($0); change(edit.palette)
                    }), in: 0...1)
                    .accessibilityLabel("Soften")
                }
                .disabled(!edit.palette.generated)
                .help(edit.palette.generated ? "Soften the shade range" : "Soften is available in Generated mode")
            }
            Divider()
            HStack {
                if !original.single {
                    Toggle("Reverse", isOn: Binding(get: { edit.palette.reversed }, set: {
                        focus = nil; edit.setReversed($0); change(edit.palette)
                    }))
                    .toggleStyle(.switch)
                    .accessibilityLabel("Reverse shades")
                    .fixedSize()
                }
                Spacer()
                ForEach(SiteAppearance.allCases, id: \.self) { appearance in
                    Button {
                        focus = nil
                        edit.setDefault(for: appearance)
                        change(edit.palette)
                    } label: {
                        Image(systemName: appearance == .light ? "sun.max.fill" : "moon.fill")
                    }
                    .disabled((appearance == .light ? edit.palette.lightDefaultShade : edit.palette.darkDefaultShade) == edit.index)
                    .help(appearance == .light ? "Set Light Default" : "Set Dark Default")
                    .accessibilityLabel(appearance == .light ? "Set Light Default" : "Set Dark Default")
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .controlSize(.small)
        .coordinateSpace(name: "shadeEditor")
        .task {
            // Let presentation assign its initial focus before clearing it.
            // Run only on appearance, never in response to later user focus.
            await Task.yield()
            guard !Task.isCancelled else { return }
            focus = nil
        }
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("shadeEditor")).onEnded { value in
            if !hexFrame.contains(value.location), focus == .hex {
                focus = nil
            }
        })
        .onChange(of: original) { _, value in
            // Keep an open editor in sync with Undo/Redo without replacing
            // partially typed hex input after our own live updates.
            if value != edit.palette {
                edit = PreviewShadeEdit(palette: value, index: edit.index)
            }
        }
    }
}

#Preview {
    FrameworkColoursPreview(model: FrameworkColourPreviewModel()).frame(width: 760, height: 650)
}

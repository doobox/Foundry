import AppKit
import SwiftUI

/// The Create a New Project window: an Empty Project card plus a card per
/// site kit, grouped into Your Library and Development. Choosing a card
/// stamps a fresh untitled document; kits are never opened in place.
struct NewProjectChooserView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var creationErrorMessage: String?

    private var library: SiteKitLibrary { .shared }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ kit: SiteKit) -> Bool {
        query.isEmpty
            || kit.title.localizedCaseInsensitiveContains(query)
            || (kit.details?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private var libraryKits: [SiteKit] { library.libraryKits.filter(matches) }
    private var developmentKits: [SiteKit] { library.developmentKits.filter(matches) }

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create a New Project")
                    .font(.title2.weight(.semibold))
                Spacer()
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader("Your Library")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        if query.isEmpty {
                            EmptyProjectCard {
                                create { FoundryDocument() }
                            }
                        }
                        ForEach(libraryKits) { kit in
                            SiteKitCard(kit: kit) { create(from: kit) }
                        }
                    }
                    if !developmentKits.isEmpty {
                        sectionHeader("Development")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(developmentKits) { kit in
                                SiteKitCard(kit: kit) { create(from: kit) }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if !query.isEmpty, libraryKits.isEmpty, developmentKits.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { library.refresh() }
        .alert("Couldn’t Create the Project", isPresented: Binding(
            get: { creationErrorMessage != nil },
            set: { if !$0 { creationErrorMessage = nil } }
        )) {
            Button("OK") { creationErrorMessage = nil }
        } message: {
            Text(creationErrorMessage ?? "")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func create(from kit: SiteKit) {
        do {
            let document = try SiteKitLibrary.makeDocument(from: kit)
            create { document }
        } catch {
            creationErrorMessage = "The kit’s document couldn’t be read: \(error.localizedDescription)"
        }
    }

    private func create(_ document: @escaping () -> FoundryDocument) {
        newDocument(document)
        dismiss()
    }
}

/// The blank starting point — first card, and the Return key's default so
/// ⌘N then Return still means "new empty document".
private struct EmptyProjectCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProjectCardChrome(title: "Empty Project", details: "A fresh start.") {
                ZStack {
                    Rectangle().fill(.quinary)
                    Image(systemName: "document.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}

private struct SiteKitCard: View {
    let kit: SiteKit
    let action: () -> Void

    @State private var preview: NSImage?

    var body: some View {
        Button(action: action) {
            ProjectCardChrome(title: kit.title, details: kit.details ?? kit.packTitle) {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.quinary)
                        Image(systemName: "macwindow")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: kit.id) {
            guard let previewURL = kit.previewURL else { return }
            preview = NSImage(contentsOf: previewURL)
        }
    }
}

/// The shared card frame: a 16:10 artwork area over a title and one-line
/// description, hover-highlighted like the Elements chooser.
private struct ProjectCardChrome<Artwork: View>: View {
    let title: String
    let details: String
    @ViewBuilder let artwork: Artwork

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sizing the slot with Color.clear keeps a scaledToFill image
            // out of layout entirely — otherwise a wide image stretches the
            // card past the footer and leaves a gap at its trailing edge.
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { artwork }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovering ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isHovering ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovering = $0 }
    }
}

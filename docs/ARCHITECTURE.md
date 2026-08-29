# Foundry Architecture

Foundry is an independently designed native macOS visual website builder. Its architecture does not depend on proprietary page-builder code, file formats, or assets.

## Application layers

1. **Presentation** — SwiftUI windows, navigator, inspector, commands, and AppKit bridges. Views read document state and send edits through the editing layer.
2. **Editing** — undo-aware commands and pure component-tree mutations. This is the only layer that intentionally changes project content.
3. **Document** — macOS document lifecycle, content-type registration, JSON encoding, snapshots, coordinated reads/writes, dirty-state tracking, and autosave.
4. **Domain model** — Codable value types for sites, pages, component trees, properties, and themes. It has no UI or WebKit dependencies.
5. **Rendering** — renderer protocols and implementations that turn a page plus theme into preview/export artifacts.
6. **Canvas integration** — a narrow WKWebView adapter that displays renderer output. Browser-side selection and interaction can be added later without making WebKit the source of truth.

Dependencies point inward: presentation and adapters depend on editing/domain contracts; the domain model does not depend on UI, WebKit, exporters, extensions, or legacy formats.

## Workspace layout

The editor shell is a dockable workspace composed of stable panel identities, tab groups, and split columns. Pages, component library, page structure, canvas, and inspector are independent panels. The workspace supports tab movement between groups, left/right split docking, resetting the layout, and restoring the arrangement between launches. AppKit-managed detached panels host the same SwiftUI panel content; their geometry is persisted, and cross-window tab drags can redock them into a tab group or adjacent column.

Workspace layout is user preference state stored separately from project documents. Rearranging the editor never marks a website document as changed and does not affect collaborators opening the same project.

## Document model

A project is initially one UTF-8 JSON file with the .foundry extension. JSON is pretty-printed with sorted keys for inspection, source control, and useful diffs.

Site is the root and contains a stable UUID, explicit schema version, site metadata, ordered pages, and theme tokens. Each Page has a stable UUID, title, slug, and ordered component forest. UUIDs are generated once at insertion and encoded. UI state such as selection, expansion, and scroll position is not persisted.

Schema migrations will run at the document boundary before decoded models reach the editor. If binary assets become part of projects, storage may evolve to a package while preserving the domain model.

## Component model

ComponentNode is a recursive value with stable UUID identity, ComponentType, user-facing name, typed properties, and ordered child nodes.

The built-in set includes Container, Section, Columns, Text, Heading, Button, Image, Divider, and Spacer. Tree traversal and mutation are domain operations independent of UI.

ComponentType is a Codable namespaced identifier resolved through an internal ComponentRegistry rather than a closed enum. The registry supplies ComponentDefinition descriptors containing display metadata, defaults, Inspector schemas, child policy, inline-edit capability, and render dispatch. Legacy `container`, `text`, and `button` identifiers migrate during decoding. Unknown identifiers and their trees remain preserved and render as explicit unavailable-component placeholders.

ComponentProperty uses a closed Codable key/value representation. This prevents untyped runtime values from leaking into documents. Reusable style-property definitions supply layout and appearance capabilities consistently across registered components; the library, Inspector, interaction bridge, and renderer consume the same descriptors. The internal registry is the architectural seam for a future versioned public manifest and isolated extension loader; it is not yet a third-party loading API.

## Theme and design tokens

A Theme contains semantic token groups: colors (background, surface, text, accent), spacing (small, medium, large), and typography (body family and base size).

Components refer to semantic intent rather than embedding HTML or CSS. Color and spacing properties may store either a fixed override or a typed DesignToken reference. Renderers resolve token references through the document Theme into their target format, while the dockable Theme panel edits those shared values through the same undoable document mutation path. Token schemas can expand with versioned migration while component identity and structure remain stable.

## Swift-to-WKWebView boundary

PageRendering is the Swift-side boundary. It accepts an immutable Page and Theme snapshot and returns a complete preview artifact, currently HTML.

WebCanvasView loads that artifact into WKWebView and installs a small Foundry-owned interaction script in an isolated WKContentWorld. Rendered components carry stable data-foundry-id attributes. Canvas clicks and drag placements cross the boundary as versioned CanvasMessage values. The browser reports only intent using before, after, inside, or end placement; Swift rejects malformed, unsupported, non-main-frame, unknown-component, invalid-child, and cyclic movement requests before applying undo-aware tree mutations. Inline Text and Button sessions remain ephemeral in the DOM until commit, when one validated final-value message becomes one native undo step; cancellation sends no mutation. Native selection is sent back to the isolated script to update the canvas highlight. Page-authored JavaScript remains disabled.

A future TypeScript runtime can replace the interaction script behind the same conceptual contract. Browser events must become validated editor commands before changing document content; arbitrary JavaScript objects never become persisted state and Swift remains authoritative.

## Preview and export pipeline

The shared conceptual pipeline is:

Site snapshot → page selection → renderer → HTML/CSS artifact → destination

Preview sends the artifact to WKWebView. Static export will write the same renderer output and assets to a chosen directory. Export is a pure projection: it must not mutate the project or depend on canvas state. Preview and export remain testable from model snapshots.

## Extension boundary

Future components or extension bundles integrate through explicit descriptors, property schemas, validation, editor contributions, and renderer providers. Extension code does not gain direct document access. Capability and version negotiation belongs at this boundary.

No plugin loading, marketplace, scripting, or third-party dependency mechanism is part of this slice.

## Legacy compatibility boundary

Compatibility with external or legacy formats is an adapter concern:

legacy input → isolated parser → validated intermediate representation → native Site model

Adapters must not introduce legacy types, identifiers, rendering assumptions, or lifecycle rules into the native domain. Export back to a legacy format, if supported, is a separate projection. Proprietary application code and assets are neither required nor reused.

# Foundry Architecture

Foundry is an independently designed native macOS visual website builder. Its architecture does not depend on proprietary page-builder code, file formats, or assets.

## Application layers

1. **Presentation** — AppKit document-window, toolbar, split-view and detached-panel ownership hosting SwiftUI navigator, canvas, inspector and panel content. Views read document state and send edits through the editing layer.
2. **Editing** — undo-aware commands and pure part-tree mutations. This is the only layer that intentionally changes project content.
3. **Document** — macOS document lifecycle, content-type registration, JSON encoding, snapshots, coordinated reads/writes, dirty-state tracking, and autosave.
4. **Domain model** — Codable value types for sites, pages, part trees, properties, and themes. It has no UI or WebKit dependencies.
5. **Rendering** — renderer protocols and implementations that turn a page plus theme into preview/export artifacts.
6. **Canvas integration** — a narrow WKWebView adapter that displays renderer output. Browser-side selection and interaction can be added later without making WebKit the source of truth.

Dependencies point inward: presentation and adapters depend on editing/domain contracts; the domain model does not depend on UI, WebKit, exporters, extensions, or legacy formats.

## Source layout

App source in `Foundry/` is split by layer. Xcode uses synchronized folders, so moving or adding a file needs no project-file change.

- `App/` — app entry point and app-wide preferences.
- `Core/` — everything that is not a view. No SwiftUI views live here.
  - `Model/Site`, `Model/Parts`, `Model/Theme` — Codable domain values.
  - `Document/` — document lifecycle, file types and validation.
  - `Editing/` — `ProjectEditor` and the undo-aware editing extensions. The only layer that changes project content.
  - `Bootstrap/Tokens` — Bootstrap 6 colour, layout, type and shadow token models. `Bootstrap/CSS` — the generated theme, colour, spacing and utility CSS, and control-group class mapping.
  - `PartPackages/Manifest`, `Templates`, `Resolvers` — part package loading and validation, the template language, and property/control-group resolvers.
  - `Rendering/Page`, `Rendering/Canvas`, `Rendering/Export` — page HTML, canvas scene and cache, static-site export and published output.
  - `Libraries/` — packs, reusable parts, theme and site-kit libraries, updates.
  - `Services/` — Google Fonts, remote/YouTube video, media import and thumbnails.
  - `Preview/`, `Publishing/` — local preview server and site publishing.
- `UI/` — SwiftUI and AppKit presentation only, grouped by screen area: `App`, `Workspace`, `Canvas`, `Navigator`, `Inspector` (with `PartControls`), `Assets`, `Editors`, `Theme` (`Colours`, `Tokens`, `Fonts`, `Layout`), `ProjectSettings` and `Shared`.
- `Resources/`, `ControlGroups/`, `PHPRuntime/`, `Assets.xcassets` — bundled resources.

Put new non-view types under `Core/` and new views under `UI/`. Keep one main type per file and name the file after it.

## Workspace layout

The editor shell is an AppKit-managed dockable workspace composed of stable panel identities, tab groups, split columns, a persistent sidebar dock, a canvas region and a persistent inspector dock. Pages, part library, page structure, resources and inspector content remain SwiftUI views hosted by AppKit controllers. The workspace supports tab movement and consolidation, left/right split docking, detached panel windows, resetting layouts, and named workspace snapshots including preferred column widths. Detached panels host the same SwiftUI content, preserve geometry, follow their owning document, and can redock into a tab group or adjacent column.

Workspace layout is user preference state stored separately from project documents. Rearranging the editor never marks a website document as changed and does not affect collaborators opening the same project.

## Document model

Reusable theme bundles use `ThemePreset` schema version 1: fixed Bootstrap colour
palettes, body/heading/monospace fonts and supported built-in colour overrides only.
`Theme` remains the resolved project styling model; it is not the bundle API.
`ProjectThemeValues` owns breakpoint switches and custom additions across theme
selection, reset, update and deletion. Preset comparison drives the Modified badge.
Legacy full-model bundles are read through the preset boundary, but new writes and
exports omit obsolete scales and project-owned settings. The official Bootstrap
stylesheet supplies native spacing steps 0–12. Space supports explicit custom
lengths; runtime theme changes do not compile Bootstrap. The sibling Bootstrap
checkout is retained for experiments and is not part of the application build.

A project is a document package with the `.foundry` extension. Its JSON model remains pretty-printed with sorted keys for inspection, source control, and useful diffs, while managed project assets live alongside it in the package.

Site is the root and contains a stable UUID, explicit schema version, publishing and site metadata, nested page/folder structure, theme tokens, reusable/global parts, project assets and installed part-package snapshots. Each Page has a stable UUID, title, slug, parent reference, metadata and ordered part forest. UUIDs are generated once at insertion and encoded. UI state such as selection, expansion and scroll position is not persisted.

Schema migrations run at the document boundary before decoded models reach the editor. Binary assets are represented by typed metadata in the domain model and data in the document package.

## Part model

PartNode is a recursive value with stable UUID identity, PartType, user-facing name, typed properties, and ordered child nodes.

The current built-in library is itself packaged as Foundry parts: Container, Controls, HTML, Image and Paragraph. Tree traversal and mutation are domain operations independent of UI.

PartType is a Codable namespaced identifier resolved through an internal PartRegistry rather than a closed enum. The registry supplies PartDefinition descriptors containing display metadata, defaults, Inspector schemas, child policy, inline-edit capability, and render dispatch. Legacy `container`, `text`, and `button` identifiers migrate during decoding. Unknown identifiers and their trees remain preserved and render as explicit unavailable-part placeholders.

PartProperty uses a closed Codable key/value representation. This prevents untyped runtime values from leaking into documents. The public part boundary is a validated `.foundrypack` / `.foundrydevpack` bundle (format version 2): a pack-level `manifest.json` plus typed `Parts/`, `Templates/`, and `Themes/` directories, where each part carries its own `manifest.json`, developer-owned templates, inspector-control declarations, slots and assets. The loader adapts a valid manifest into the same PartDefinition descriptors consumed by the library, Inspector, interaction bridge and renderer. Unknown package identifiers and missing-package snapshots remain preserved in documents.

## Theme and design tokens

A Theme contains semantic colour roles, an extensible spacing scale, body/heading/monospaced and custom fonts, standard/custom type sizes with line heights, and configurable responsive screens and container widths.

Parts refer to semantic intent rather than embedding HTML or CSS. Color and spacing properties may store either a fixed override or a typed DesignToken reference. Renderers resolve token references through the document Theme into their target format, while the dockable Theme panel edits those shared values through the same undoable document mutation path. Token schemas can expand with versioned migration while part identity and structure remain stable.

## Swift-to-WKWebView boundary

PageRendering is the Swift-side boundary. It accepts immutable site/page/theme snapshots and returns complete canvas or export artifacts including HTML, scoped styles, scripts, PHP and managed assets.

WebCanvasView loads the artifact into WKWebView and installs a Foundry-owned interaction script in an isolated WKContentWorld. Rendered parts carry stable `data-foundry-id` and `data-foundry-package` attributes. Canvas clicks, inline text/HTML edits, asset drops, deletions and drag placements cross the boundary as validated CanvasMessage values before becoming undo-aware Swift mutations. Part-authored JavaScript runs in the page world; the isolated editor bridge remains authoritative for document changes.

A future TypeScript runtime can replace the interaction script behind the same conceptual contract. Browser events must become validated editor commands before changing document content; arbitrary JavaScript objects never become persisted state and Swift remains authoritative.

## Preview and export pipeline

The shared conceptual pipeline is:

Site snapshot → page selection → renderer → HTML/CSS artifact → destination

The editing canvas sends an editor artifact to WKWebView. Browser preview and publishing use the static-site renderer, which writes route-aware HTML/PHP, page-local `files/page.css` and declared `files/page.js` artifacts, shared `files/site.css`, metadata, sitemaps, robots files and managed assets. JavaScript files are emitted from template declarations rather than guessed from rendered text. Managed Resource filenames are readable and receive a short stable identifier only when sanitized sibling names collide. Export is a pure projection: it does not mutate the project or depend on canvas state. The same export bundle feeds local browser preview and local, FTP/SFTP or S3 publishing. Local folder exports remove obsolete manifest-owned files by default, preserve locally modified output, prune only empty generated directories and reject unsafe or symlinked paths. Remote publishing never deletes server files.

## Extension boundary

Third-party parts integrate through explicit package manifests, property schemas, template validation and renderer artifacts. Package JavaScript and PHP execute only in website/preview contexts and do not gain native document, AppKit, filesystem or shell access. Native plugin loading and arbitrary extension binaries are outside this boundary.

## Legacy compatibility boundary

Compatibility with external or legacy formats is an adapter concern:

legacy input → isolated parser → validated intermediate representation → native Site model

Adapters must not introduce legacy types, identifiers, rendering assumptions, or lifecycle rules into the native domain. Export back to a legacy format, if supported, is a separate projection. Proprietary application code and assets are neither required nor reused.

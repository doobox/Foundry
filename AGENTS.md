# Foundry workspace notes

## Bootstrap 6 is the generated-site framework

Use Bootstrap 6's native markup, classes, component variants, theme classes,
colour names, tokens and defaults as the contract for generated sites.
Verify against the bundled Bootstrap 6 version and the official Bootstrap skills.
Do not assume Bootstrap 5 conventions still apply: a solid primary button uses
`btn btn-solid theme-primary`, not `btn btn-primary`.

Canvas editing identifiers and metadata must stay out of plain preview/export
markup. Preview and export share the clean Bootstrap output contract. Retain
output hooks only for authored styling or runtime behaviour that needs them.
The old Foundry CSS generator and old built-in parts are removed; do not restore
compatibility CSS. The baseline built-ins are Button, Container, Element, Flex, Grid, Paragraph, HTML, SVG, Image and Card. Element is a plain HTML wrapper whose tag is chosen in the Inspector; it adds no Bootstrap classes.
Card is the first ready-made Bootstrap component part: it composes native
component markup with a small, semantic inspector and maps choices to classes
in its template.
Inspector controls should select
Bootstrap themes, variants, sizes and tokens; avoid parallel Foundry styling
defaults or unconditional CSS that overrides Bootstrap's component states.
Custom styling must be explicit and use Bootstrap's supported extension points.
Breaking changes are accepted for this migration; remove obsolete contracts
instead of retaining compatibility styling. Work one section at a time, update
the matching developer docs, and verify computed browser styles as well as
generated markup before calling a component converted.

For each part's first switchover, strip its inspector to Bootstrap basics.
Keep only essential content, behaviour, accessibility and native Bootstrap
options. Remove legacy styling control groups; add extra capabilities back
progressively when Gary requests them.

## Bootstrap ships untouched; Foundry adds plain CSS

The bundled Bootstrap CSS and JS are byte-for-byte the official npm release,
pinned by checksum in `BootstrapBundledLibraryTests`. There is no Sass, Node or
npm step; update Bootstrap with `tools/bootstrap/update.sh <version>`.
Bootstrap's utility scales (spacing steps, text sizes, weights, numbered radii and
border widths, numeric z-index) are fixed because Bootstrap bakes them into its
utilities. The theme editor shows Colours, Fonts and Extensions.
Extensions holds project-named additions to the fixed scales. There is no global
Advanced section or saved global component override API. Component and layout
overrides belong to individual parts; Bootstrap supplies their defaults. Foundry's own
responsive text and wrapping variants and container caps come from
`BootstrapUtilityExtensionsCSS`, emitted after Bootstrap in the same layers.

## Source layout

App code is split into `Foundry/App`, `Foundry/Core` (models, editing, Bootstrap, part packages, rendering, services; no views) and `Foundry/UI` (views only, grouped by screen area). See "Source layout" in `ARCHITECTURE.md` before adding or moving files. Put each new type in the folder for its layer, one main type per file.

## Built-in inspector order

Keep shared sections in this relative order, omitting those a part does not use:
Content (including source/icon controls), Action, Appearance, Layout (including
Container/Flex/Grid), Sizing, Alignment, Gap, Spacing, Typography, Foreground,
Background, Borders, Shadows, Links, Display, Advanced. Object fit follows Sizing;
Content typography (Prose) follows Typography; Accessibility precedes Advanced.
Use the same Typography and Foreground titles across parts. Third-party manifests
retain their declared order. Reuse the Bootstrap sizing group; do not duplicate
Container's width behaviour or Button's specialised fit/full-width control.

## Built-in theme artwork

Always ask Gary for a supplied tile image when creating a built-in theme. Do not generate or substitute fallback artwork. See `.cursor/rules/framework-artwork.mdc`.

## API documentation

The Foundry application and its browsable developer documentation are separate sibling Git repositories:

- This repository: `Mac/Foundry/app` (`doobox/Foundry`)
- Documentation repository: `Mac/Foundry/docs` (`doobox/foundry-docs`) — user guide in `guide/`, part developer API in `developer/`

Do not look for or reconstruct a `docs` directory in this repository. The historical in-repository docs were removed after the separate documentation repository was created.

When asked to open, preview, serve, edit, or update the API docs, use the current working tree of the workspace sibling `docs` repository, including its uncommitted changes. Start it with:

```sh
./scripts/serve-docs
```

The command in this repository delegates to the docs repository's supported preview script. The preview URL is `http://127.0.0.1:4000/`.

Before adding, editing or restructuring documentation, read and follow the canonical documentation charter in the sibling repository's `AGENTS.md`. Do not proceed from conventions inferred from an old preview or archived copy.

Never serve an archived Git revision or the public GitHub Pages site as the local docs unless the user explicitly requests that version.

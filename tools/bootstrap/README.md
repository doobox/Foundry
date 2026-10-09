# Foundry Bootstrap stylesheet build

Sass is a developer build tool only. Foundry does not ship Node or Sass, compile
styles during editing, or store compiled CSS in a framework document.

From the app repository root:

```sh
npm ci --prefix tools/bootstrap --ignore-scripts --omit=peer
npm run build --prefix tools/bootstrap
npm test --prefix tools/bootstrap
```

`live.scss` configures Bootstrap 6.0.0-alpha.1 through its native Sass maps.
Its spacing values reference `--spacer`, preserving Bootstrap's numeric steps,
native classes, logical edges, negative-margin values and responsive variants.
Container maximum widths reference CSS variables with Bootstrap defaults as
fallbacks. Breakpoint thresholds remain the upstream defaults.

`compiler.mjs` uses Dart Sass Embedded and Bootstrap's PostCSS prefixer plus
Autoprefixer. The resulting `--bs-`-prefixed stylesheet is checked in as
`Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/bootstrap-6.0.0-alpha.1-live.min.css`.
Rebuild it when changing the Sass configuration or pinned dependencies. Normal
Xcode builds need neither npm nor a compiler archive.

`BootstrapThemeCSS` emits the small runtime settings sheet shared by canvas,
preview and export. The base spacer stays at `1rem`; named additions update
`--bs-spacer-NAME`. `BootstrapSpacingCSS` emits the extended spacing families
in Bootstrap's utility layer and breakpoint order, preserving responsive
precedence between standard and custom sizes. Disabled container sizes
inherit the preceding enabled maximum, or `none` if no maximum is enabled.
XL and 2XL are disabled by default. Canvas patches the framework style element
in place, leaving the prepared Bootstrap stylesheet unchanged.

Spacing values and breakpoint switches persist as ordinary model settings and
support undo. Old base-spacer settings reset to the fixed default; old compiled
payloads are ignored and are not written again. Colours continue to use their
native Bootstrap token override sheet. Other framework sections still require
their own Bootstrap migration; this is not a blanket runtime-token conversion.

Tests cover computed browser styles, custom spacers, all 32 switch combinations,
native responsive classes, persistence, undo and canvas/preview/export parity.

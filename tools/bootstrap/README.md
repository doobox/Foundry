# Bootstrap in Foundry

Foundry ships Bootstrap exactly as the Bootstrap team publishes it. There is no
Sass, Node or npm step anywhere in the project.

## What is bundled

`Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources` holds three files
copied byte-for-byte from the pinned npm release:

- `bootstrap-<version>.min.css` and `bootstrap.min.css.map`
- `bootstrap-<version>.bundle.min.js`

`FoundryTests/BootstrapBundledLibraryTests.swift` pins their checksums and checks
for the selectors Foundry relies on. Never edit these files by hand.

## How Foundry adds to Bootstrap

Everything Foundry contributes is plain CSS emitted by Swift after Bootstrap's
sheet, in the same cascade layers:

- `BootstrapColorCSS` emits edited colours and custom theme classes.
- `BootstrapEditorCSS` emits edited component variables and the utilities for
  project-named additions such as `text-hero` or `rounded-soft`.
- `BootstrapSpacingCSS` emits the spacing families only when a site has custom
  spacers, so a custom base value and a Bootstrap responsive step cascade correctly.
- `BootstrapUtilityExtensionsCSS` emits the responsive text size, weight and
  wrapping variants Bootstrap does not generate, and caps `.container` when a
  framework disables a breakpoint.

Bootstrap's utility scales (spacing steps, text sizes, weights, numbered radii and
border widths, numeric z-index) are fixed, because Bootstrap bakes their values
into the utility classes. The framework editor edits only variables that
Bootstrap's components read.

## Updating Bootstrap

```sh
tools/bootstrap/update.sh 6.0.0-beta.1
```

The script downloads the npm tarball, keeps the whole package (including the Sass
source) under `tools/bootstrap/upstream/` for reference, and copies the dist files
into the bundle under versioned names. It then prints the steps that remain:
update the version in `FoundryWebLibraryRegistry`, update the version and
checksums in `BootstrapBundledLibraryTests`, run the Bootstrap browser tests, and
review `BootstrapUtilityExtensionsCSS` against the release's utilities. Upstream
selector or token changes can still require adapting Foundry's additions,
especially between alpha releases.

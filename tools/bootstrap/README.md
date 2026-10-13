# Bootstrap distribution

Foundry bundles the official Bootstrap CSS and JavaScript release. The sibling
`../bootstrap` checkout is retained for future development, but is not used by
canvas, preview, publishing or the Xcode build.

## Bundled files

`Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources` contains:

- `bootstrap-<version>.min.css`: the official stylesheet used by all renderers.
- `bootstrap.min.css.map`: the upstream reference source map.
- `bootstrap-<version>.bundle.min.js`: the official JavaScript bundle.

`BootstrapBundledLibraryTests` pins checksums. Export removes unavailable source-map
references without rewriting the vendor CSS. Never edit vendor files by hand.

## Spacing

The preset scale is Bootstrap's native 0–12. Space supports a custom length,
initially 3.5 rem, with CSS generated only for that instance. Previously saved
project custom spacers remain supported. There is no global 13–24 extension.

Project colour, typography and supported utility overrides remain separate from
the vendor stylesheet. Sass, Node and npm never run during preview or publishing.

## Updating Bootstrap

Run `tools/bootstrap/update.sh <version>`, then update the registry version and
the pinned test checksums. Run the Bootstrap browser tests and review Foundry's
separate utility overrides against the new release.

## Retained experimental checkout

`sh tools/bootstrap/build-foundry.sh` builds the experimental Sass configuration
in `../bootstrap/foundry/dist` only. It does not copy files into Foundry or switch
the stylesheet registry. Install that checkout's dependencies with
`npm ci --ignore-scripts` before using it. The checkout and its remotes are retained.

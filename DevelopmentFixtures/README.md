# Development fixtures

`BrokenComponent.foundrydevpack` is intentionally invalid. Open it with a development build of Foundry to exercise the Developer panel. It must fail validation because its identifier is not lowercase reverse-DNS and its declared HTML template does not exist.

The fixture lives outside the app's synchronized `Foundry` source group, so it is not copied into shipping builds.

`EnableConditions.foundrydevpack` is a valid development component demonstrating the shared `enable` API with equality, numeric comparison, empty-value checks, and a zero-based indexed multi-control reference. A working copy may also be installed in `~/Library/Application Support/Foundry/Packs` for interactive testing.

`ThemeValues.foundrydevpack` demonstrates ordinary select controls requesting the named `colors`, `fontFamilies`, `fontSizes`, and `spacing` theme sources, including a two-value select array. It is also installed in the app-support Packs directory for interactive testing.

`ExpressionEngine.foundrydevpack` is an interactive showcase for inline arithmetic, operator precedence, numeric functions, comparisons, `&&`, `||`, `!`, indexed control values, `if`/`elseif`/`else`, and the mutually exclusive `canvas`, `preview`, and `published` environment values.

`ScopedAssets.foundrydevpack` demonstrates the asset dictionary contract. It publishes an individual file and a directory at page scope, publishes a shared directory once at site scope, and displays the resolved `asset`, `site`, `page`, and `path` template values.

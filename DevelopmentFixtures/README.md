# Development fixtures

`AppearanceToggle.foundrydevpack` provides Light, Dark and System buttons using `window.foundryAppearance.set(...)`. Enable **Light and Dark** in Site Settings and test in browser Preview or exported output. The canvas and single-appearance sites disable the buttons. Its own card changes colour too, so the effect is visible even on an otherwise empty page. It has no getter or selection indicator and does not access the API's private storage.

`BrokenPart.foundrydevpack` is intentionally invalid. Open it with a development build of Foundry to exercise the Developer panel. It must fail validation because its identifier is not lowercase reverse-DNS and its declared HTML template does not exist.

The fixture lives outside the app's synchronized `Foundry` source group, so it is not copied into shipping builds.

`EnableConditions.foundrydevpack` is a valid development part demonstrating the shared `enable` API with equality, numeric comparison, empty-value checks, and a zero-based indexed multi-control reference. A working copy may also be installed in `~/Library/Application Support/Foundry/Packs` for interactive testing.

`FrameworkValues.foundrydevpack` exercises dedicated framework colour controls. Removed framework Select controls have no replacement styling. Ordinary Select controls contain only explicitly declared options.

`ExpressionEngine.foundrydevpack` is an interactive showcase for inline arithmetic, operator precedence, numeric functions, comparisons, `&&`, `||`, `!`, indexed control values, `if`/`elseif`/`else`, and the mutually exclusive `canvas`, `preview`, and `published` environment values.

`ScopedAssets.foundrydevpack` demonstrates the asset dictionary contract. It publishes an individual file and a directory at page scope, publishes a shared directory once at site scope, and displays the resolved `asset`, `site`, `page`, and `path` template values.

# Foundry workspace notes

## Bootstrap 6 is the generated-site framework

Use Bootstrap 6's native markup, classes, component variants, theme classes,
colour names, tokens and defaults as the contract for generated sites.
Verify against the bundled Bootstrap 6 version and the official Bootstrap skills.
Do not assume Bootstrap 5 conventions still apply: a solid primary button uses
`btn btn-solid theme-primary`, not `btn btn-primary`.

Foundry may add identifiers, editing metadata and behaviour hooks. These must
preserve the underlying Bootstrap component. Inspector controls should select
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

## Built-in framework artwork

Always ask Gary for a supplied tile image when creating a built-in framework. Do not generate or substitute fallback artwork. See `.cursor/rules/framework-artwork.mdc`.

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

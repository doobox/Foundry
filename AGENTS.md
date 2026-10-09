# Foundry workspace notes

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

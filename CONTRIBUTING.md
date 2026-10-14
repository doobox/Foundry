# Contributing to Foundry

Foundry is under active development. For substantial changes, open an issue
first to discuss the problem and proposed approach.

## Getting started

Follow the [build instructions](README.md#build-from-source), then read
[ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](AGENTS.md) for the current
source layout and project conventions.

Use a branch for your changes and keep pull requests focused on a single
problem. Explain the user-visible change and how you verified it. Include
screenshots for interface changes and a small reproduction for bug fixes.

## Implementation guidance

- Keep views under `Foundry/UI/` and non-view code under `Foundry/Core/`.
- Route project mutations through the undo-aware editing layer.
- Use the bundled Bootstrap 6 version as the generated-site contract.
- Verify preview and export together when changing generated markup or styling.
- Add meaningful regression coverage for changes to model, rendering or package behaviour.
- Preserve upstream copyright notices and licences when modifying dependencies.

Build the Foundry scheme and run tests relevant to your change before submitting
a pull request. Note any checks you could not run and why.

The user guide and part developer documentation are maintained in
[their separate repository](https://github.com/doobox/foundry-docs). Changes to
those documents should follow that repository's contribution conventions.

## Reporting bugs

Include the macOS version, Xcode version or app revision, steps to reproduce,
expected behaviour and actual behaviour. Use a minimal sample project when
possible. Remove publishing credentials, personal data and private assets
before sharing a project or log.

Report security issues using [SECURITY.md](SECURITY.md).

## Contribution licensing

Unless explicitly agreed otherwise, contributions to Foundry's original code
and documentation are submitted under the repository's [MIT licence](LICENSE).
Only contribute material you have the right to distribute under those terms.
Third-party material must retain its applicable licence and attribution.

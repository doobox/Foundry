# Third-party notices

Foundry's root [MIT licence](LICENSE) applies to original Foundry code and
documentation. It does not replace the licences of third-party source,
libraries, runtime binaries or resources included in this repository or in a
built application. Preserve the applicable copyright, licence and notice
files when redistributing them.

This index points to retained notices and dependency sources. It is not a
replacement for the complete upstream licence texts or a declaration that
every bundled component is MIT-licensed.

## Website libraries

The following notices are retained in
`Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/`:

- [Bootstrap 6](Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/BOOTSTRAP-6-LICENSE.txt)
- [Bootstrap Icons](Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/BOOTSTRAP-ICONS-LICENSE.txt)
- [Alpine.js](Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/ALPINE-LICENSE.md)
- [GLightbox](Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/GLIGHTBOX-LICENSE.md)
- [GSAP](Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/GSAP-LICENSE.txt)

GSAP uses the [Standard No Charge GSAP License](https://gsap.com/standard-license/),
which includes restrictions on visual animation-building tools that compete
with Webflow's visual animation capabilities. Foundry's MIT licence grants no
additional rights to GSAP. Review the applicable upstream terms before changing
animation-building features or redistributing GSAP as part of a derivative.

Foundry currently exposes GSAP-driven Reveal effects through visual controls
for effect, distance, duration, delay and easing. Whether this use falls within
the permitted niche-tool use described in GSAP's FAQ remains unresolved. Obtain
confirmation for this integration or replace it before treating this dependency
as cleared for public distribution.

## Editor and Markdown libraries

- [CodeEditSourceEditor licence](Vendor/CodeEditSourceEditor/LICENSE.md)
- [CodeEditTextView licence](Vendor/CodeEditTextView/LICENSE.md)
- [CodeEditLanguages upstream repository](https://github.com/CodeEditApp/CodeEditLanguages)
- [CodeEditorView retained licence](Foundry/Resources/ThirdPartyLicenses/CODEEDITORVIEW-LICENSE.txt)
- [Swift Markdown licence](Foundry/Resources/ThirdPartyLicenses/SWIFT-MARKDOWN-LICENSE.txt)
  and [notice](Foundry/Resources/ThirdPartyLicenses/SWIFT-MARKDOWN-NOTICE.txt)
- [Swift cmark retained licence](Foundry/Resources/ThirdPartyLicenses/SWIFT-CMARK-LICENSE.txt)
- [Rearrange retained licence](Foundry/Resources/ThirdPartyLicenses/REARRANGE-LICENSE.txt)
- [TextStory licence](Foundry/Resources/ThirdPartyLicenses/TEXTSTORY-LICENSE.txt)
- [TextFormation licence](Foundry/Resources/ThirdPartyLicenses/TEXTFORMATION-LICENSE.txt)
- [SwiftTreeSitter licence](Foundry/Resources/ThirdPartyLicenses/SWIFT-TREE-SITTER-LICENSE.txt)
- [Tree-sitter licence](Foundry/Resources/ThirdPartyLicenses/TREE-SITTER-LICENSE.txt)
- [Swift Collections licence](Foundry/Resources/ThirdPartyLicenses/SWIFT-COLLECTIONS-LICENSE.txt)
- [Swift grammar retained by SwiftTreeSitter](Foundry/Resources/ThirdPartyLicenses/TREE-SITTER-SWIFT-LICENSE.txt)

Swift package dependencies and exact revisions are recorded in
`Foundry.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
The dependency graph also includes CodeEditSymbols, Swift Collections,
SwiftTreeSitter, Tree-sitter, TextFormation and TextStory. Their upstream
licences, and any notices required by their dependencies, remain applicable.

### Unresolved CodeEdit licences

The vendored CodeEditLanguages snapshot is tag `0.1.20`, commit
`331d5dbc5fc8513be5848fce8a2a312908f36a11`. It has no top-level licence file;
see [its vendor provenance](Vendor/CodeEditLanguages/FOUNDRY-VENDOR.md).
The retained `CodeLanguagesContainer.xcframework.zip` contains no licence or
notice files for its compiled grammars. Query resources are also vendored.

Upstream [issue #96](https://github.com/CodeEditApp/CodeEditLanguages/issues/96)
requests a licence and remains open as of 14 October 2026.
[Issue #94](https://github.com/CodeEditApp/CodeEditLanguages/issues/94) also asks
for clarification. Neither the Foundry MIT licence nor the CodeEditSourceEditor
MIT licence establishes redistribution rights for this separate dependency.

CodeEditSourceEditor additionally depends on CodeEditSymbols `0.2.3`.
The upstream issue flags this package as lacking a declared licence too, and
GitHub's licence endpoint returned no licence on review. The resolved `0.2.3`
checkout also contains no licence file or README licence statement. Confirm the rights to
both dependencies before publishing the vendored source or distributing the app.
If permission cannot be established, replace these dependencies with ones that
have explicit compatible licences. Do not add an assumed MIT licence on behalf
of their authors.

The package's licence, once established, still needs to be checked alongside the
licences and required notices of each included grammar.

## Publishing runtime

`Vendor/FoundryCurl/` contains the publishing runtime and retained licences for:

- [curl](Vendor/FoundryCurl/Licenses/curl.txt)
- [libssh2](Vendor/FoundryCurl/Licenses/libssh2.txt)
- [mbedTLS](Vendor/FoundryCurl/Licenses/mbedtls.txt)

See [the runtime build notes](Vendor/FoundryCurl/README.md) for pinned versions
and rebuilding instructions.

## PHP runtime

PHP is built from pinned upstream source by `scripts/build-php-runtime`.
The script stages PHP's complete licence as
`Foundry/PHPRuntime/PHP-LICENSE.txt`, which Xcode embeds with the runtime.
The staging directory is ignored by Git. See [Runtime/PHP/README.md](Runtime/PHP/README.md).

## Other resources

The public CA certificate bundle in `Foundry/Resources/cacert.pem` retains its
upstream attribution header. It is not a private signing key.

Check redistribution rights for artwork, fonts and other supplied assets before
adding them. Include their licence and attribution where required; do not assume
that an asset is covered by the app's MIT licence simply because it is stored
in this repository.

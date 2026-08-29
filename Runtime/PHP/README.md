# Foundry PHP runtime

Foundry previews PHP with a minimal, bundled `php-cgi`. It must never use PHP from `PATH`, Homebrew, or the operating system.

Run `scripts/build-php-runtime` on an Apple Silicon Mac with Xcode command-line tools and Rosetta 2 installed. If Bison 3 or newer is unavailable, the script builds its own pinned Bison 3.8.2 inside the temporary build directory. The script:

- downloads the pinned official PHP source archive over HTTPS;
- verifies its SHA-256 checksum before extracting it;
- builds isolated arm64 and x86_64 CGI executables against the macOS SDK;
- combines them into one universal executable;
- copies PHP's complete licence into the staged artifact; and
- writes the result to the ignored `RuntimeArtifacts/PHP` directory.

The intentionally small first configuration enables CGI plus core `ctype`, `filter`, `session`, and `tokenizer` functionality. Add an extension only with its build dependency, licence, architecture, signing, and runtime tests accounted for.

The staged files are inputs to Foundry's Xcode embedding/signing step; they are not source-controlled binaries.

Release artifacts default to `arm64 x86_64` and require Rosetta 2 when built on Apple Silicon. To create an arm64-only artifact for local development, run `FOUNDRY_PHP_ARCHITECTURES=arm64 scripts/build-php-runtime`. Single-architecture artifacts must not be used for a universal Foundry release.

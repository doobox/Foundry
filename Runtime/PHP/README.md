# Foundry PHP runtime

Foundry previews PHP with a minimal, bundled `php-cgi`. It must never use PHP from `PATH`, Homebrew, or the operating system.

Run `scripts/build-php-runtime` on an Apple silicon Mac with Xcode command-line tools installed. If Bison 3 or newer is unavailable, the script builds its own pinned Bison 3.8.2 inside the temporary build directory. The script:

- downloads the pinned official PHP source archive over HTTPS;
- verifies its SHA-256 checksum before extracting it;
- builds an arm64 CGI executable against the macOS SDK;
- copies PHP's complete licence into the staged artifact; and
- writes the result to the ignored `Foundry/PHPRuntime` staging directory, whose files Xcode embeds in the app's Resources directory.

The intentionally small first configuration enables CGI plus core `ctype`, `filter`, `session`, and `tokenizer` functionality. Add an extension only with its build dependency, licence, architecture, signing, and runtime tests accounted for.

The staged files are embedded and signed by Xcode; they are not source-controlled binaries. Foundry targets macOS 27, which supports Apple-silicon Macs only, so the runtime intentionally contains no x86_64 slice.

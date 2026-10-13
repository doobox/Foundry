#!/bin/sh
# Copies an official Bootstrap release into Foundry's built-in libraries bundle.
#
# Usage: tools/bootstrap/update.sh 6.0.0-alpha.1
#
# This updates the bundled assets. The npm tarball is fetched, its untouched
# dist CSS, source map and JS bundle are copied under versioned names, and the
# downloaded package is removed when the update finishes.
set -eu

version=${1:?usage: update.sh <bootstrap-version>}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
resources="$root/Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
upstream="$tmp/package"

echo "Fetching bootstrap@$version from the npm registry…"
curl -fsSL "https://registry.npmjs.org/bootstrap/-/bootstrap-$version.tgz" -o "$tmp/bootstrap.tgz"
mkdir -p "$upstream"
tar -xzf "$tmp/bootstrap.tgz" -C "$upstream" --strip-components=1

# Replace only official release CSS files.
find "$resources" -maxdepth 1 -name 'bootstrap-*.min.css' ! -name '*-foundry.min.css' -exec rm -f {} \;
rm -f "$resources"/bootstrap-*.bundle.min.js "$resources"/bootstrap.min.css.map
cp "$upstream/dist/css/bootstrap.min.css" "$resources/bootstrap-$version.min.css"
cp "$upstream/dist/css/bootstrap.min.css.map" "$resources/bootstrap.min.css.map"
cp "$upstream/dist/js/bootstrap.bundle.min.js" "$resources/bootstrap-$version.bundle.min.js"

shasum -a 256 "$resources/bootstrap-$version.min.css" "$resources/bootstrap-$version.bundle.min.js"
cat <<EOF

Copied Bootstrap $version. Next:
  1. Update the version in Foundry/Core/Rendering/Page/FoundryWebLibraryRegistry.swift.
  2. Update the version and checksums in FoundryTests/BootstrapBundledLibraryTests.swift.
  3. Run the Bootstrap browser tests (spacing, container, paragraph, live theme, editor tokens).
  4. Review BootstrapUtilityExtensionsCSS against the new release's utilities.
EOF

#!/bin/sh
# Build the retained experimental configuration without changing Foundry's bundle.
set -eu
app_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
bootstrap_root="$app_root/../bootstrap"
cd "$bootstrap_root"
npm run css-foundry
shasum -a 256 foundry/dist/bootstrap-foundry.min.css
echo "Experimental build only. Foundry continues to bundle the official Bootstrap CSS."
